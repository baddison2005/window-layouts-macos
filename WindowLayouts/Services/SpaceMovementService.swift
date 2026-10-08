// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

nonisolated enum SpaceMovementDirection: String, CaseIterable, Identifiable, Sendable {
    case previous
    case next

    var id: String { rawValue }

    var name: String {
        switch self {
        case .previous: String(localized: "Move Window to Previous Space")
        case .next: String(localized: "Move Window to Next Space")
        }
    }

    fileprivate var arrowKeyCode: CGKeyCode {
        switch self {
        case .previous: CGKeyCode(kVK_LeftArrow)
        case .next: CGKeyCode(kVK_RightArrow)
        }
    }
}

nonisolated enum SpaceMovementError: Error, Equatable, LocalizedError, Sendable {
    case featureDisabled
    case shortcutConfirmationRequired
    case accessibilityPermissionRequired
    case postEventPermissionRequired
    case inputStillActive
    case noFocusedApplication
    case ownApplicationFocused
    case noFocusedWindow
    case unsupportedWindow
    case minimizedWindow
    case fullScreenWindow
    case invalidWindowGeometry
    case noSafeTitleBarPoint
    case targetTimedOut
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            String(localized: "Enable Experimental Space Movement in General settings first.")
        case .shortcutConfirmationRequired:
            String(localized: "Confirm the Mission Control Space shortcuts in General settings first.")
        case .accessibilityPermissionRequired:
            String(localized: "Accessibility access is required.")
        case .postEventPermissionRequired:
            String(localized: "Permission to post input events is required.")
        case .inputStillActive:
            String(localized: "Release held modifier keys and mouse buttons, then try again.")
        case .noFocusedApplication:
            String(localized: "No application is currently focused.")
        case .ownApplicationFocused:
            String(localized: "Choose a window in another application first.")
        case .noFocusedWindow:
            String(localized: "The focused application has no eligible window.")
        case .unsupportedWindow:
            String(localized: "The focused item is not a standard movable application window.")
        case .minimizedWindow:
            String(localized: "The focused window is minimized.")
        case .fullScreenWindow:
            String(localized: "Native full-screen windows are not supported.")
        case .invalidWindowGeometry:
            String(localized: "The focused window reported invalid geometry.")
        case .noSafeTitleBarPoint:
            String(
                localized:
                    "No unobstructed, noninteractive title-bar point was available for the experimental gesture."
            )
        case .targetTimedOut:
            String(localized: "The focused application did not respond in time.")
        case .eventCreationFailed:
            String(localized: "macOS could not create the experimental input gesture.")
        }
    }
}

nonisolated struct SpaceMovementTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowFrame: CGRect
    let dragPoint: CGPoint
}

nonisolated struct SpaceMovementInputState: Equatable, Sendable {
    let primaryModifierIsDown: Bool
    let mouseButtonIsDown: Bool

    var isNeutral: Bool {
        !primaryModifierIsDown && !mouseButtonIsDown
    }
}

nonisolated enum SpaceMovementSyntheticEvent: Equatable, Sendable {
    case mouseMoved(point: CGPoint)
    case leftMouseDown(point: CGPoint, eventNumber: Int64)
    case leftMouseUp(point: CGPoint, eventNumber: Int64)
    case keyDown(code: CGKeyCode, control: Bool)
    case keyUp(code: CGKeyCode, control: Bool)
}

@MainActor
struct SpaceMovementSystemClient {
    var hasAccessibilityAccess: () -> Bool
    var hasPostEventAccess: () -> Bool
    var requestPostEventAccess: () -> Bool
    var inputState: () -> SpaceMovementInputState
    var pointerLocation: () -> CGPoint?
    var eventNumber: () -> Int64
    var resolveTarget: (pid_t?) throws -> SpaceMovementTarget
    var post: (SpaceMovementSyntheticEvent) throws -> Void
    var pause: (Duration) async throws -> Void

    static let live: SpaceMovementSystemClient = {
        // Reuse one event source so the mouse hold and keyboard shortcut are
        // represented as one synthetic input sequence.
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        return SpaceMovementSystemClient(
            hasAccessibilityAccess: {
                AXIsProcessTrusted()
            },
            hasPostEventAccess: {
                CGPreflightPostEventAccess()
            },
            requestPostEventAccess: {
                CGRequestPostEventAccess()
            },
            inputState: {
                let flags = CGEventSource.flagsState(.combinedSessionState)
                let primaryModifiers: CGEventFlags = [
                    .maskCommand,
                    .maskAlternate,
                    .maskControl,
                    .maskShift,
                ]
                return SpaceMovementInputState(
                    primaryModifierIsDown: !flags.intersection(primaryModifiers).isEmpty,
                    mouseButtonIsDown: CGEventSource.buttonState(
                        .combinedSessionState,
                        button: .left
                    )
                        || CGEventSource.buttonState(
                            .combinedSessionState,
                            button: .right
                        )
                        || CGEventSource.buttonState(
                            .combinedSessionState,
                            button: .center
                        )
                )
            },
            pointerLocation: {
                CGEvent(source: nil)?.location
            },
            eventNumber: {
                Int64(DispatchTime.now().uptimeNanoseconds & 0x7fff_ffff)
            },
            resolveTarget: { processIdentifier in
                try SpaceMovementAXTargetResolver.resolve(
                    processIdentifier: processIdentifier
                )
            },
            post: { descriptor in
                guard let eventSource else {
                    throw SpaceMovementError.eventCreationFailed
                }
                let event: CGEvent?
                switch descriptor {
                case .mouseMoved(let point):
                    event = CGEvent(
                        mouseEventSource: eventSource,
                        mouseType: .mouseMoved,
                        mouseCursorPosition: point,
                        mouseButton: .left
                    )
                case .leftMouseDown(let point, let eventNumber):
                    event = CGEvent(
                        mouseEventSource: eventSource,
                        mouseType: .leftMouseDown,
                        mouseCursorPosition: point,
                        mouseButton: .left
                    )
                    event?.setIntegerValueField(
                        .mouseEventNumber,
                        value: eventNumber
                    )
                    event?.setIntegerValueField(.mouseEventClickState, value: 1)
                    event?.setDoubleValueField(.mouseEventPressure, value: 1)
                case .leftMouseUp(let point, let eventNumber):
                    event = CGEvent(
                        mouseEventSource: eventSource,
                        mouseType: .leftMouseUp,
                        mouseCursorPosition: point,
                        mouseButton: .left
                    )
                    event?.setIntegerValueField(
                        .mouseEventNumber,
                        value: eventNumber
                    )
                    event?.setIntegerValueField(.mouseEventClickState, value: 1)
                    event?.setDoubleValueField(.mouseEventPressure, value: 0)
                case .keyDown(let code, let control):
                    event = CGEvent(
                        keyboardEventSource: eventSource,
                        virtualKey: code,
                        keyDown: true
                    )
                    event?.flags = control
                        ? [.maskControl, .maskNumericPad, .maskSecondaryFn]
                        : [.maskNumericPad, .maskSecondaryFn]
                case .keyUp(let code, let control):
                    event = CGEvent(
                        keyboardEventSource: eventSource,
                        virtualKey: code,
                        keyDown: false
                    )
                    event?.flags = control
                        ? [.maskControl, .maskNumericPad, .maskSecondaryFn]
                        : [.maskNumericPad, .maskSecondaryFn]
                }

                guard let event else {
                    throw SpaceMovementError.eventCreationFailed
                }
                event.post(tap: .cghidEventTap)
            },
            pause: { duration in
                try await Task.sleep(for: duration)
            }
        )
    }()
}

@MainActor
final class SpaceMovementService {
    private static let neutralInputAttempts = 30
    private static let neutralInputPollDelay = Duration.milliseconds(50)
    private static let pointerSettleDelay = Duration.milliseconds(40)
    private static let mouseHoldDelay = Duration.milliseconds(120)
    private static let arrowHoldDelay = Duration.milliseconds(90)
    private static let spaceTransitionDelay = Duration.milliseconds(420)

    private let client: SpaceMovementSystemClient

    init() {
        self.client = .live
    }

    init(client: SpaceMovementSystemClient) {
        self.client = client
    }

    var hasPostEventAccess: Bool {
        client.hasPostEventAccess()
    }

    @discardableResult
    func requestPostEventAccess() -> Bool {
        client.requestPostEventAccess()
    }

    func moveWindow(
        _ direction: SpaceMovementDirection,
        processIdentifier: pid_t? = nil
    ) async throws {
        guard client.hasAccessibilityAccess() else {
            throw SpaceMovementError.accessibilityPermissionRequired
        }
        guard client.hasPostEventAccess() else {
            throw SpaceMovementError.postEventPermissionRequired
        }

        try await waitForNeutralPhysicalInput()
        let target = try client.resolveTarget(processIdentifier)
        guard let originalPointer = client.pointerLocation() else {
            throw SpaceMovementError.eventCreationFailed
        }

        let eventNumber = client.eventNumber()
        let arrowKey = direction.arrowKeyCode
        var pointerWasMoved = false
        var mouseIsDown = false
        var arrowIsDown = false

        do {
            try client.post(.mouseMoved(point: target.dragPoint))
            pointerWasMoved = true
            try await client.pause(Self.pointerSettleDelay)

            try client.post(
                .leftMouseDown(
                    point: target.dragPoint,
                    eventNumber: eventNumber
                ))
            mouseIsDown = true
            try await client.pause(Self.mouseHoldDelay)

            try client.post(.keyDown(code: arrowKey, control: true))
            arrowIsDown = true
            try await client.pause(Self.arrowHoldDelay)

            try client.post(.keyUp(code: arrowKey, control: true))
            arrowIsDown = false
            try await client.pause(Self.spaceTransitionDelay)

            try client.post(
                .leftMouseUp(
                    point: target.dragPoint,
                    eventNumber: eventNumber
                ))
            mouseIsDown = false
            try await client.pause(Self.pointerSettleDelay)

            try client.post(.mouseMoved(point: originalPointer))
            pointerWasMoved = false

            AppDiagnostics.windowOperations.debug(
                "Experimental Space gesture posted direction=\(direction.rawValue, privacy: .public) pid=\(target.processIdentifier, privacy: .public)"
            )
        } catch {
            if arrowIsDown {
                try? client.post(.keyUp(code: arrowKey, control: true))
            }
            if mouseIsDown {
                try? client.post(
                    .leftMouseUp(
                        point: target.dragPoint,
                        eventNumber: eventNumber
                    ))
            }
            if pointerWasMoved {
                try? client.post(.mouseMoved(point: originalPointer))
            }
            throw error
        }
    }

    private func waitForNeutralPhysicalInput() async throws {
        for attempt in 0..<Self.neutralInputAttempts {
            if client.inputState().isNeutral {
                return
            }
            if attempt + 1 < Self.neutralInputAttempts {
                try await client.pause(Self.neutralInputPollDelay)
            }
        }
        throw SpaceMovementError.inputStillActive
    }

}

// Acrobat draws Home/tabs itself and may expose them only as AXWindow.
// Prefer the outer title-bar margins just below the traffic-light buttons,
// matching manually verified hold points, rather than the tab strip's centre.
// These are candidates, not proof of draggability: every point still requires
// the resolver's control exclusion and AX ownership/interaction checks.
nonisolated enum SpaceMovementTitleBarPolicy {
    static func acrobatCandidates(
        bundleIdentifier: String?, frame: CGRect, closeButtonFrame: CGRect? = nil
    ) -> [CGPoint]? {
        guard let identifier = bundleIdentifier?.lowercased(),
              ["com.adobe.acrobat.pro", "com.adobe.reader"].contains(identifier) else {
            return nil
        }
        guard frame.width.isFinite, frame.height.isFinite,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width >= 180, frame.height >= 32 else { return [] }
        let y = closeButtonFrame.map { $0.maxY + 3 } ?? (frame.minY + 28)
        guard y.isFinite, y >= frame.minY + 16, y <= frame.minY + 40 else { return [] }
        return [5.0, 7.0, 9.0, 11.0].flatMap { inset in
            [CGPoint(x: frame.minX + inset, y: y),
             CGPoint(x: frame.maxX - inset, y: y)]
        }.filter { point in
            frame.contains(point)
                && !(closeButtonFrame?.insetBy(dx: -3, dy: -5).contains(point) ?? false)
        }
    }

    static func isVerifiedLeftMargin(_ point: CGPoint, frame: CGRect, close: CGRect?) -> Bool {
        guard let close, frame.contains(close),
              close.width > 0, close.height > 0 else { return false }
        return frame.contains(point)
            && point.x >= frame.minX + 4 && point.x <= frame.minX + 7
            && point.x < close.minX - 3
            && abs(point.y - (close.maxY + 3)) < 0.5
            && point.y <= frame.minY + 40
    }
}

private enum SpaceMovementAXTargetResolver {
    private static let messagingTimeout: Float = 0.25
    private static let minimumWindowWidth: CGFloat = 180
    private static let titleBarFallbackOffset: CGFloat = 14
    private static let interactiveRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXPopUpButtonRole as String,
        kAXComboBoxRole as String,
        kAXSliderRole as String,
        "AXLink",
        kAXMenuButtonRole as String,
        kAXDisclosureTriangleRole as String,
        kAXScrollBarRole as String,
        kAXIncrementorRole as String,
        "AXTab",
        "AXMenuItem",
    ]

    static func resolve(processIdentifier explicitProcessIdentifier: pid_t?) throws
        -> SpaceMovementTarget
    {
        var stage = "permission"
        do {
            return try resolve(
                processIdentifier: explicitProcessIdentifier,
                stage: &stage
            )
        } catch {
            AppDiagnostics.windowOperations.error(
                "Experimental Space target resolution failed stage=\(stage, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    private static func resolve(
        processIdentifier explicitProcessIdentifier: pid_t?,
        stage: inout String
    ) throws -> SpaceMovementTarget {
        guard AXIsProcessTrusted() else {
            throw SpaceMovementError.accessibilityPermissionRequired
        }

        stage = "focusedApplication"
        let systemWide = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        let processIdentifier = try resolvedProcessIdentifier(
            explicit: explicitProcessIdentifier,
            systemWide: systemWide
        )
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw SpaceMovementError.ownApplicationFocused
        }

        stage = "focusedWindow"
        let application = AXUIElementCreateApplication(processIdentifier)
        try check(
            AXUIElementSetMessagingTimeout(application, messagingTimeout)
        )
        let window = try focusedOrMainWindow(of: application)
        try check(AXUIElementSetMessagingTimeout(window, messagingTimeout))

        stage = "windowEligibility"
        try validate(window)

        stage = "windowGeometry"
        let windowFrame = try frame(of: window)
        guard windowFrame.width >= minimumWindowWidth else {
            throw SpaceMovementError.unsupportedWindow
        }

        stage = "titleBarControls"
        let closeButtonFrame = titleBarControlFrame(
            kAXCloseButtonAttribute,
            of: window
        )
        let controlFrames = titleBarControlFrames(of: window)
        let controlCenterY =
            controlFrames.isEmpty
            ? windowFrame.minY + titleBarFallbackOffset
            : controlFrames.map(\.midY).reduce(0, +) / CGFloat(controlFrames.count)
        let controlAdjacentXs = controlFrames.map(\.maxX).max().map { rightEdge in
            [5, 8, 11, 14].map { rightEdge + CGFloat($0) }
        } ?? []
        let inset = max(44, min(96, windowFrame.width * 0.12))
        let generalCandidateXs =
            [0.5, 0.62, 0.38, 0.74, 0.26, 0.86, 0.14, 0.68, 0.32, 0.80, 0.20]
            .map { windowFrame.minX + windowFrame.width * $0 }
            + [windowFrame.minX + inset, windowFrame.maxX - inset]
        let bundleIdentifier = NSRunningApplication(
            processIdentifier: processIdentifier
        )?.bundleIdentifier
        let usesDenseBrowserTabStrip = bundleIdentifier.map(
            isDenseBrowserBundleIdentifier
        ) ?? false
        let candidateYs = uniqueCoordinates([
            controlCenterY,
            windowFrame.minY + 10,
            windowFrame.minY + 16,
            windowFrame.minY + 22,
            windowFrame.minY + 28,
        ])
        let controlAdjacentPoints = candidateYs.flatMap { y in
            controlAdjacentXs.map { CGPoint(x: $0, y: y) }
        }
        let closeButtonCornerPoint = closeButtonFrame.map { frame in
            CGPoint(x: frame.minX - 3, y: frame.maxY + 3)
        }
        let closeButtonCornerPoints: [CGPoint] = closeButtonCornerPoint.map { [$0] } ?? []
        let closeButtonFallbackPoints: [CGPoint]
        if let frame = closeButtonFrame {
            let xs = [5, 8, 11].map { frame.minX - CGFloat($0) }
            let ys = uniqueCoordinates(
                [controlCenterY]
                    + [6, 10, 14, 18].map { frame.maxY + CGFloat($0) }
            )
            closeButtonFallbackPoints = ys.flatMap { y in
                xs.map { CGPoint(x: $0, y: y) }
            }
        } else {
            closeButtonFallbackPoints = []
        }
        let generalCandidatePoints = candidateYs.flatMap { y in
            generalCandidateXs.map { CGPoint(x: $0, y: y) }
        }
        let acrobatCandidates = SpaceMovementTitleBarPolicy.acrobatCandidates(
            bundleIdentifier: bundleIdentifier, frame: windowFrame,
            closeButtonFrame: closeButtonFrame
        )
        let candidatePoints = acrobatCandidates ?? (controlAdjacentPoints
            + closeButtonCornerPoints
            + closeButtonFallbackPoints
            + (usesDenseBrowserTabStrip ? [] : generalCandidatePoints))
        let strategy = acrobatCandidates == nil ? "control-adjacent" : "acrobat-outer-margins"

        stage = "safeTitleBarPoint"
        if acrobatCandidates != nil {
            AppDiagnostics.windowOperations.debug(
                "Experimental Space Acrobat geometry window=\(String(describing: windowFrame), privacy: .public) close=\(String(describing: closeButtonFrame), privacy: .public) controls=\(String(describing: controlFrames), privacy: .public)"
            )
        }
        for (candidateIndex, point) in candidatePoints.enumerated() {
            let isExactCloseButtonCorner = closeButtonCornerPoint == point
            let isClearOfControls = isExactCloseButtonCorner
                ? !controlFrames.contains(where: { $0.contains(point) })
                : isClearOfTitleBarControls(point, controlFrames: controlFrames)
            // Acrobat's verified margin is 7 points inside the edge; the
            // general 8-point inset would discard it before AX hit testing.
            let rejection: String?
            if !windowFrame.insetBy(dx: acrobatCandidates == nil ? 8 : 4, dy: 0).contains(point) {
                rejection = "outside-window-inset"
            } else if !isClearOfControls {
                rejection = "traffic-light-clearance"
            } else {
                rejection = try pointRejectionReason(
                    point, in: window, systemWide: systemWide,
                    verifiedAcrobatMargin: acrobatCandidates != nil
                        && SpaceMovementTitleBarPolicy.isVerifiedLeftMargin(
                            point, frame: windowFrame, close: closeButtonFrame
                        ),
                    windowFrame: windowFrame
                )
            }
            if let rejection {
                if acrobatCandidates != nil {
                    AppDiagnostics.windowOperations.debug(
                        "Experimental Space Acrobat candidate=\(candidateIndex, privacy: .public) offset=(\(point.x - windowFrame.minX, privacy: .public), \(point.y - windowFrame.minY, privacy: .public)) rejected=\(rejection, privacy: .public)"
                    )
                }
                continue
            }
            AppDiagnostics.windowOperations.debug(
                "Experimental Space target resolved pid=\(processIdentifier, privacy: .public) strategy=\(strategy, privacy: .public) candidate=\(candidateIndex, privacy: .public) offset=(\(point.x - windowFrame.minX, privacy: .public), \(point.y - windowFrame.minY, privacy: .public)) point=(\(point.x, privacy: .public), \(point.y, privacy: .public))"
            )
            return SpaceMovementTarget(
                processIdentifier: processIdentifier,
                windowFrame: windowFrame,
                dragPoint: point
            )
        }
        AppDiagnostics.windowOperations.debug(
            "Experimental Space target rejected strategy=\(strategy, privacy: .public) candidates=\(candidatePoints.count, privacy: .public)"
        )
        throw SpaceMovementError.noSafeTitleBarPoint
    }

    nonisolated private static func isDenseBrowserBundleIdentifier(
        _ identifier: String
    ) -> Bool {
        let normalized = identifier.lowercased()
        return normalized.hasPrefix("com.google.chrome")
            || normalized.hasPrefix("org.mozilla.firefox")
            || normalized.hasPrefix("com.operasoftware.opera")
    }

    nonisolated private static func isClearOfTitleBarControls(
        _ point: CGPoint,
        controlFrames: [CGRect]
    ) -> Bool {
        !controlFrames.contains { frame in
            frame.insetBy(dx: -3, dy: -5).contains(point)
        }
    }

    nonisolated private static func uniqueCoordinates(_ values: [CGFloat]) -> [CGFloat] {
        var seen: Set<Int> = []
        return values.filter { seen.insert(Int($0.rounded())).inserted }
    }

    private static func resolvedProcessIdentifier(
        explicit: pid_t?,
        systemWide: AXUIElement
    ) throws -> pid_t {
        if let explicit, explicit > 0 {
            return explicit
        }

        var value: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        if focusedError == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        {
            let application = unsafeBitCast(value, to: AXUIElement.self)
            var processIdentifier: pid_t = 0
            try check(AXUIElementGetPid(application, &processIdentifier))
            if processIdentifier > 0 {
                return processIdentifier
            }
        } else if focusedError != .noValue,
            focusedError != .attributeUnsupported
        {
            try check(focusedError)
        }

        guard
            let processIdentifier = NSWorkspace.shared
                .frontmostApplication?
                .processIdentifier,
            processIdentifier > 0
        else {
            throw SpaceMovementError.noFocusedApplication
        }
        return processIdentifier
    }

    private static func focusedOrMainWindow(
        of application: AXUIElement
    ) throws -> AXUIElement {
        if let focused = try optionalElementAttribute(
            kAXFocusedWindowAttribute as CFString,
            of: application
        ) {
            return focused
        }
        if let main = try optionalElementAttribute(
            kAXMainWindowAttribute as CFString,
            of: application
        ) {
            return main
        }
        throw SpaceMovementError.noFocusedWindow
    }

    private static func validate(_ window: AXUIElement) throws {
        guard
            try stringAttribute(kAXRoleAttribute as CFString, of: window)
                == (kAXWindowRole as String)
        else {
            throw SpaceMovementError.unsupportedWindow
        }
        if let subrole = try optionalStringAttribute(
            kAXSubroleAttribute as CFString,
            of: window
        ), subrole != (kAXStandardWindowSubrole as String) {
            throw SpaceMovementError.unsupportedWindow
        }
        if try optionalBoolAttribute(
            kAXMinimizedAttribute as CFString,
            of: window
        ) == true {
            throw SpaceMovementError.minimizedWindow
        }

        var settable = DarwinBoolean(false)
        try check(
            AXUIElementIsAttributeSettable(
                window,
                kAXPositionAttribute as CFString,
                &settable
            ))
        guard settable.boolValue else {
            throw SpaceMovementError.unsupportedWindow
        }
    }

    private static func titleBarControlFrames(
        of window: AXUIElement
    ) -> [CGRect] {
        [
            kAXCloseButtonAttribute,
            kAXMinimizeButtonAttribute,
            kAXZoomButtonAttribute,
        ].compactMap { titleBarControlFrame($0, of: window) }
    }

    private static func titleBarControlFrame(
        _ attribute: String,
        of window: AXUIElement
    ) -> CGRect? {
        guard
            let button = try? optionalElementAttribute(
                attribute as CFString,
                of: window
            )
        else { return nil }
        return try? frame(of: button)
    }

    private static func pointRejectionReason(
        _ point: CGPoint,
        in window: AXUIElement,
        systemWide: AXUIElement,
        verifiedAcrobatMargin: Bool,
        windowFrame: CGRect
    ) throws -> String? {
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hitElement
        )
        if error == .apiDisabled {
            throw SpaceMovementError.accessibilityPermissionRequired
        }
        if error == .notImplemented, verifiedAcrobatMargin {
            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success else {
                return "acrobat-fallback-missing-pid"
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                return "acrobat-fallback-app-not-frontmost"
            }
            let screens = NSScreen.screens
            let primaryTop = screens.first?.frame.maxY ?? 0
            let displayBounds = screens.map {
                CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY,
                       width: $0.frame.width, height: $0.frame.height)
            }
            // No screen capture or private window-server API: query public
            // window geometry in front-to-back order. Refuse an obscured point
            // or an ambiguous window; never fall back on app ownership alone.
            guard let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]] else { return "acrobat-fallback-window-list-unavailable" }
            for info in windows {
                guard let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                      alpha.doubleValue > 0 else { continue }
                guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds) else {
                    return "acrobat-fallback-unknown-bounds"
                }
                guard rect.contains(point) else { continue }
                // Dock can publish a full-display bookkeeping window at its
                // own level even while ordinary apps receive pointer input.
                // Exclude only that shape/owner/level combination, never the
                // actual Dock, menus, or another app's floating panels.
                if let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                   let layer = info[kCGWindowLayer as String] as? NSNumber,
                   layer.int32Value == CGWindowLevelForKey(.dockWindow),
                   NSRunningApplication(processIdentifier: owner.int32Value)?.bundleIdentifier == "com.apple.dock",
                   displayBounds.contains(where: {
                       abs($0.minX - rect.minX) < 2 && abs($0.minY - rect.minY) < 2
                           && abs($0.width - rect.width) < 2 && abs($0.height - rect.height) < 2
                   }) {
                    continue
                }
                guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                      owner.int32Value == pid,
                      abs(rect.minX - windowFrame.minX) < 2,
                      abs(rect.minY - windowFrame.minY) < 2,
                      abs(rect.width - windowFrame.width) < 2,
                      abs(rect.height - windowFrame.height) < 2 else {
                    let owner = info[kCGWindowOwnerPID as String] as? NSNumber
                    let layer = info[kCGWindowLayer as String] as? NSNumber
                    return "acrobat-fallback-point-obscured-or-window-mismatch:pid=\(owner?.int32Value ?? -1),layer=\(layer?.int32Value ?? -1),bounds=\(rect)"
                }
                AppDiagnostics.windowOperations.debug(
                    "Experimental Space Acrobat verified left margin using public window geometry (AX hit test not implemented)"
                )
                return nil
            }
            return "acrobat-fallback-window-not-visible"
        }
        guard error == .success else {
            return "hit-test-error:\(error.rawValue)"
        }
        guard let hitElement else { return "hit-test-empty" }

        var hitPID: pid_t = 0
        var windowPID: pid_t = 0
        let hitPIDError = AXUIElementGetPid(hitElement, &hitPID)
        let windowPIDError = AXUIElementGetPid(window, &windowPID)
        if hitPIDError == .success, windowPIDError == .success, hitPID != windowPID {
            return "different-application:hitPID=\(hitPID),targetPID=\(windowPID)"
        }

        var current = hitElement
        for depth in 0..<12 {
            _ = AXUIElementSetMessagingTimeout(current, messagingTimeout)
            if CFEqual(current, window) {
                return nil
            }

            guard let role = try bestEffortStringAttribute(
                    kAXRoleAttribute as CFString,
                    of: current
                ) else { return "missing-role:depth=\(depth)" }
            if interactiveRoles.contains(role) {
                return "interactive-role:\(role),depth=\(depth)"
            }
            guard let actions = try bestEffortActionNames(of: current) else {
                return "unavailable-actions:role=\(role),depth=\(depth)"
            }
            if actions.contains(kAXPressAction as String) {
                return "press-action:role=\(role),depth=\(depth)"
            }

            guard
                let parent = try bestEffortElementAttribute(
                    kAXParentAttribute as CFString,
                    of: current
                ), !CFEqual(parent, current)
            else {
                return "missing-or-self-parent:role=\(role),depth=\(depth)"
            }
            current = parent
        }
        return "ancestor-depth-limit"
    }

    private static func bestEffortElementAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .apiDisabled {
            throw SpaceMovementError.accessibilityPermissionRequired
        }
        guard error == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func bestEffortStringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .apiDisabled {
            throw SpaceMovementError.accessibilityPermissionRequired
        }
        guard error == .success else { return nil }
        return value as? String
    }

    private static func bestEffortActionNames(
        of element: AXUIElement
    ) throws -> Set<String>? {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        if error == .apiDisabled {
            throw SpaceMovementError.accessibilityPermissionRequired
        }
        guard error == .success,
            let names = names as? [String]
        else {
            return nil
        }
        return Set(names)
    }

    private static func frame(of element: AXUIElement) throws -> CGRect {
        let positionValue = try valueAttribute(
            kAXPositionAttribute as CFString,
            of: element
        )
        let sizeValue = try valueAttribute(
            kAXSizeAttribute as CFString,
            of: element
        )
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint,
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetType(sizeValue) == .cgSize,
            AXValueGetValue(sizeValue, .cgSize, &size),
            [position.x, position.y, size.width, size.height]
                .allSatisfy(\.isFinite),
            size.width > 0,
            size.height > 0
        else {
            throw SpaceMovementError.invalidWindowGeometry
        }
        return CGRect(origin: position, size: size)
    }

    private static func optionalElementAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .noValue || error == .attributeUnsupported {
            return nil
        }
        try check(error)
        guard let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> String {
        guard let result = try optionalStringAttribute(attribute, of: element) else {
            throw SpaceMovementError.unsupportedWindow
        }
        return result
    }

    private static func optionalStringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .noValue || error == .attributeUnsupported {
            return nil
        }
        try check(error)
        return value as? String
    }

    private static func optionalBoolAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .noValue || error == .attributeUnsupported {
            return nil
        }
        try check(error)
        return value as? Bool
    }

    private static func valueAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) throws -> AXValue {
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element, attribute, &value))
        guard let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            throw SpaceMovementError.invalidWindowGeometry
        }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private static func check(_ error: AXError) throws {
        guard error != .success else { return }
        switch error {
        case .apiDisabled:
            throw SpaceMovementError.accessibilityPermissionRequired
        case .cannotComplete:
            throw SpaceMovementError.targetTimedOut
        default:
            throw SpaceMovementError.unsupportedWindow
        }
    }
}
