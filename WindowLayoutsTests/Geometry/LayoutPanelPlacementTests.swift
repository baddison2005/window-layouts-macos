// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct LayoutPanelPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    @Test func opensBelowAndExtendsLeftOfTheGreenButtonWhenSpaceAllows() throws {
        let placement = try #require(LayoutPanelPlacementEngine.placement(
            beside: CGRect(x: 60, y: 16, width: 14, height: 14),
            requestedSize: CGSize(width: 310, height: 500),
            in: screen
        ))

        #expect(placement.verticalSide == .below)
        #expect(placement.horizontalAlignment == .leading)
        #expect(placement.frame == CGRect(x: 32, y: 38, width: 310, height: 500))
    }

    @Test func leftOverlapRemainsInsideTheUsableFrame() throws {
        let placement = try #require(LayoutPanelPlacementEngine.placement(
            beside: CGRect(x: 16, y: 16, width: 14, height: 14),
            requestedSize: CGSize(width: 310, height: 500),
            in: screen
        ))

        #expect(placement.horizontalAlignment == .leading)
        #expect(placement.frame.minX == screen.minX + LayoutPanelPlacementEngine.edgeGap)
    }

    @Test func switchesEdgesAndNeverLeavesUsableFrame() throws {
        let placement = try #require(LayoutPanelPlacementEngine.placement(
            beside: CGRect(x: 1_410, y: 870, width: 14, height: 14),
            requestedSize: CGSize(width: 310, height: 500),
            in: screen
        ))

        #expect(placement.verticalSide == .above)
        #expect(placement.horizontalAlignment == .trailing)
        #expect(screen.contains(placement.frame))
        #expect(placement.frame.maxX <= screen.maxX - 8)
        #expect(placement.frame.maxY <= screen.maxY - 8)
    }

    @Test func refusesPanelInsteadOfCreatingANearlyScreenSizedSurface() {
        let tinyScreen = CGRect(x: -800, y: -600, width: 500, height: 360)
        let placement = LayoutPanelPlacementEngine.placement(
            beside: CGRect(x: -760, y: -570, width: 14, height: 14),
            requestedSize: CGSize(width: 1_500, height: 1_000),
            in: tinyScreen
        )

        #expect(placement == nil)
    }

    @Test func refusesAFittingButNoncompactPanel() {
        let shortScreen = CGRect(x: 0, y: 0, width: 800, height: 700)

        let placement = LayoutPanelPlacementEngine.placement(
            beside: CGRect(x: 20, y: 20, width: 14, height: 14),
            requestedSize: CGSize(width: 410, height: 680),
            in: shortScreen
        )

        #expect(placement == nil)
    }
}
