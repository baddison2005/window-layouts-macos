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
        let candidatePoints = controlAdjacentPoints
            + closeButtonCornerPoints
            + closeButtonFallbackPoints
            + (usesDenseBrowserTabStrip ? [] : generalCandidatePoints)

        stage = "safeTitleBarPoint"
        for point in candidatePoints {
            let isExactCloseButtonCorner = closeButtonCornerPoint == point
            let isClearOfControls = isExactCloseButtonCorner
                ? !controlFrames.contains(where: { $0.contains(point) })
                : isClearOfTitleBarControls(point, controlFrames: controlFrames)
            guard windowFrame.insetBy(dx: 8, dy: 0).contains(point),
                isClearOfControls,
                try pointIsSafe(
                    point,
                    in: window,
                    systemWide: systemWide
                )
            else { continue }
            AppDiagnostics.windowOperations.debug(
                "Experimental Space target resolved pid=\(processIdentifier, privacy: .public) point=(\(point.x, privacy: .public), \(point.y, privacy: .public))"
            )
            return SpaceMovementTarget(
                processIdentifier: processIdentifier,
                windowFrame: windowFrame,
                dragPoint: point
            )
        }
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

    private static func pointIsSafe(
        _ point: CGPoint,
        in window: AXUIElement,
        systemWide: AXUIElement
    ) throws -> Bool {
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hitElement
        )
        if error == .noValue || error == .attributeUnsupported {
            return false
        }
        if error == .apiDisabled {
            throw SpaceMovementError.accessibilityPermissionRequired
        }
        guard error == .success else {
            return false
        }
        guard let hitElement else { return false }

        var current = hitElement
        for _ in 0..<12 {
            if CFEqual(current, window) {
                return true
            }

            guard
                let role = try bestEffortStringAttribute(
                    kAXRoleAttribute as CFString,
                    of: current
                ), !interactiveRoles.contains(role),
                let actions = try bestEffortActionNames(of: current),
                !actions.contains(kAXPressAction as String)
            else {
                return false
            }

            guard
                let parent = try bestEffortElementAttribute(
                    kAXParentAttribute as CFString,
                    of: current
                ), !CFEqual(parent, current)
            else {
                return false
            }
            current = parent
        }
        return false
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
