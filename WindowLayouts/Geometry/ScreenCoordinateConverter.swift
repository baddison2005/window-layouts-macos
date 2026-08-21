// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Converts only at the AppKit/Accessibility boundary.
///
/// AppKit's global Y axis grows upward. Accessibility's global Y axis grows
/// downward from the top edge of the display containing the menu bar.
nonisolated struct ScreenCoordinateConverter: Equatable, Sendable {
    let referenceTop: CGFloat

    /// AppKit's global origin belongs to the primary display even if a screen
    /// API returns the focused display first. Selecting the frame rooted at
    /// (0, 0) keeps the Accessibility Y-axis conversion stable as focus moves
    /// between displays.
    static func referenceTop(forAppKitFrames frames: [CGRect]) -> CGFloat? {
        guard let fallback = frames.first else { return nil }
        let primary = frames.first {
            abs($0.minX) < 0.5 && abs($0.minY) < 0.5
        } ?? fallback
        return primary.maxY
    }

    func accessibilityRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: referenceTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func accessibilityPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: referenceTop - point.y)
    }

    func appKitRect(fromAccessibility rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: referenceTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func appKitPoint(fromAccessibility point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: referenceTop - point.y)
    }
}
