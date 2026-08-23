// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

nonisolated enum LayoutPanelVerticalSide: Sendable {
    case below
    case above
}

nonisolated enum LayoutPanelHorizontalAlignment: Sendable {
    case leading
    case trailing
}

nonisolated struct LayoutPanelPlacement: Equatable, Sendable {
    let frame: CGRect
    let verticalSide: LayoutPanelVerticalSide
    let horizontalAlignment: LayoutPanelHorizontalAlignment
}

nonisolated enum LayoutPanelPlacementEngine {
    static let edgeGap: CGFloat = 8
    static let maximumUsableFrameFraction: CGFloat = 0.9
    static let greenButtonMenuCoverOffset: CGFloat = 28

    /// All inputs and output use Accessibility's top-left global coordinates.
    static func placement(
        beside anchor: CGRect,
        requestedSize: CGSize,
        in usableFrame: CGRect,
        gap: CGFloat = edgeGap
    ) -> LayoutPanelPlacement? {
        guard [
            anchor.minX, anchor.minY, anchor.width, anchor.height,
            requestedSize.width, requestedSize.height,
            usableFrame.minX, usableFrame.minY, usableFrame.width, usableFrame.height,
        ].allSatisfy(\.isFinite),
        anchor.width > 0,
        anchor.height > 0,
        requestedSize.width > 0,
        requestedSize.height > 0,
        usableFrame.width > gap * 2,
        usableFrame.height > gap * 2,
        requestedSize.width <= usableFrame.width - gap * 2,
        requestedSize.height <= usableFrame.height - gap * 2,
        requestedSize.width <= usableFrame.width * maximumUsableFrameFraction,
        requestedSize.height <= usableFrame.height * maximumUsableFrameFraction else {
            return nil
        }

        let size = requestedSize
        let minimumX = usableFrame.minX + gap
        let maximumX = usableFrame.maxX - gap - size.width

        // Extend across the traffic-light cluster instead of beginning at the
        // green button. At popup-menu level this gives the compact, opaque
        // panel enough overlap to cover Apple's menu when both are present.
        let leadingX = anchor.minX - greenButtonMenuCoverOffset
        let trailingX = anchor.maxX - size.width
        let horizontalAlignment: LayoutPanelHorizontalAlignment
        let x: CGFloat
        if leadingX <= maximumX {
            horizontalAlignment = .leading
            x = max(minimumX, leadingX)
        } else {
            horizontalAlignment = .trailing
            x = max(minimumX, min(trailingX, maximumX))
        }

        let belowY = anchor.maxY + gap
        let aboveY = anchor.minY - gap - size.height
        let maximumY = usableFrame.maxY - gap - size.height
        let verticalSide: LayoutPanelVerticalSide
        let y: CGFloat
        if belowY <= maximumY {
            verticalSide = .below
            y = max(usableFrame.minY + gap, belowY)
        } else {
            verticalSide = .above
            y = max(usableFrame.minY + gap, min(aboveY, maximumY))
        }

        return LayoutPanelPlacement(
            frame: CGRect(origin: CGPoint(x: x, y: y), size: size),
            verticalSide: verticalSide,
            horizontalAlignment: horizontalAlignment
        )
    }
}
