// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

nonisolated enum WindowAction: Equatable, Sendable {
    case fixed(FixedLayout)
    case custom(LayoutDefinition)
    case center
    case maximize
    case restore
    case moveToPreviousMonitor
    case moveToNextMonitor

    var name: String {
        switch self {
        case .fixed(let layout): layout.name
        case .custom(let layout): layout.name
        case .center: String(localized: "Center")
        case .maximize: String(localized: "Maximize")
        case .restore: String(localized: "Restore")
        case .moveToPreviousMonitor: String(localized: "Move to Previous Monitor")
        case .moveToNextMonitor: String(localized: "Move to Next Monitor")
        }
    }
}

nonisolated struct WindowDragSession: Hashable, Sendable {
    fileprivate let id: UUID
}

nonisolated struct WindowDragSnapshot: Equatable, Sendable {
    let session: WindowDragSession
    let processIdentifier: pid_t
    let frame: CGRect
}

nonisolated enum WindowAccessibilityError: Error, Equatable, LocalizedError, Sendable {
    case permissionRequired
    case noFocusedApplication
    case ownApplicationFocused
    case noFocusedWindow
    case unsupportedWindow
    case minimizedWindow
    case fullScreenWindow
    case windowCannotBeMovedOrResized
    case invalidWindowGeometry
    case noUsableScreen
    case noEligibleWindows
    case noOtherMonitor
    case noRestoreFrame
    case invalidDragSession
    case targetTimedOut(operation: String)
    case accessibilityFailure(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            String(localized: "Accessibility access is required.")
        case .noFocusedApplication:
            String(localized: "No application is currently focused.")
        case .ownApplicationFocused:
            String(localized: "Choose a window in another application first.")
        case .noFocusedWindow:
            String(localized: "The focused application has no eligible window.")
        case .unsupportedWindow:
            String(localized: "The focused item is not a standard application window.")
        case .minimizedWindow:
            String(localized: "The focused window is minimized.")
        case .fullScreenWindow:
            String(localized: "Native full-screen windows are not supported.")
        case .windowCannotBeMovedOrResized:
            String(localized: "The focused window cannot be moved and resized through Accessibility.")
        case .invalidWindowGeometry:
            String(localized: "The focused window reported invalid geometry.")
        case .noUsableScreen:
            String(localized: "No usable display contains the focused window.")
        case .noEligibleWindows:
            String(localized: "The target display has no eligible visible windows.")
        case .noOtherMonitor:
            String(localized: "No other display is available.")
        case .noRestoreFrame:
            String(localized: "No original frame has been saved for this window.")
        case .invalidDragSession:
            String(localized: "The dragged window is no longer available.")
        case .targetTimedOut:
            String(localized: "The focused application did not respond in time.")
        case .accessibilityFailure:
            String(localized: "The focused application could not complete the window operation.")
        }
    }
}

actor WindowAccessibilityService {
    static let messagingTimeout: Float = 0.25
    private static let frameVerificationTolerance: CGFloat = 1
    private static let initialVerificationDelay = Duration.milliseconds(60)
    private static let displayTransitionStepDelay = Duration.milliseconds(50)
    private static let displaySettleDelay = Duration.milliseconds(220)
    private static let displayHandoffDelay = Duration.milliseconds(350)

    private struct FocusedWindow {
        let element: AXUIElement
        let processIdentifier: pid_t
    }

    private struct EligibleWindow {
        let window: FocusedWindow
        let frame: CGRect
    }

    private struct RestoreEntry {
        let processIdentifier: pid_t
        let element: AXUIElement
        let originalFrame: CGRect
        var lastAppliedFrame: CGRect?
        var lastAppliedLayout: NormalizedRect?
    }

    private var restoreEntries: [RestoreEntry] = []
    private var dragWindows: [UUID: FocusedWindow] = [:]

    func perform(
        _ action: WindowAction,
        processIdentifier: pid_t? = nil,
        screens: [ScreenSnapshot],
        padding: CGFloat = 0,
        knownLayouts: [NormalizedRect] = FixedLayout.allCases.map(\.normalizedRect)
    ) async throws {
        guard AXIsProcessTrusted() else {
            throw WindowAccessibilityError.permissionRequired
        }

        pruneStaleRestoreEntries()
        let window: FocusedWindow
        if let processIdentifier {
            window = try focusedWindow(processIdentifier: processIdentifier)
        } else {
            window = try focusedWindow()
        }
        try await perform(
            action,
            for: window,
            screens: screens,
            padding: padding,
            knownLayouts: knownLayouts
        )
    }

    func fillScreen(
        using group: WindowFillGroup,
        processIdentifier: pid_t? = nil,
        screens: [ScreenSnapshot],
        padding: CGFloat = 0
    ) async throws -> WindowFillResult {
        guard AXIsProcessTrusted() else {
            throw WindowAccessibilityError.permissionRequired
        }
        guard !screens.isEmpty else {
            throw WindowAccessibilityError.noUsableScreen
        }
        guard !group.layouts.isEmpty else {
            throw WindowAccessibilityError.noEligibleWindows
        }

        pruneStaleRestoreEntries()
        let anchor: FocusedWindow
        if let processIdentifier {
            anchor = try focusedWindow(processIdentifier: processIdentifier)
        } else {
            anchor = try focusedWindow()
        }
        let anchorFrame = try frame(of: anchor.element)
        if ScreenGeometryResolver.isLikelyNativeFullScreen(
            anchorFrame,
            among: screens
        ), !matchesLastAppliedFrame(anchorFrame, for: anchor) {
            throw WindowAccessibilityError.fullScreenWindow
        }
        guard let targetScreen = ScreenGeometryResolver.screen(
            containing: anchorFrame,
            among: screens
        ) else {
            throw WindowAccessibilityError.noUsableScreen
        }

        let eligibleWindows = try visibleEligibleWindows(
            on: targetScreen,
            among: screens
        )
        guard !eligibleWindows.isEmpty else {
            throw WindowAccessibilityError.noEligibleWindows
        }

        let layoutIndices = VisibleWindowMatching.layoutIndices(
            windowCount: eligibleWindows.count,
            layoutCount: group.layouts.count
        )
        var appliedCount = 0
        var skippedCount = 0

        for (eligible, layoutIndex) in zip(eligibleWindows, layoutIndices) {
            do {
                try validateEligibility(of: eligible.window.element)
                let currentFrame = try frame(of: eligible.window.element)
                guard !ScreenGeometryResolver.isLikelyNativeFullScreen(
                    currentFrame,
                    among: screens
                ) else {
                    skippedCount += 1
                    continue
                }
                rememberOriginalFrame(currentFrame, for: eligible.window)
                let layout = group.layouts[layoutIndex]
                let destination = LayoutEngine.rectangle(
                    for: layout,
                    in: targetScreen.visibleFrame,
                    padding: padding
                )
                let appliedFrame = try await setFrame(
                    destination,
                    of: eligible.window.element,
                    constrainedTo: targetScreen.visibleFrame
                )
                recordAppliedFrame(
                    appliedFrame,
                    intendedLayout: layout,
                    for: eligible.window
                )
                appliedCount += 1
            } catch WindowAccessibilityError.permissionRequired {
                throw WindowAccessibilityError.permissionRequired
            } catch {
                skippedCount += 1
            }
        }

        guard appliedCount > 0 else {
            throw WindowAccessibilityError.noEligibleWindows
        }
        return WindowFillResult(
            appliedCount: appliedCount,
            skippedCount: skippedCount
        )
    }

    func beginDragSession(screens: [ScreenSnapshot]) throws -> WindowDragSnapshot {
        guard AXIsProcessTrusted() else {
            throw WindowAccessibilityError.permissionRequired
        }
        guard !screens.isEmpty else {
            throw WindowAccessibilityError.noUsableScreen
        }

        let window = try focusedWindow()
        let currentFrame = try frame(of: window.element)
        if ScreenGeometryResolver.isLikelyNativeFullScreen(currentFrame, among: screens),
           !matchesLastAppliedFrame(currentFrame, for: window) {
            throw WindowAccessibilityError.fullScreenWindow
        }
        guard ScreenGeometryResolver.screen(
            containing: currentFrame,
            among: screens
        ) != nil else {
            throw WindowAccessibilityError.noUsableScreen
        }

        let session = WindowDragSession(id: UUID())
        dragWindows[session.id] = window
        return WindowDragSnapshot(
            session: session,
            processIdentifier: window.processIdentifier,
            frame: currentFrame
        )
    }

    func frame(for dragSession: WindowDragSession) throws -> CGRect {
        guard AXIsProcessTrusted() else {
            dragWindows.removeValue(forKey: dragSession.id)
            throw WindowAccessibilityError.permissionRequired
        }
        guard let window = dragWindows[dragSession.id] else {
            throw WindowAccessibilityError.invalidDragSession
        }

        var currentProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(window.element, &currentProcessIdentifier) == .success,
              currentProcessIdentifier == window.processIdentifier else {
            dragWindows.removeValue(forKey: dragSession.id)
            throw WindowAccessibilityError.invalidDragSession
        }
        do {
            try validateEligibility(of: window.element)
            return try frame(of: window.element)
        } catch {
            dragWindows.removeValue(forKey: dragSession.id)
            throw error
        }
    }

    func cancelDragSession(_ dragSession: WindowDragSession) {
        dragWindows.removeValue(forKey: dragSession.id)
    }

    func cancelAllDragSessions() {
        dragWindows.removeAll()
    }

    func perform(
        _ action: WindowAction,
        dragSession: WindowDragSession,
        destinationScreenID: String? = nil,
        screens: [ScreenSnapshot],
        padding: CGFloat = 0,
        knownLayouts: [NormalizedRect] = FixedLayout.allCases.map(\.normalizedRect)
    ) async throws {
        guard AXIsProcessTrusted() else {
            dragWindows.removeValue(forKey: dragSession.id)
            throw WindowAccessibilityError.permissionRequired
        }
        guard let window = dragWindows.removeValue(forKey: dragSession.id) else {
            throw WindowAccessibilityError.invalidDragSession
        }
        pruneStaleRestoreEntries()
        try validateEligibility(of: window.element)
        try await perform(
            action,
            for: window,
            destinationScreenID: destinationScreenID,
            screens: screens,
            padding: padding,
            knownLayouts: knownLayouts
        )
    }

    private func perform(
        _ action: WindowAction,
        for window: FocusedWindow,
        destinationScreenID: String? = nil,
        screens: [ScreenSnapshot],
        padding: CGFloat,
        knownLayouts: [NormalizedRect]
    ) async throws {
        let currentFrame = try frame(of: window.element)
        if ScreenGeometryResolver.isLikelyNativeFullScreen(currentFrame, among: screens),
           !matchesLastAppliedFrame(currentFrame, for: window) {
            throw WindowAccessibilityError.fullScreenWindow
        }

        if case .restore = action {
            try await restore(window: window, screens: screens)
            return
        }

        guard let currentScreen = ScreenGeometryResolver.screen(
            containing: currentFrame,
            among: screens
        ) else {
            throw WindowAccessibilityError.noUsableScreen
        }
        guard let actionScreen = ScreenGeometryResolver.destinationScreen(
            for: currentFrame,
            preferredScreenID: destinationScreenID,
            among: screens
        ) else {
            throw WindowAccessibilityError.noUsableScreen
        }

        rememberOriginalFrame(currentFrame, for: window)
        let destination: CGRect
        var destinationUsableFrame = actionScreen.visibleFrame
        var transfersDisplay = currentScreen.id != actionScreen.id
        var intendedLayout: NormalizedRect? = nil
        switch action {
        case .fixed(let layout):
            intendedLayout = layout.normalizedRect
            destination = LayoutEngine.rectangle(
                for: layout.normalizedRect,
                in: actionScreen.visibleFrame,
                padding: padding
            )
        case .custom(let layout):
            intendedLayout = layout.normalizedRect
            destination = LayoutEngine.rectangle(
                for: layout.normalizedRect,
                in: actionScreen.visibleFrame,
                padding: padding
            )
        case .center:
            destination = LayoutEngine.centered(
                frame: currentFrame,
                in: actionScreen.visibleFrame
            )
        case .maximize:
            destination = actionScreen.visibleFrame
            intendedLayout = LayoutEngine.normalizedGeometry(
                of: destination,
                in: actionScreen.visibleFrame
            )
        case .restore:
            destination = currentFrame
        case .moveToPreviousMonitor, .moveToNextMonitor:
            transfersDisplay = true
            let offset: Int
            switch action {
            case .moveToPreviousMonitor:
                offset = -1
            default:
                offset = 1
            }
            guard let destinationScreen = ScreenGeometryResolver.adjacentScreen(
                to: currentScreen.id,
                offset: offset,
                among: screens
            ) else {
                throw WindowAccessibilityError.noOtherMonitor
            }
            destinationUsableFrame = destinationScreen.visibleFrame
            let preservedLayout = rememberedLayout(
                matching: currentFrame,
                for: window
            ) ?? MonitorTransfer.recognizedLayout(
                for: currentFrame,
                in: currentScreen.visibleFrame,
                padding: padding,
                layouts: knownLayouts
            )
            intendedLayout = preservedLayout
            destination = MonitorTransfer.destination(
                for: currentFrame,
                from: currentScreen.visibleFrame,
                to: destinationScreen.visibleFrame,
                padding: padding,
                layouts: knownLayouts,
                preferredLayout: preservedLayout
            )
        }

        AppDiagnostics.windowOperations.debug(
            "Action target name=\(action.name, privacy: .private(mask: .hash)) pid=\(Int(window.processIdentifier), privacy: .private) source=\(String(describing: currentFrame), privacy: .private) requested=\(String(describing: destination), privacy: .private)"
        )
        let appliedFrame: CGRect
        if transfersDisplay {
            appliedFrame = try await transferFrame(
                destination,
                from: currentFrame,
                of: window.element,
                to: destinationUsableFrame
            )
        } else {
            appliedFrame = try await setFrame(
                destination,
                of: window.element,
                constrainedTo: destinationUsableFrame
            )
        }
        recordAppliedFrame(
            appliedFrame,
            intendedLayout: intendedLayout,
            for: window
        )
        AppDiagnostics.windowOperations.debug(
            "Action applied name=\(action.name, privacy: .private(mask: .hash)) pid=\(Int(window.processIdentifier), privacy: .private) final=\(String(describing: appliedFrame), privacy: .private)"
        )
    }

    static func translatedError(
        _ error: AXError,
        operation: String
    ) -> WindowAccessibilityError {
        switch error {
        case .apiDisabled:
            .permissionRequired
        case .cannotComplete:
            .targetTimedOut(operation: operation)
        default:
            .accessibilityFailure(operation: operation, code: error.rawValue)
        }
    }

    private func focusedWindow() throws -> FocusedWindow {
        let systemWide = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)

        let (application, processIdentifier) = try focusedApplication(
            from: systemWide
        )
        try check(
            AXUIElementSetMessagingTimeout(application, Self.messagingTimeout),
            operation: "setting the application messaging timeout"
        )

        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw WindowAccessibilityError.ownApplicationFocused
        }

        let element = try elementAttribute(
            kAXFocusedWindowAttribute as CFString,
            of: application,
            missingError: .noFocusedWindow
        )
        try check(
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout),
            operation: "setting the window messaging timeout"
        )
        try validateEligibility(of: element)

        return FocusedWindow(
            element: element,
            processIdentifier: processIdentifier
        )
    }

    /// Resolves the focused (or, after app deactivation, main) window for an
    /// explicitly recorded application. This is used by the Dock menu because
    /// interacting with the Dock can make Window Layouts frontmost before its
    /// menu action is delivered.
    private func focusedWindow(processIdentifier: pid_t) throws -> FocusedWindow {
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw WindowAccessibilityError.ownApplicationFocused
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        try check(
            AXUIElementSetMessagingTimeout(application, Self.messagingTimeout),
            operation: "setting the recorded application messaging timeout"
        )

        let element: AXUIElement
        do {
            element = try elementAttribute(
                kAXFocusedWindowAttribute as CFString,
                of: application,
                missingError: .noFocusedWindow
            )
        } catch WindowAccessibilityError.noFocusedWindow {
            element = try elementAttribute(
                kAXMainWindowAttribute as CFString,
                of: application,
                missingError: .noFocusedWindow
            )
        }
        try check(
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout),
            operation: "setting the recorded window messaging timeout"
        )
        try validateEligibility(of: element)

        return FocusedWindow(
            element: element,
            processIdentifier: processIdentifier
        )
    }

    private func visibleEligibleWindows(
        on targetScreen: ScreenSnapshot,
        among screens: [ScreenSnapshot]
    ) throws -> [EligibleWindow] {
        let visible = visibleWindowDescriptors(
            on: targetScreen,
            among: screens
        )
        let processIdentifiers = Set(visible.map(\.processIdentifier))
        var candidates: [EligibleWindow] = []

        for processIdentifier in processIdentifiers.sorted() {
            let application = AXUIElementCreateApplication(processIdentifier)
            do {
                try check(
                    AXUIElementSetMessagingTimeout(
                        application,
                        Self.messagingTimeout
                    ),
                    operation: "setting a visible application messaging timeout"
                )
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(
                    application,
                    kAXWindowsAttribute as CFString,
                    &value
                )
                if error == .noValue || error == .attributeUnsupported {
                    continue
                }
                try check(error, operation: "reading visible application windows")
                guard let windows = value as? [AXUIElement] else { continue }

                for element in windows {
                    do {
                        try check(
                            AXUIElementSetMessagingTimeout(
                                element,
                                Self.messagingTimeout
                            ),
                            operation: "setting a visible window messaging timeout"
                        )
                        try validateEligibility(of: element)
                        let windowFrame = try frame(of: element)
                        guard !ScreenGeometryResolver.isLikelyNativeFullScreen(
                            windowFrame,
                            among: screens
                        ) else { continue }
                        candidates.append(
                            EligibleWindow(
                                window: FocusedWindow(
                                    element: element,
                                    processIdentifier: processIdentifier
                                ),
                                frame: windowFrame
                            )
                        )
                    } catch WindowAccessibilityError.permissionRequired {
                        throw WindowAccessibilityError.permissionRequired
                    } catch {
                        continue
                    }
                }
            } catch WindowAccessibilityError.permissionRequired {
                throw WindowAccessibilityError.permissionRequired
            } catch {
                continue
            }
        }

        let candidateDescriptors = candidates.map {
            WindowFrameDescriptor(
                processIdentifier: $0.window.processIdentifier,
                frame: $0.frame
            )
        }
        return VisibleWindowMatching.candidateIndices(
            for: visible,
            among: candidateDescriptors
        ).map { candidates[$0] }
    }

    private func visibleWindowDescriptors(
        on targetScreen: ScreenSnapshot,
        among screens: [ScreenSnapshot]
    ) -> [WindowFrameDescriptor] {
        let options: CGWindowListOption = [
            .optionOnScreenOnly,
            .excludeDesktopElements,
        ]
        guard let windowInfo = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return windowInfo.compactMap { item in
            guard let processNumber = item[kCGWindowOwnerPID as String] as? NSNumber,
                  let layerNumber = item[kCGWindowLayer as String] as? NSNumber,
                  layerNumber.intValue == 0 else { return nil }
            let processIdentifier = processNumber.int32Value
            guard processIdentifier > 0,
                  processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return nil
            }
            if let alpha = item[kCGWindowAlpha as String] as? NSNumber,
               alpha.doubleValue <= 0 {
                return nil
            }
            guard let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else {
                return nil
            }
            let windowFrame = CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
            guard
                  windowFrame.width > 0,
                  windowFrame.height > 0,
                  ScreenGeometryResolver.screen(
                      containing: windowFrame,
                      among: screens
                  )?.id == targetScreen.id else {
                return nil
            }
            return WindowFrameDescriptor(
                processIdentifier: processIdentifier,
                frame: windowFrame
            )
        }
    }

    private func focusedApplication(
        from systemWide: AXUIElement
    ) throws -> (element: AXUIElement, processIdentifier: pid_t) {
        var value: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )

        var axApplication: AXUIElement?
        var axProcessIdentifier: pid_t?
        if focusedError == .success,
           let value,
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            let application = unsafeBitCast(value, to: AXUIElement.self)
            var processIdentifier: pid_t = 0
            try check(
                AXUIElementGetPid(application, &processIdentifier),
                operation: "reading the focused application identifier"
            )
            axApplication = application
            axProcessIdentifier = processIdentifier
        } else if focusedError != .success,
                  focusedError != .noValue,
                  focusedError != .attributeUnsupported {
            try check(
                focusedError,
                operation: "reading the focused application"
            )
        }

        let workspaceProcessIdentifier = NSWorkspace.shared
            .frontmostApplication?
            .processIdentifier
        guard let processIdentifier = FocusedApplicationSelection.processIdentifier(
            axFocusedProcessIdentifier: axProcessIdentifier,
            workspaceFrontmostProcessIdentifier: workspaceProcessIdentifier
        ) else {
            throw WindowAccessibilityError.noFocusedApplication
        }

        if let axApplication,
           axProcessIdentifier == processIdentifier {
            return (axApplication, processIdentifier)
        }
        return (
            AXUIElementCreateApplication(processIdentifier),
            processIdentifier
        )
    }

    private func validateEligibility(of window: AXUIElement) throws {
        let role = try stringAttribute(kAXRoleAttribute as CFString, of: window)
        guard role == (kAXWindowRole as String) else {
            throw WindowAccessibilityError.unsupportedWindow
        }

        let subrole = try optionalStringAttribute(kAXSubroleAttribute as CFString, of: window)
        if let subrole, subrole != (kAXStandardWindowSubrole as String) {
            throw WindowAccessibilityError.unsupportedWindow
        }
        if try optionalBoolAttribute(kAXMinimizedAttribute as CFString, of: window) == true {
            throw WindowAccessibilityError.minimizedWindow
        }
        guard try isAttributeSettable(kAXPositionAttribute as CFString, of: window),
              try isAttributeSettable(kAXSizeAttribute as CFString, of: window) else {
            throw WindowAccessibilityError.windowCannotBeMovedOrResized
        }
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        let positionValue = try valueAttribute(kAXPositionAttribute as CFString, of: window)
        let sizeValue = try valueAttribute(kAXSizeAttribute as CFString, of: window)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(sizeValue, .cgSize, &size),
              [position.x, position.y, size.width, size.height].allSatisfy(\.isFinite),
              size.width > 0,
              size.height > 0 else {
            throw WindowAccessibilityError.invalidWindowGeometry
        }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(
        _ frame: CGRect,
        of window: AXUIElement,
        constrainedTo usableFrame: CGRect
    ) async throws -> CGRect {
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              frame.width >= 1,
              frame.height >= 1 else {
            throw WindowAccessibilityError.invalidWindowGeometry
        }

        let startingFrame = try self.frame(of: window)
        let crossesDisplay = !usableFrame.contains(
            CGPoint(x: startingFrame.midX, y: startingFrame.midY)
        )
        try await writeFrame(
            frame,
            to: window,
            stagingOrigin: LayoutEngine.stagingOrigin(
                for: frame,
                currentSize: startingFrame.size,
                in: usableFrame
            ),
            resizeBeforeMoving: crossesDisplay
                && LayoutEngine.shouldResizeBeforeDisplayTransfer(
                    currentSize: startingFrame.size,
                    to: usableFrame
                ),
            pauseForDisplayTransition: crossesDisplay
        )

        // Some applications apply an AX size asynchronously, especially when
        // the first change crosses a display edge or leaves a zoomed state.
        // Verify once after a short delay and repeat internally so one menu
        // selection is enough without turning a slow target into a long wait.
        try await Task.sleep(for: Self.initialVerificationDelay)
        var observedFrame = try self.frame(of: window)
        if !frameIsAcceptable(observedFrame, requested: frame, in: usableFrame) {
            try await writeFrame(
                frame,
                to: window,
                stagingOrigin: LayoutEngine.stagingOrigin(
                    for: frame,
                    currentSize: observedFrame.size,
                    in: usableFrame
                ),
                resizeBeforeMoving: crossesDisplay
                    && LayoutEngine.shouldResizeBeforeDisplayTransfer(
                        currentSize: observedFrame.size,
                        to: usableFrame
                    ),
                pauseForDisplayTransition: false
            )
            try await Task.sleep(for: Self.initialVerificationDelay)
            observedFrame = try self.frame(of: window)
        }

        // Crossing displays can make the target application recompute its
        // frame after the first AX response, particularly when backing scales
        // differ. Check once after that transition has settled and correct a
        // late width/height drift so a second user action is unnecessary.
        if crossesDisplay {
            try await Task.sleep(for: Self.displaySettleDelay)
            let settledFrame = try self.frame(of: window)
            if frameIsAcceptable(settledFrame, requested: frame, in: usableFrame) {
                observedFrame = settledFrame
            } else {
                try await writeFrame(
                    frame,
                    to: window,
                    stagingOrigin: LayoutEngine.stagingOrigin(
                        for: frame,
                        currentSize: settledFrame.size,
                        in: usableFrame
                    ),
                    resizeBeforeMoving: LayoutEngine.shouldResizeBeforeDisplayTransfer(
                        currentSize: settledFrame.size,
                        to: usableFrame
                    ),
                    pauseForDisplayTransition: false
                )
                try await Task.sleep(for: Self.initialVerificationDelay)
                observedFrame = try self.frame(of: window)
            }
        }

        var finalFrame = observedFrame
        let containedFrame = LayoutEngine.clamped(finalFrame, to: usableFrame)
        if containedFrame.size == finalFrame.size,
           containedFrame.origin != finalFrame.origin {
            try writePosition(containedFrame.origin, to: window)
            try await Task.sleep(for: .milliseconds(30))
            finalFrame = try self.frame(of: window)
        }
        return finalFrame
    }

    private func transferFrame(
        _ intendedFrame: CGRect,
        from startingFrame: CGRect,
        of window: AXUIElement,
        to usableFrame: CGRect
    ) async throws -> CGRect {
        let stagingFrame = LayoutEngine.displayTransferStagingFrame(
            for: intendedFrame,
            currentSize: startingFrame.size,
            in: usableFrame
        )

        if !LayoutEngine.approximatelyEqual(
            CGRect(origin: .zero, size: startingFrame.size),
            CGRect(origin: .zero, size: stagingFrame.size),
            tolerance: Self.frameVerificationTolerance
        ) {
            try writeSize(stagingFrame.size, to: window)
            try await Task.sleep(for: Self.displayTransitionStepDelay)
        }

        try writePosition(stagingFrame.origin, to: window)

        // Complete the display handoff before applying the layout. This is
        // intentionally two-stage: a normal same-display resize after the wait
        // follows the same path as the user's currently successful second
        // layout command.
        try await Task.sleep(for: Self.displayHandoffDelay)
        let handedOffFrame = try self.frame(of: window)

        var appliedFrame = try await setFrame(
            intendedFrame,
            of: window,
            constrainedTo: usableFrame
        )
        try await Task.sleep(for: Self.displaySettleDelay)
        let settledFrame = try self.frame(of: window)
        if frameIsAcceptable(settledFrame, requested: intendedFrame, in: usableFrame) {
            appliedFrame = settledFrame
        } else {
            appliedFrame = try await setFrame(
                intendedFrame,
                of: window,
                constrainedTo: usableFrame
            )
        }

        AppDiagnostics.windowOperations.debug(
            "Monitor transfer requested=\(String(describing: intendedFrame), privacy: .private) staged=\(String(describing: stagingFrame), privacy: .private) handedOff=\(String(describing: handedOffFrame), privacy: .private) settled=\(String(describing: settledFrame), privacy: .private) final=\(String(describing: appliedFrame), privacy: .private)"
        )
        return appliedFrame
    }

    private func writeFrame(
        _ frame: CGRect,
        to window: AXUIElement,
        stagingOrigin: CGPoint,
        resizeBeforeMoving: Bool,
        pauseForDisplayTransition: Bool
    ) async throws {
        var size = frame.size
        var stagingPosition = stagingOrigin
        var finalPosition = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let stagingPositionValue = AXValueCreate(.cgPoint, &stagingPosition),
              let finalPositionValue = AXValueCreate(.cgPoint, &finalPosition) else {
            throw WindowAccessibilityError.invalidWindowGeometry
        }

        if resizeBeforeMoving {
            // The current frame cannot fit on the destination. Shrink it while
            // it is still on the source display instead of letting macOS push
            // an oversized intermediate frame around the destination edges.
            try check(
                AXUIElementSetAttributeValue(
                    window,
                    kAXSizeAttribute as CFString,
                    sizeValue
                ),
                operation: "resizing the focused window before moving it"
            )
            if pauseForDisplayTransition {
                try await Task.sleep(for: Self.displayTransitionStepDelay)
            }
        } else {
            // Moving first selects the destination display before the target
            // application interprets the new logical size.
            try check(
                AXUIElementSetAttributeValue(
                    window,
                    kAXPositionAttribute as CFString,
                    stagingPositionValue
                ),
                operation: "moving the focused window"
            )
            if pauseForDisplayTransition {
                // AX writes are not atomic. Give the window server one short
                // interval to associate the window with the destination before
                // asking the target app to interpret a new logical size.
                try await Task.sleep(for: Self.displayTransitionStepDelay)
            }
            try check(
                AXUIElementSetAttributeValue(
                    window,
                    kAXSizeAttribute as CFString,
                    sizeValue
                ),
                operation: "resizing the focused window"
            )
        }
        try check(
            AXUIElementSetAttributeValue(
                window,
                kAXPositionAttribute as CFString,
                finalPositionValue
            ),
            operation: "positioning the resized window"
        )
    }

    private func frameIsAcceptable(
        _ observed: CGRect,
        requested: CGRect,
        in usableFrame: CGRect
    ) -> Bool {
        LayoutEngine.approximatelyEqual(
            observed,
            requested,
            tolerance: Self.frameVerificationTolerance
        ) && LayoutEngine.clamped(observed, to: usableFrame) == observed
    }

    private func writePosition(_ position: CGPoint, to window: AXUIElement) throws {
        var position = position
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw WindowAccessibilityError.invalidWindowGeometry
        }
        try check(
            AXUIElementSetAttributeValue(
                window,
                kAXPositionAttribute as CFString,
                positionValue
            ),
            operation: "keeping the focused window inside the display"
        )
    }

    private func writeSize(_ size: CGSize, to window: AXUIElement) throws {
        var size = size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowAccessibilityError.invalidWindowGeometry
        }
        try check(
            AXUIElementSetAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                sizeValue
            ),
            operation: "sizing the focused window for a display handoff"
        )
    }

    private func rememberOriginalFrame(_ frame: CGRect, for window: FocusedWindow) {
        guard restoreIndex(for: window) == nil else { return }
        restoreEntries.append(
            RestoreEntry(
                processIdentifier: window.processIdentifier,
                element: window.element,
                originalFrame: frame,
                lastAppliedFrame: nil,
                lastAppliedLayout: nil
            )
        )
    }

    private func restore(
        window: FocusedWindow,
        screens: [ScreenSnapshot]
    ) async throws {
        guard let index = restoreIndex(for: window) else {
            throw WindowAccessibilityError.noRestoreFrame
        }
        let frame = restoreEntries[index].originalFrame
        guard let usableFrame = ScreenGeometryResolver.screen(
            containing: frame,
            among: screens
        )?.visibleFrame else {
            throw WindowAccessibilityError.noUsableScreen
        }
        _ = try await setFrame(
            frame,
            of: window.element,
            constrainedTo: usableFrame
        )
        restoreEntries.remove(at: index)
    }

    private func restoreIndex(for window: FocusedWindow) -> Int? {
        restoreEntries.firstIndex {
            $0.processIdentifier == window.processIdentifier
                && CFEqual($0.element, window.element)
        }
    }

    private func matchesLastAppliedFrame(_ frame: CGRect, for window: FocusedWindow) -> Bool {
        guard let index = restoreIndex(for: window),
              let lastAppliedFrame = restoreEntries[index].lastAppliedFrame else {
            return false
        }
        return LayoutEngine.approximatelyEqual(frame, lastAppliedFrame)
    }

    private func rememberedLayout(
        matching frame: CGRect,
        for window: FocusedWindow
    ) -> NormalizedRect? {
        guard let index = restoreIndex(for: window) else { return nil }
        return MonitorTransfer.applicableRememberedLayout(
            restoreEntries[index].lastAppliedLayout,
            currentFrame: frame,
            lastAppliedFrame: restoreEntries[index].lastAppliedFrame
        )
    }

    private func recordAppliedFrame(
        _ frame: CGRect,
        intendedLayout: NormalizedRect?,
        for window: FocusedWindow
    ) {
        guard let index = restoreIndex(for: window) else { return }
        restoreEntries[index].lastAppliedFrame = frame
        restoreEntries[index].lastAppliedLayout = intendedLayout
    }

    private func pruneStaleRestoreEntries() {
        restoreEntries.removeAll { entry in
            var processIdentifier: pid_t = 0
            return AXUIElementGetPid(entry.element, &processIdentifier) != .success
                || processIdentifier != entry.processIdentifier
        }
    }

    private func elementAttribute(
        _ attribute: CFString,
        of element: AXUIElement,
        missingError: WindowAccessibilityError
    ) throws -> AXUIElement {
        let value = try copyAttribute(attribute, of: element, missingError: missingError)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw missingError
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func valueAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> AXValue {
        let value = try copyAttribute(
            attribute,
            of: element,
            missingError: .invalidWindowGeometry
        )
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            throw WindowAccessibilityError.invalidWindowGeometry
        }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) throws -> String {
        guard let value = try optionalStringAttribute(attribute, of: element) else {
            throw WindowAccessibilityError.unsupportedWindow
        }
        return value
    }

    private func optionalStringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .attributeUnsupported || error == .noValue {
            return nil
        }
        try check(error, operation: "reading a window attribute")
        return value as? String
    }

    private func optionalBoolAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .attributeUnsupported || error == .noValue {
            return nil
        }
        try check(error, operation: "reading a window state")
        return (value as? NSNumber)?.boolValue
    }

    private func isAttributeSettable(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> Bool {
        var settable = DarwinBoolean(false)
        try check(
            AXUIElementIsAttributeSettable(element, attribute, &settable),
            operation: "checking a window capability"
        )
        return settable.boolValue
    }

    private func copyAttribute(
        _ attribute: CFString,
        of element: AXUIElement,
        missingError: WindowAccessibilityError
    ) throws -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .noValue || error == .attributeUnsupported {
            throw missingError
        }
        try check(error, operation: "reading an Accessibility attribute")
        guard let value else { throw missingError }
        return value
    }

    private func check(_ error: AXError, operation: String) throws {
        guard error != .success else { return }
        throw Self.translatedError(error, operation: operation)
    }
}
