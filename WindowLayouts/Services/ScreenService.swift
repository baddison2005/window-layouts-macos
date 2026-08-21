// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreGraphics

nonisolated struct ScreenSnapshot: Equatable, Sendable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
}

@MainActor
enum ScreenService {
    static func snapshots() -> [ScreenSnapshot] {
        let screens = NSScreen.screens
        guard let referenceTop = ScreenCoordinateConverter.referenceTop(
            forAppKitFrames: screens.map(\.frame)
        ) else { return [] }
        let converter = ScreenCoordinateConverter(referenceTop: referenceTop)

        return screens.enumerated().map { index, screen in
            let numberKey = NSDeviceDescriptionKey("NSScreenNumber")
            let screenNumber = screen.deviceDescription[numberKey] as? NSNumber
            return ScreenSnapshot(
                id: screenNumber?.stringValue ?? "screen-\(index)",
                frame: converter.accessibilityRect(fromAppKit: screen.frame),
                visibleFrame: converter.accessibilityRect(fromAppKit: screen.visibleFrame)
            )
        }
    }

    static func appKitRect(fromAccessibility rect: CGRect) -> CGRect? {
        guard let referenceTop = ScreenCoordinateConverter.referenceTop(
            forAppKitFrames: NSScreen.screens.map(\.frame)
        ) else { return nil }
        return ScreenCoordinateConverter(referenceTop: referenceTop)
            .appKitRect(fromAccessibility: rect)
    }

    static func accessibilityPoint(fromAppKit point: CGPoint) -> CGPoint? {
        guard let referenceTop = ScreenCoordinateConverter.referenceTop(
            forAppKitFrames: NSScreen.screens.map(\.frame)
        ) else { return nil }
        return ScreenCoordinateConverter(referenceTop: referenceTop)
            .accessibilityPoint(fromAppKit: point)
    }
}

nonisolated enum ScreenGeometryResolver {
    static func isLikelyNativeFullScreen(
        _ windowFrame: CGRect,
        among screens: [ScreenSnapshot],
        tolerance: CGFloat = 2
    ) -> Bool {
        screens.contains {
            LayoutEngine.approximatelyEqual(
                windowFrame,
                $0.frame,
                tolerance: tolerance
            )
        }
    }

    static func visibleFrame(
        containing windowFrame: CGRect,
        among screens: [ScreenSnapshot]
    ) -> CGRect? {
        screen(containing: windowFrame, among: screens)?.visibleFrame
    }

    static func screen(
        containing windowFrame: CGRect,
        among screens: [ScreenSnapshot]
    ) -> ScreenSnapshot? {
        guard !screens.isEmpty else { return nil }

        let intersecting = screens.map { screen in
            (screen, intersectionArea(windowFrame, screen.frame))
        }
        if let best = intersecting.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }

        return screens.min {
            squaredDistance(from: windowFrame.center, to: $0.frame.center)
                < squaredDistance(from: windowFrame.center, to: $1.frame.center)
        }
    }

    /// A drag target belongs to the display under the pointer, even while most
    /// of the dragged window still intersects an adjacent display. Prefer that
    /// explicit display and fall back to frame-based resolution for ordinary
    /// menu and shortcut actions.
    static func destinationScreen(
        for windowFrame: CGRect,
        preferredScreenID: String?,
        among screens: [ScreenSnapshot]
    ) -> ScreenSnapshot? {
        if let preferredScreenID,
           let preferred = screens.first(where: { $0.id == preferredScreenID }) {
            return preferred
        }
        return screen(containing: windowFrame, among: screens)
    }

    static func screen(
        containingPoint point: CGPoint,
        among screens: [ScreenSnapshot]
    ) -> ScreenSnapshot? {
        screens.first { $0.frame.contains(point) }
            ?? screens.min {
                squaredDistance(from: point, to: $0.frame.center)
                    < squaredDistance(from: point, to: $1.frame.center)
            }
    }

    /// Accessibility coordinates grow downward, so smaller Y values are
    /// visually higher when two displays share the same horizontal position.
    static func orderedScreens(_ screens: [ScreenSnapshot]) -> [ScreenSnapshot] {
        screens.sorted {
            if abs($0.frame.midX - $1.frame.midX) > 0.5 {
                return $0.frame.midX < $1.frame.midX
            }
            if abs($0.frame.midY - $1.frame.midY) > 0.5 {
                return $0.frame.midY < $1.frame.midY
            }
            return $0.id < $1.id
        }
    }

    static func adjacentScreen(
        to currentID: String,
        offset: Int,
        among screens: [ScreenSnapshot]
    ) -> ScreenSnapshot? {
        let ordered = orderedScreens(screens)
        guard ordered.count > 1,
              let currentIndex = ordered.firstIndex(where: { $0.id == currentID }) else {
            return nil
        }
        let wrappedIndex = (currentIndex + offset % ordered.count + ordered.count)
            % ordered.count
        return ordered[wrappedIndex]
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }

    private static func squaredDistance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }
}

private nonisolated extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
