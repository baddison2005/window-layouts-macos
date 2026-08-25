// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

nonisolated struct ActiveWindowSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowToken: UInt
    let windowFrame: CGRect
    let greenButtonFrame: CGRect
    let usableFrame: CGRect
}

actor ActiveWindowSnapshotService {
    private let ownProcessIdentifier: pid_t

    init(ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    func snapshot(screens: [ScreenSnapshot]) -> ActiveWindowSnapshot? {
        guard AXIsProcessTrusted(), !screens.isEmpty else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(
            systemWide,
            WindowAccessibilityService.messagingTimeout
        )
        let axApplication = elementAttribute(
            kAXFocusedApplicationAttribute as CFString,
            of: systemWide
        )
        var axProcessIdentifier: pid_t?
        if let axApplication {
            var processIdentifier: pid_t = 0
            if AXUIElementGetPid(axApplication, &processIdentifier) == .success {
                axProcessIdentifier = processIdentifier
            }
        }
        guard let processIdentifier = FocusedApplicationSelection.processIdentifier(
            axFocusedProcessIdentifier: axProcessIdentifier,
            workspaceFrontmostProcessIdentifier: NSWorkspace.shared
                .frontmostApplication?
                .processIdentifier
        ) else { return nil }
        let application = axApplication.flatMap {
            axProcessIdentifier == processIdentifier ? $0 : nil
        } ?? AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(
            application,
            WindowAccessibilityService.messagingTimeout
        )

        guard processIdentifier != ownProcessIdentifier,
              let window = elementAttribute(
                  kAXFocusedWindowAttribute as CFString,
                  of: application
              ) else { return nil }
        _ = AXUIElementSetMessagingTimeout(
            window,
            WindowAccessibilityService.messagingTimeout
        )

        guard stringAttribute(kAXRoleAttribute as CFString, of: window)
                == (kAXWindowRole as String) else { return nil }
        if let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: window),
           subrole != (kAXStandardWindowSubrole as String) {
            return nil
        }
        guard boolAttribute(kAXMinimizedAttribute as CFString, of: window) != true,
              isSettable(kAXPositionAttribute as CFString, of: window),
              isSettable(kAXSizeAttribute as CFString, of: window),
              let windowFrame = frame(of: window),
              let screen = ScreenGeometryResolver.screen(
                  containing: windowFrame,
                  among: screens
              ),
              ScreenGeometryResolver.allowsGreenButtonPanel(
                  for: windowFrame,
                  on: screen
              ),
              let greenButton = elementAttribute(
                  kAXFullScreenButtonAttribute as CFString,
                  of: window
              ) ?? elementAttribute(
                  kAXZoomButtonAttribute as CFString,
                  of: window
              ),
              let greenButtonFrame = frame(of: greenButton),
              greenButtonFrame.width > 0,
              greenButtonFrame.height > 0 else {
            return nil
        }

        return ActiveWindowSnapshot(
            processIdentifier: processIdentifier,
            windowToken: CFHash(window),
            windowFrame: windowFrame,
            greenButtonFrame: greenButtonFrame,
            usableFrame: screen.visibleFrame
        )
    }

    private func elementAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func stringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    private func isSettable(_ attribute: CFString, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success
            && settable.boolValue
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        let axPosition = unsafeBitCast(positionValue, to: AXValue.self)
        let axSize = unsafeBitCast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(axPosition) == .cgPoint,
              AXValueGetValue(axPosition, .cgPoint, &position),
              AXValueGetType(axSize) == .cgSize,
              AXValueGetValue(axSize, .cgSize, &size),
              [position.x, position.y, size.width, size.height].allSatisfy(\.isFinite),
              size.width > 0,
              size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }
}

@MainActor
final class ActiveWindowObserver: ObservableObject {
    @Published private(set) var target: ActiveWindowSnapshot?

    private let snapshotService: ActiveWindowSnapshotService
    private var enabled = false
    private var refreshInFlight = false
    private var refreshPending = false
    private var refreshGeneration: UInt = 0
    private var fallbackTimer: Timer?
    private var axObserver: AXObserver?
    private var observedIdentity: (pid_t, UInt)?

    init(snapshotService: ActiveWindowSnapshotService = ActiveWindowSnapshotService()) {
        self.snapshotService = snapshotService
    }

    func start() {
        guard !enabled else { return }
        refreshGeneration &+= 1
        enabled = true
        installWorkspaceObservers()
        fallbackTimer = Timer.scheduledTimer(
            timeInterval: 0.35,
            target: self,
            selector: #selector(observationTimerFired),
            userInfo: nil,
            repeats: true
        )
        refresh()
    }

    func stop() {
        guard enabled else { return }
        refreshGeneration &+= 1
        enabled = false
        refreshInFlight = false
        refreshPending = false
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        removeWorkspaceObservers()
        tearDownAXObserver()
        target = nil
    }

    func refresh() {
        guard enabled else { return }
        guard !refreshInFlight else {
            refreshPending = true
            return
        }
        refreshInFlight = true
        let generation = refreshGeneration
        let screens = ScreenService.snapshots()
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await snapshotService.snapshot(screens: screens)
            accept(snapshot, generation: generation)
        }
    }

    fileprivate func receiveAXNotification() {
        refresh()
    }

    @objc private func observationTimerFired() {
        refresh()
    }

    @objc private func observedEnvironmentChanged() {
        refresh()
    }

    private func accept(_ snapshot: ActiveWindowSnapshot?, generation: UInt) {
        guard enabled, generation == refreshGeneration else { return }
        refreshInFlight = false
        target = snapshot
        configureAXObserver(for: snapshot)
        if refreshPending {
            refreshPending = false
            refresh()
        }
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification,
        ] {
            center.addObserver(
                self,
                selector: #selector(observedEnvironmentChanged),
                name: name,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(observedEnvironmentChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func configureAXObserver(for target: ActiveWindowSnapshot?) {
        guard let target else {
            tearDownAXObserver()
            return
        }
        let identity = (target.processIdentifier, target.windowToken)
        if let observedIdentity,
           observedIdentity.0 == identity.0,
           observedIdentity.1 == identity.1 {
            return
        }
        tearDownAXObserver()

        var observer: AXObserver?
        guard AXObserverCreate(
            target.processIdentifier,
            activeWindowAXCallback,
            &observer
        ) == .success,
        let observer else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let application = AXUIElementCreateApplication(target.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(
            application,
            WindowAccessibilityService.messagingTimeout
        )
        _ = AXObserverAddNotification(
            observer,
            application,
            kAXFocusedWindowChangedNotification as CFString,
            context
        )

        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            let window = unsafeBitCast(focusedValue, to: AXUIElement.self)
            for notification in [
                kAXMovedNotification,
                kAXResizedNotification,
                kAXWindowMiniaturizedNotification,
                kAXUIElementDestroyedNotification,
            ] {
                _ = AXObserverAddNotification(
                    observer,
                    window,
                    notification as CFString,
                    context
                )
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        axObserver = observer
        observedIdentity = identity
    }

    private func tearDownAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(axObserver),
                .commonModes
            )
        }
        axObserver = nil
        observedIdentity = nil
    }
}

private let activeWindowAXCallback: AXObserverCallback = {
    _, _, _, context in
    guard let context else { return }
    let observer = Unmanaged<ActiveWindowObserver>
        .fromOpaque(context)
        .takeUnretainedValue()
    Task { @MainActor in
        observer.receiveAXNotification()
    }
}
