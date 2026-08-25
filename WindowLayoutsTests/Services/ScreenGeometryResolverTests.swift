// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct ScreenGeometryResolverTests {
    private let screens = [
        ScreenSnapshot(
            id: "left",
            frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -1_920, y: 25, width: 1_920, height: 1_055)
        ),
        ScreenSnapshot(
            id: "primary",
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876)
        ),
    ]

    @Test func choosesScreenWithLargestIntersection() {
        #expect(ScreenGeometryResolver.screen(
            containing: CGRect(x: -100, y: 100, width: 400, height: 400),
            among: screens
        )?.id == "primary")
        #expect(ScreenGeometryResolver.visibleFrame(
            containing: CGRect(x: -100, y: 100, width: 400, height: 400),
            among: screens
        ) == screens[1].visibleFrame)
        #expect(ScreenGeometryResolver.visibleFrame(
            containing: CGRect(x: -1_800, y: 100, width: 600, height: 500),
            among: screens
        ) == screens[0].visibleFrame)
    }

    @Test func choosesNearestScreenForAnOffscreenWindow() {
        #expect(ScreenGeometryResolver.visibleFrame(
            containing: CGRect(x: 2_000, y: 100, width: 300, height: 300),
            among: screens
        ) == screens[1].visibleFrame)
    }

    @Test func dragTargetDisplayOverridesWindowIntersectionAtEverySharedEdge() {
        let center = ScreenSnapshot(
            id: "center",
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_000, height: 776)
        )
        let surrounding = [
            ScreenSnapshot(
                id: "above",
                frame: CGRect(x: 0, y: -800, width: 1_000, height: 800),
                visibleFrame: CGRect(x: 0, y: -800, width: 1_000, height: 776)
            ),
            ScreenSnapshot(
                id: "below",
                frame: CGRect(x: 0, y: 800, width: 1_000, height: 800),
                visibleFrame: CGRect(x: 0, y: 824, width: 1_000, height: 776)
            ),
            ScreenSnapshot(
                id: "left",
                frame: CGRect(x: -1_000, y: 0, width: 1_000, height: 800),
                visibleFrame: CGRect(x: -1_000, y: 24, width: 1_000, height: 776)
            ),
            ScreenSnapshot(
                id: "right",
                frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
                visibleFrame: CGRect(x: 1_000, y: 24, width: 1_000, height: 776)
            )
        ]
        let screens = [center] + surrounding
        let windowStillMostlyOnCenter = CGRect(
            x: 100,
            y: 100,
            width: 800,
            height: 600
        )

        for destination in surrounding {
            #expect(
                ScreenGeometryResolver.destinationScreen(
                    for: windowStillMostlyOnCenter,
                    preferredScreenID: destination.id,
                    among: screens
                ) == destination
            )
        }
    }

    @Test func missingDragTargetDisplayFallsBackToWindowIntersection() {
        #expect(
            ScreenGeometryResolver.destinationScreen(
                for: CGRect(x: 1_050, y: 100, width: 400, height: 400),
                preferredScreenID: "disconnected",
                among: screens
            ) == screens[1]
        )
    }

    @Test func returnsNilWithoutScreens() {
        #expect(ScreenGeometryResolver.screen(
            containing: .zero,
            among: []
        ) == nil)
        #expect(ScreenGeometryResolver.visibleFrame(
            containing: .zero,
            among: []
        ) == nil)
    }

    @Test func detectsAFullDisplayFrameWithoutPrivateAttributes() {
        #expect(ScreenGeometryResolver.isLikelyNativeFullScreen(
            screens[1].frame,
            among: screens
        ))
        #expect(!ScreenGeometryResolver.isLikelyNativeFullScreen(
            screens[1].visibleFrame,
            among: screens
        ))

        let screenWithoutReservedEdges = ScreenSnapshot(
            id: "edge-to-edge",
            frame: CGRect(x: 1_440, y: 0, width: 1_280, height: 720),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 1_280, height: 720)
        )
        #expect(ScreenGeometryResolver.isLikelyNativeFullScreen(
            screenWithoutReservedEdges.frame,
            among: [screenWithoutReservedEdges]
        ))
    }

    @Test func greenButtonPanelAllowsMaximizedWindowOnEdgeToEdgeDisplay() {
        let edgeToEdge = ScreenSnapshot(
            id: "external",
            frame: CGRect(x: 1_440, y: 0, width: 2_560, height: 1_440),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 2_560, height: 1_440)
        )

        #expect(ScreenGeometryResolver.allowsGreenButtonPanel(
            for: edgeToEdge.visibleFrame,
            on: edgeToEdge
        ))
    }

    @Test func greenButtonPanelRejectsFullDisplayFrameWhenUsableFrameIsSmaller() {
        #expect(!ScreenGeometryResolver.allowsGreenButtonPanel(
            for: screens[1].frame,
            on: screens[1]
        ))
        #expect(ScreenGeometryResolver.allowsGreenButtonPanel(
            for: screens[1].visibleFrame,
            on: screens[1]
        ))
    }

    @Test func monitorOrderUsesAccessibilityCoordinatesAndWraps() {
        let belowPrimary = ScreenSnapshot(
            id: "below",
            frame: CGRect(x: 0, y: 900, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 900, width: 1_440, height: 876)
        )
        let unordered = [belowPrimary, screens[1], screens[0]]

        #expect(ScreenGeometryResolver.orderedScreens(unordered).map(\.id)
            == ["left", "primary", "below"])
        #expect(ScreenGeometryResolver.adjacentScreen(
            to: "below",
            offset: 1,
            among: unordered
        )?.id == "left")
        #expect(ScreenGeometryResolver.adjacentScreen(
            to: "left",
            offset: -1,
            among: unordered
        )?.id == "below")
    }

    @Test func adjacentMonitorRequiresAnotherKnownScreen() {
        #expect(ScreenGeometryResolver.adjacentScreen(
            to: "primary",
            offset: 1,
            among: [screens[1]]
        ) == nil)
        #expect(ScreenGeometryResolver.adjacentScreen(
            to: "missing",
            offset: 1,
            among: screens
        ) == nil)
    }
}
