// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import OSLog

@MainActor
final class MenuBarRevealController: NSObject {
    private let settingsStore: SettingsStore
    private var subscriptions: Set<AnyCancellable> = []
    private var preferences = MenuBarRevealPreferences()
    private var displays: [MenuBarRevealDisplay] = []
    private var converter: ScreenCoordinateConverter?
    private var statusItem: NSStatusItem?
    private var hold: (display: MenuBarRevealDisplay, popover: NSPopover)?
    private var timer: Timer?
    private var policy = MenuBarRevealPolicy()
    private var sessionActive = true
    private var displayAwake = true
    var isWindowActionRunning = false {
        didSet {
            if isWindowActionRunning { releaseMenuBar() }
        }
    }

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()

        settingsStore.$library.map(\.menuBarReveal).removeDuplicates()
            .sink { [weak self] preferences in
                self?.preferences = preferences
                self?.refresh()
            }.store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.policy.resetHover() }.store(in: &subscriptions)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.releaseMenuBar() }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.sessionActive = notification.name == NSWorkspace.sessionDidBecomeActiveNotification
                self?.refresh()
            }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.screensDidWakeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.displayAwake = notification.name == NSWorkspace.screensDidWakeNotification
                self?.refresh()
            }.store(in: &subscriptions)
    }

    isolated deinit { stop() }

    func disableImmediately() {
        stop()
        settingsStore.disableMenuBarReveal()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        releaseMenuBar()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func refresh() {
        guard preferences.enabled, sessionActive, displayAwake,
              NSClassFromString("XCTestCase") == nil else {
            stop()
            return
        }

        let screens = NSScreen.screens
        guard let referenceTop = ScreenCoordinateConverter.referenceTop(forAppKitFrames: screens.map(\.frame))
        else {
            stop()
            return
        }

        let converter = ScreenCoordinateConverter(referenceTop: referenceTop)
        let displays = screens.map { screen in
            let topInset = screen.safeAreaInsets.top
            let topAreas = topInset > 0
                ? [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
                : [screen.frame]
            return MenuBarRevealDisplay(
                frame: converter.accessibilityRect(fromAppKit: screen.frame),
                topAreas: topAreas.map { converter.accessibilityRect(fromAppKit: $0) },
                menuBarHeight: max(NSStatusBar.system.thickness, topInset)
            )
        }
        if self.converter != converter {
            releaseMenuBar()
        } else if let heldFrame = hold?.display.frame {
            // Screen ordering and changes elsewhere must not interrupt this hold.
            if let updated = displays.first(where: { $0.frame == heldFrame }) {
                hold?.display = updated
            } else {
                finishHold()
            }
        }
        self.converter = converter
        self.displays = displays
        installStatusItem()
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.samplePointer() }
        }
        timer.tolerance = 0.005
        self.timer = timer
        // Pause during AppKit menu tracking.
        RunLoop.main.add(timer, forMode: .default)
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }
        let title = String(localized: "Reveal Menu Bar")
        button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: title)
        if button.image == nil { button.title = title }
        button.toolTip = title
        button.target = self
        button.action = #selector(toggleFromStatusItem(_:))
        statusItem = item
    }

    @objc private func toggleFromStatusItem(_ button: NSStatusBarButton) {
        if hold?.popover.isShown == true {
            releaseMenuBar()
        } else if let converter, !isWindowActionRunning {
            finishHold()
            let pointer = converter.accessibilityPoint(fromAppKit: NSEvent.mouseLocation)
            if let display = displays.first(where: { $0.frame.contains(pointer) }) {
                holdMenuBar(on: display, using: button, time: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private var inputInUse: Bool {
        isWindowActionRunning || NSEvent.pressedMouseButtons != 0
            || !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private func samplePointer() {
        guard let converter, let button = statusItem?.button else { return }
        let pointer = converter.accessibilityPoint(fromAppKit: NSEvent.mouseLocation)
        let now = ProcessInfo.processInfo.systemUptime
        let distance = preferences.activationDistance
        let display = displays.first { $0.frame.contains(pointer) }
        // Keep tracking the pointer while the current bar counts down, so an
        // intentional dwell on another screen can be served after release.
        if let hold {
            if !hold.popover.isShown {
                finishHold()
                policy.allowRetryAfterDismissal(on: hold.display.frame, at: now)
                AppDiagnostics.overlays.debug("Menu bar popover closed before its hold expired.")
            } else if !isOnDisplay(hold.popover.contentViewController?.view.window, hold.display) {
                finishHold()
                AppDiagnostics.overlays.debug("Menu bar popover left the requested display.")
            } else if policy.shouldRelease(
                pointerInHoldZone: hold.display.containsHoldPoint(pointer, distance: distance),
                time: now,
                delay: preferences.hideDelaySeconds
            ) {
                finishHold()
            }
        }

        let hoverReady = policy.hoverReady(
            pointer: pointer, time: now, display: display,
            distance: distance, inputInUse: inputInUse
        )
        guard hold == nil, hoverReady, let display else { return }
        holdMenuBar(on: display, using: button, time: now)
    }

    private func isOnDisplay(_ window: NSWindow?, _ display: MenuBarRevealDisplay) -> Bool {
        guard let converter, let screen = window?.screen else { return false }
        return converter.accessibilityRect(fromAppKit: screen.frame) == display.frame
    }

    private func holdMenuBar(on display: MenuBarRevealDisplay, using button: NSStatusBarButton, time: TimeInterval) {
        guard isOnDisplay(button.window, display) else { return }
        let content = MenuBarRevealContentView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.animates = false
        popover.behavior = .applicationDefined
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown, let window = content.window else {
            if popover.isShown { popover.close() }
            policy.recordRevealAttempt(at: time, canRetry: true)
            AppDiagnostics.overlays.debug("Menu bar popover could not attach. A hover can retry once.")
            return
        }

        policy.recordRevealAttempt(at: time)
        guard window.ignoresMouseEvents, window.alphaValue == 0, isOnDisplay(window, display) else {
            popover.close()
            AppDiagnostics.overlays.debug("Menu bar popover failed its display or input-safety check.")
            return
        }
        hold = (display, popover)
    }

    private func finishHold() {
        if let popover = hold?.popover, popover.isShown { popover.close() }
        hold = nil
        policy.resetReleaseDelay()
    }

    private func releaseMenuBar() {
        finishHold()
        policy = MenuBarRevealPolicy()
    }
}

@MainActor
final class MenuBarRevealContentView: NSView {
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Configure the AppKit popover window before it can be displayed.
        newWindow?.ignoresMouseEvents = true
        newWindow?.alphaValue = 0
        super.viewWillMove(toWindow: newWindow)
    }
}
