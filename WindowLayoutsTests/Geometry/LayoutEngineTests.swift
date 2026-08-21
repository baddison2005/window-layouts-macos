// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct LayoutEngineTests {
    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    @Test func fixedHalvesUseLogicalPoints() {
        #expect(LayoutEngine.rectangle(
            for: FixedLayout.leftHalf.normalizedRect,
            in: screen
        ) == CGRect(x: 0, y: 0, width: 720, height: 900))
        #expect(LayoutEngine.rectangle(
            for: FixedLayout.rightHalf.normalizedRect,
            in: screen
        ) == CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    @Test func paddingInsetsOnlyInternalEdges() {
        #expect(LayoutEngine.rectangle(
            for: FixedLayout.leftHalf.normalizedRect,
            in: screen,
            padding: 10
        ) == CGRect(x: 0, y: 0, width: 710, height: 900))
        #expect(LayoutEngine.rectangle(
            for: FixedLayout.rightHalf.normalizedRect,
            in: screen,
            padding: 10
        ) == CGRect(x: 730, y: 0, width: 710, height: 900))
        #expect(LayoutEngine.rectangle(
            for: FixedLayout.centerThird.normalizedRect,
            in: screen,
            padding: 10
        ) == CGRect(x: 490, y: 0, width: 460, height: 900))
    }

    @Test func excessivePaddingRetainsOnePointSize() throws {
        let tinyCenter = try NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let result = LayoutEngine.rectangle(
            for: tinyCenter,
            in: CGRect(x: 0, y: 0, width: 10, height: 10),
            padding: 200
        )
        #expect(result.width == 1)
        #expect(result.height == 1)
    }

    @Test func normalizationClampsAWindowIntoUsableBounds() {
        let normalized = LayoutEngine.normalizedGeometry(
            of: CGRect(x: -100, y: 100, width: 800, height: 450),
            in: screen
        )
        #expect(normalized.x == 0)
        #expect(normalized.y == 100.0 / 900.0)
        #expect(normalized.width == 800.0 / 1_440.0)
        #expect(normalized.height == 0.5)
    }

    @Test func centeringPreservesAndConstrainsSize() {
        #expect(LayoutEngine.centered(
            frame: CGRect(x: 30, y: 20, width: 600, height: 400),
            in: screen
        ) == CGRect(x: 420, y: 250, width: 600, height: 400))
        #expect(LayoutEngine.centered(
            frame: CGRect(x: 30, y: 20, width: 2_000, height: 1_000),
            in: screen
        ) == screen)
    }

    @Test func stagingOriginKeepsOldSizeAboveAdjacentDisplay() {
        // The external display is above the primary display in Accessibility
        // coordinates and ends at y = 0. Moving a tall window directly to the
        // final bottom-zone origin would temporarily extend below that edge.
        let external = CGRect(x: -1_191, y: -2_160, width: 5_120, height: 2_160)
        let intendedBottomZone = CGRect(
            x: -1_191,
            y: -720,
            width: 3_413,
            height: 720
        )
        let oldSize = CGSize(width: 2_000, height: 1_440)

        let origin = LayoutEngine.stagingOrigin(
            for: intendedBottomZone,
            currentSize: oldSize,
            in: external
        )

        #expect(origin == CGPoint(x: -1_191, y: -1_440))
        #expect(origin.y + oldSize.height == external.maxY)
    }

    @Test func crossDisplayOrderShrinksOnlyWhenOldSizeCannotFit() {
        let macBook = CGRect(x: 0, y: 0, width: 2_624, height: 1_573)
        let lg = CGRect(x: -1_191, y: -2_160, width: 5_120, height: 2_160)

        #expect(!LayoutEngine.shouldResizeBeforeDisplayTransfer(
            currentSize: CGSize(width: 1_312, height: 1_573),
            to: lg
        ))
        #expect(LayoutEngine.shouldResizeBeforeDisplayTransfer(
            currentSize: CGSize(width: 2_560, height: 2_160),
            to: macBook
        ))
    }

    @Test func displayTransferStagingPreservesOrShrinksByDirection() {
        let macBook = CGRect(x: 0, y: 0, width: 2_624, height: 1_573)
        let lg = CGRect(x: -1_191, y: -2_160, width: 5_120, height: 2_160)
        let intendedOnLG = CGRect(x: -1_191, y: -2_160, width: 2_560, height: 2_160)
        let intendedOnMac = CGRect(x: 0, y: 0, width: 1_312, height: 1_573)

        #expect(LayoutEngine.displayTransferStagingFrame(
            for: intendedOnLG,
            currentSize: CGSize(width: 1_312, height: 1_573),
            in: lg
        ) == CGRect(x: -1_191, y: -2_160, width: 1_312, height: 1_573))

        #expect(LayoutEngine.displayTransferStagingFrame(
            for: intendedOnMac,
            currentSize: CGSize(width: 2_560, height: 2_160),
            in: macBook
        ) == intendedOnMac)
    }
}
