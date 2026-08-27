// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import SwiftUI

@MainActor
final class GreenButtonPanelController: ObservableObject {
    private static let pointerInterval: TimeInterval = 0.1
    private static let dismissalDelay: TimeInterval = 0.55
    private static let triggerInset: CGFloat = 3

    private let settingsStore: SettingsStore
    private let windowController: WindowLayoutsController
    private let activeWindowObserver: ActiveWindowObserver
    private var settingsObservation: AnyCancellable?
    private var targetObservation: AnyCancellable?
    private var pointerTimer: Timer?
    private var panel: SafeLayoutPanel?
    private var target: ActiveWindowSnapshot?
    private var lastInteraction = Date.distantPast
    private var enabled = false

    convenience init(
        settingsStore: SettingsStore,
        windowController: WindowLayoutsController
    ) {
        self.init(
            settingsStore: settingsStore,
            windowController: windowController,
            activeWindowObserver: ActiveWindowObserver()
        )
    }

    init(
        settingsStore: SettingsStore,
        windowController: WindowLayoutsController,
        activeWindowObserver: ActiveWindowObserver
    ) {
        self.settingsStore = settingsStore
        self.windowController = windowController
        self.activeWindowObserver = activeWindowObserver

        settingsObservation = settingsStore.$library.sink { [weak self] library in
            self?.apply(library: library)
        }
        targetObservation = activeWindowObserver.$target.sink { [weak self] target in
            self?.accept(target: target)
        }
    }

    private func apply(library: LayoutLibrary) {
        if library.greenButtonPanelEnabled {
            startIfNeeded()
            repositionVisiblePanel()
        } else {
            stopIfNeeded()
        }
    }

    private func startIfNeeded() {
        guard !enabled else { return }
        enabled = true
        activeWindowObserver.start()
        pointerTimer = Timer.scheduledTimer(
            timeInterval: Self.pointerInterval,
            target: self,
            selector: #selector(pointerTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopIfNeeded() {
        guard enabled else {
            hidePanel()
            return
        }
        enabled = false
        pointerTimer?.invalidate()
        pointerTimer = nil
        activeWindowObserver.stop()
        target = nil
        hidePanel()
    }

    private func accept(target newTarget: ActiveWindowSnapshot?) {
        let identityChanged = target?.processIdentifier != newTarget?.processIdentifier
            || target?.windowToken != newTarget?.windowToken
        target = newTarget
        if identityChanged || newTarget == nil {
            hidePanel()
        } else {
            repositionVisiblePanel()
        }
    }

    @objc private func pointerTimerFired() {
        guard enabled, let target else {
            hidePanel()
            return
        }
        guard let anchor = ScreenService.appKitRect(
            fromAccessibility: target.greenButtonFrame
        ) else {
            hidePanel()
            return
        }

        let pointer = NSEvent.mouseLocation
        let overTrigger = anchor.insetBy(
            dx: -Self.triggerInset,
            dy: -Self.triggerInset
        ).contains(pointer)
        let overPanel = panel?.isVisible == true && panel?.frame.contains(pointer) == true

        if overTrigger || overPanel {
            lastInteraction = Date()
            if panel?.isVisible != true {
                showPanel(for: target)
            } else {
                panel?.maintainFrontmostPosition()
            }
        } else if panel?.isVisible == true,
                  Date().timeIntervalSince(lastInteraction) >= Self.dismissalDelay {
            hidePanel()
        }
    }

    private func showPanel(for target: ActiveWindowSnapshot) {
        guard let placement = LayoutPanelPlacementEngine.placement(
            beside: target.greenButtonFrame,
            requestedSize: settingsStore.library.layoutPanelSize.panelSize,
            in: target.usableFrame
        ),
        let appKitFrame = ScreenService.appKitRect(
            fromAccessibility: placement.frame
        ) else { return }

        let panel = panel ?? makePanel(contentSize: appKitFrame.size)
        self.panel = panel
        panel.present(frame: appKitFrame)
    }

    private func repositionVisiblePanel() {
        guard panel?.isVisible == true, let target else { return }
        guard let placement = LayoutPanelPlacementEngine.placement(
            beside: target.greenButtonFrame,
            requestedSize: settingsStore.library.layoutPanelSize.panelSize,
            in: target.usableFrame
        ),
        let appKitFrame = ScreenService.appKitRect(
            fromAccessibility: placement.frame
        ) else {
            hidePanel()
            return
        }
        guard let panel,
              !LayoutEngine.approximatelyEqual(
                  panel.frame,
                  appKitFrame,
                  tolerance: 0.5
              ) else { return }
        // Do not force an immediate AppKit display/layout pass from an AX
        // observation callback. SwiftUI may already be laying out the hosted
        // content, and setFrame(display: true) can recursively enter it.
        panel.setFrame(appKitFrame, display: false)
    }

    private func makePanel(contentSize: CGSize) -> SafeLayoutPanel {
        let panel = SafeLayoutPanel(contentSize: contentSize)
        let hostingView = NSHostingView(
            rootView: GreenButtonLayoutPanelView(
                controller: windowController,
                settingsStore: settingsStore,
                perform: { [weak self] action in
                    self?.hidePanel()
                    self?.windowController.perform(action)
                },
                fillScreen: { [weak self] group in
                    self?.hidePanel()
                    self?.windowController.fillScreen(using: group)
                },
                moveToSpace: { [weak self] direction in
                    let processIdentifier = self?.target?.processIdentifier
                    self?.hidePanel()
                    guard let processIdentifier else { return }
                    self?.windowController.moveWindowToSpace(
                        direction,
                        targetingProcessIdentifier: processIdentifier
                    )
                },
                close: { [weak self] in
                    self?.hidePanel()
                },
                disable: { [weak self] in
                    self?.windowController.disableOptionalOverlays()
                }
            )
        )
        // Keep SwiftUI's intrinsic sizing from feeding back into the fixed
        // NSPanel while AppKit is already laying out the window.
        hostingView.sizingOptions = []
        hostingView.frame = CGRect(origin: .zero, size: contentSize)
        hostingView.autoresizingMask = [.width, .height]

        let container = NSView(frame: CGRect(origin: .zero, size: contentSize))
        container.autoresizesSubviews = true
        container.addSubview(hostingView)
        panel.contentView = container
        return panel
    }

    private func hidePanel() {
        panel?.conceal()
    }
}

@MainActor
final class SafeLayoutPanel: NSPanel {
    init(contentSize: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isFloatingPanel = true
        // Set this after isFloatingPanel because AppKit otherwise restores the
        // floating level. Match the public level reserved for popup menus so
        // the compact, visible Window Layouts surface has menu-level stacking
        // priority without using a private or arbitrary window level.
        level = .popUpMenu
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none

        // An unmapped panel must never own an invisible input region.
        ignoresMouseEvents = true
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(frame: CGRect) {
        ignoresMouseEvents = true
        setFrame(frame, display: false)
        alphaValue = 1
        orderFrontRegardless()
        // Input begins only after the complete rectangular content is visible.
        ignoresMouseEvents = false
    }

    func maintainFrontmostPosition() {
        guard isVisible else { return }
        orderFrontRegardless()
    }

    func conceal() {
        // Stop accepting input before removing the visible surface.
        ignoresMouseEvents = true
        orderOut(nil)
    }
}
