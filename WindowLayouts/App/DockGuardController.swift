// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Gentle mode observes buttons; Strong mode additionally adjusts only mouse
/// movement. Button/key/scroll events are never swallowed or rewritten.
private final class DockGuardButtonObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var releaseTime: TimeInterval = 0
    private var pressedButtons: Set<Int64> = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let screens: [ScreenSnapshot]
    private let preferredID: String?
    private let preferences: DockGuardPreferences
    private var policy = DockGuardPolicy()
    private var warpFailed = false

    init(screens: [ScreenSnapshot], preferredID: String?, preferences: DockGuardPreferences) {
        self.screens = screens
        self.preferredID = preferredID
        self.preferences = preferences
    }

    func start() -> Bool {
        var types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .leftMouseUp, .rightMouseUp, .otherMouseUp]
        if preferences.strength == .strong { types.append(.mouseMoved) }
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(
            tap: preferences.strength == .strong ? .cghidEventTap : .cgSessionEventTap,
            place: .headInsertEventTap,
            options: preferences.strength == .strong ? .defaultTap : .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, context in
                if let context {
                    let observer = Unmanaged<DockGuardButtonObserver>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        // Runtime observes a disabled tap and suspends instead
                        // of continuing with incomplete resize protection.
                    } else if type == .mouseMoved {
                        observer.adjustMovement(event)
                    } else {
                        observer.lock.lock()
                        let button = event.getIntegerValueField(.mouseEventButtonNumber)
                        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                            observer.pressedButtons.insert(button)
                        } else {
                            observer.pressedButtons.remove(button)
                            observer.releaseTime = ProcessInfo.processInfo.systemUptime
                            observer.policy.inputReleased(at: observer.releaseTime)
                        }
                        observer.lock.unlock()
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            stop(); return false
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    var isEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    var lastRelease: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return releaseTime
    }
    var anyButtonDown: Bool {
        lock.lock(); defer { lock.unlock() }
        return !pressedButtons.isEmpty
    }

    private func adjustMovement(_ event: CGEvent) {
        lock.lock(); defer { lock.unlock() }
        guard !warpFailed else { return }
        let down = !pressedButtons.isEmpty || [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
        let corrected = policy.strongCorrection(
            point: event.location,
            deltaY: CGFloat(event.getIntegerValueField(.mouseEventDeltaY)),
            now: ProcessInfo.processInfo.systemUptime,
            screens: screens, preferredID: preferredID, mouseIsDown: down,
            bypass: event.flags.contains(preferences.bypassModifier.flag)
        )
        if let corrected {
            guard CGWarpMouseCursorPosition(corrected) == .success else {
                warpFailed = true; return
            }
            event.location = corrected
        }
    }

    var hasFailed: Bool {
        lock.lock(); defer { lock.unlock() }
        return warpFailed
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
    }
    deinit { stop() }
}

@MainActor
final class DockGuardController: ObservableObject {
    @Published private(set) var status = "Disabled"
    @Published private(set) var displays: [ScreenSnapshot] = []
    private let settingsStore: SettingsStore
    private var preferences = DockGuardPreferences()
    private var screens: [ScreenSnapshot] = []
    private var preferredID: String?
    private var policy = DockGuardPolicy()
    private var timer: Timer?
    private var buttons: DockGuardButtonObserver?
    private var subscriptions: Set<AnyCancellable> = []
    private var lastRelease: TimeInterval = 0
    private var lastPermissionCheck: TimeInterval = 0
    private var lastGeometryCheck: TimeInterval = 0

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        settingsStore.$library.map(\.dockGuard).removeDuplicates()
            .sink { [weak self] preferences in
                self?.preferences = preferences
                self?.refresh()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.stop(status: "Suspended during sleep") }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stop() }.store(in: &subscriptions)
    }

    func disableImmediately() {
        stop()
        _ = settingsStore.disableDockGuard()
    }

    func refresh() {
        stop()
        screens = ScreenService.snapshots()
        displays = screens
        guard preferences.enabled else { return }
        // A test host must not install a live pointer modifier using saved
        // user preferences while running the pure geometry/menu tests.
        guard NSClassFromString("XCTestCase") == nil else {
            status = "Suspended in test host"; return
        }
        if let persistentID = preferences.preferredDisplayID {
            preferredID = screens.first { $0.persistentID == persistentID }?.id
        } else {
            let builtIn = NSScreen.screens.first {
                let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                return CGDisplayIsBuiltin(id) != 0
            }
            let id = (builtIn?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
            preferredID = screens.first { $0.id == id }?.id
        }
        guard preferredID != nil else { status = "Suspended: preferred display is disconnected"; return }
        guard screens.count > 1 else { status = "Suspended: one display connected"; return }
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        guard orientation == "bottom" else { status = "Suspended: position the Dock at the bottom"; return }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            status = "Accessibility and input-event access required"; return
        }
        let observer = DockGuardButtonObserver(screens: screens, preferredID: preferredID, preferences: preferences)
        guard observer.start() else {
            status = "Input tap unavailable: check permissions or use Gentle mode"; return
        }
        buttons = observer
        lastPermissionCheck = ProcessInfo.processInfo.systemUptime
        lastGeometryCheck = lastPermissionCheck
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        status = preferences.strength == .strong
            ? "Active: Strong edge protection" : "Active: Gentle idle protection"
    }

    isolated deinit {
        timer?.invalidate()
        buttons?.stop()
    }

    private func stop(status: String = "Disabled") {
        timer?.invalidate(); timer = nil
        buttons?.stop(); buttons = nil
        policy.reset()
        self.status = status
    }

    private func tick() {
        guard preferences.enabled, let buttons else { stop(); return }
        guard buttons.isEnabled, !buttons.hasFailed else { stop(status: "Input observation paused: choose Check Dock Guard"); return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastGeometryCheck >= 2 {
            lastGeometryCheck = now
            let latest = ScreenService.snapshots()
            if !DockGuardPolicy.sameDisplayGeometry(screens, latest) {
                refresh()
                return
            }
        }
        if now - lastPermissionCheck >= 1 {
            lastPermissionCheck = now
            let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
            guard orientation == "bottom", AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
                stop(status: "Suspended: check permissions and bottom Dock position"); return
            }
        }
        if buttons.lastRelease > lastRelease {
            lastRelease = buttons.lastRelease
            policy.inputReleased(at: lastRelease)
        }
        guard let point = CGEvent(source: nil)?.location else { return }
        let mouseIsDown = buttons.anyButtonDown || [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
        let bypass = CGEventSource.flagsState(.combinedSessionState).contains(preferences.bypassModifier.flag)
        let corrected = preferences.strength == .strong ? policy.strongCorrection(
            point: point, deltaY: 0, now: now, screens: screens, preferredID: preferredID,
            mouseIsDown: mouseIsDown, bypass: bypass
        ) : policy.correction(
            point: point, now: now, screens: screens, preferredID: preferredID,
            mouseIsDown: mouseIsDown, bypass: bypass
        )
        if let corrected {
            if CGWarpMouseCursorPosition(corrected) != .success {
                stop(status: "Cursor adjustment failed: choose Check Dock Guard")
            }
        }
    }
}
