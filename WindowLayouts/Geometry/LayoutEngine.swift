// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

nonisolated enum LayoutEngine {
    static let maximumPadding: CGFloat = 200
    static let edgeEpsilon = 0.000_001
    static let geometryMatchTolerance: CGFloat = 3

    /// Produces a rectangle in top-left global coordinates.
    static func rectangle(
        for layout: NormalizedRect,
        in usableFrame: CGRect,
        padding: CGFloat = 0
    ) -> CGRect {
        guard isUsable(usableFrame) else { return .zero }

        var left = logicalRound(usableFrame.minX + usableFrame.width * layout.x)
        var top = logicalRound(usableFrame.minY + usableFrame.height * layout.y)
        var right = logicalRound(
            usableFrame.minX + usableFrame.width * (layout.x + layout.width)
        )
        var bottom = logicalRound(
            usableFrame.minY + usableFrame.height * (layout.y + layout.height)
        )
        let safePadding = min(max(padding.rounded(), 0), maximumPadding)

        let horizontalInsets = constrainedInsets(
            size: right - left,
            start: layout.x > edgeEpsilon ? safePadding : 0,
            end: layout.x + layout.width < 1 - edgeEpsilon ? safePadding : 0
        )
        let verticalInsets = constrainedInsets(
            size: bottom - top,
            start: layout.y > edgeEpsilon ? safePadding : 0,
            end: layout.y + layout.height < 1 - edgeEpsilon ? safePadding : 0
        )

        left += horizontalInsets.start
        right -= horizontalInsets.end
        top += verticalInsets.start
        bottom -= verticalInsets.end

        return CGRect(
            x: left,
            y: top,
            width: max(1, right - left),
            height: max(1, bottom - top)
        )
    }

    static func centered(frame: CGRect, in usableFrame: CGRect) -> CGRect {
        guard isUsable(usableFrame) else { return .zero }
        let width = min(max(frame.width, 1), usableFrame.width)
        let height = min(max(frame.height, 1), usableFrame.height)
        return CGRect(
            x: logicalRound(usableFrame.minX + (usableFrame.width - width) / 2),
            y: logicalRound(usableFrame.minY + (usableFrame.height - height) / 2),
            width: width,
            height: height
        )
    }

    static func normalizedGeometry(of frame: CGRect, in usableFrame: CGRect) -> NormalizedRect {
        guard isFinite(frame), isUsable(usableFrame) else {
            return try! NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        }

        let width = clamp(frame.width / usableFrame.width, 1 / usableFrame.width, 1)
        let height = clamp(frame.height / usableFrame.height, 1 / usableFrame.height, 1)
        let x = clamp(
            (frame.minX - usableFrame.minX) / usableFrame.width,
            0,
            1 - width
        )
        let y = clamp(
            (frame.minY - usableFrame.minY) / usableFrame.height,
            0,
            1 - height
        )
        return try! NormalizedRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    static func clamped(_ frame: CGRect, to usableFrame: CGRect) -> CGRect {
        guard isFinite(frame), isUsable(usableFrame) else { return .zero }
        let width = min(max(frame.width, 1), usableFrame.width)
        let height = min(max(frame.height, 1), usableFrame.height)
        return CGRect(
            x: clamp(frame.minX, usableFrame.minX, usableFrame.maxX - width),
            y: clamp(frame.minY, usableFrame.minY, usableFrame.maxY - height),
            width: width,
            height: height
        )
    }

    /// Chooses an intermediate origin that keeps the window's current size on
    /// the destination display while AX changes its size. This avoids briefly
    /// crossing a display boundary when applying a smaller bottom/right zone.
    static func stagingOrigin(
        for intendedFrame: CGRect,
        currentSize: CGSize,
        in usableFrame: CGRect
    ) -> CGPoint {
        clamped(
            CGRect(origin: intendedFrame.origin, size: currentSize),
            to: usableFrame
        ).origin
    }

    /// A cross-display move should shrink before moving when the old logical
    /// size cannot fit on the destination. Moving the oversized frame first can
    /// make AppKit visibly constrain and rebound it while the AX resize lands.
    static func shouldResizeBeforeDisplayTransfer(
        currentSize: CGSize,
        to usableFrame: CGRect
    ) -> Bool {
        guard [
            currentSize.width, currentSize.height,
            usableFrame.width, usableFrame.height,
        ].allSatisfy(\.isFinite),
        currentSize.width > 0,
        currentSize.height > 0,
        usableFrame.width > 0,
        usableFrame.height > 0 else {
            return false
        }
        return currentSize.width > usableFrame.width + edgeEpsilon
            || currentSize.height > usableFrame.height + edgeEpsilon
    }

    /// Produces the visible first-stage frame for a monitor handoff. Preserve
    /// the old logical size when it fits; otherwise shrink to the intended
    /// destination size before moving so the intermediate window is contained.
    static func displayTransferStagingFrame(
        for intendedFrame: CGRect,
        currentSize: CGSize,
        in usableFrame: CGRect
    ) -> CGRect {
        let stagingSize = shouldResizeBeforeDisplayTransfer(
            currentSize: currentSize,
            to: usableFrame
        ) ? intendedFrame.size : currentSize
        return clamped(
            CGRect(origin: intendedFrame.origin, size: stagingSize),
            to: usableFrame
        )
    }

    static func approximatelyEqual(
        _ first: CGRect,
        _ second: CGRect,
        tolerance: CGFloat = geometryMatchTolerance
    ) -> Bool {
        abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }

    private static func constrainedInsets(
        size: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> (start: CGFloat, end: CGFloat) {
        let maximumTotal = max(0, size - 1)
        let requestedTotal = start + end
        guard requestedTotal > maximumTotal else { return (start, end) }
        guard requestedTotal > 0 else { return (0, 0) }

        let constrainedStart = floor(maximumTotal * start / requestedTotal)
        return (constrainedStart, maximumTotal - constrainedStart)
    }

    private static func clamp(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        max(minimum, min(value, maximum))
    }

    private static func logicalRound(_ value: CGFloat) -> CGFloat {
        value.rounded(.toNearestOrAwayFromZero)
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        isFinite(rect) && rect.width > 0 && rect.height > 0
    }
}
