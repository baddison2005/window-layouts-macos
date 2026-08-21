// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct DragTargetLayoutTests {
    private let usable = CGRect(x: -1_191, y: -2_160, width: 3_413, height: 2_160)

    @Test func zoneTargetsWithTheSameCenterStackWithoutOverlapping() throws {
        let definitions = [
            definition("centerTwoThirds", rect: (1.0 / 6, 0, 2.0 / 3, 1)),
            definition("centerThird", rect: (1.0 / 3, 0, 1.0 / 3, 1)),
            definition("maximize", rect: (0, 0, 1, 1)),
        ]

        let placements = DragTargetLayoutEngine.placements(
            for: definitions,
            style: .zones,
            in: usable
        )

        #expect(placements.count == 3)
        #expect(Set(placements.map(\.groupKey)).count == 1)
        #expect(placements.allSatisfy { usable.contains($0.frame) })
        #expect(!placements[0].frame.intersects(placements[1].frame))
        #expect(!placements[1].frame.intersects(placements[2].frame))
    }

    @Test func topTargetsWrapAndRemainInsideAnOffsetUsableFrame() throws {
        let definitions = (0..<14).map {
            definition("layout-\($0)", rect: (0, 0, 0.5, 1))
        }

        let placements = DragTargetLayoutEngine.placements(
            for: definitions,
            style: .top,
            in: usable
        )

        #expect(placements.count == 14)
        #expect(Set(placements.map { $0.frame.minY }).count == 2)
        #expect(placements.allSatisfy { usable.contains($0.frame) })
        #expect(DragTargetLayoutEngine.stripFrame(for: placements).map(usable.contains) == true)
    }

    @Test func proximityRevealRetainsAStackWhilePointerIsOverItsCards() throws {
        let placements = DragTargetLayoutEngine.placements(
            for: [definition("left", rect: (0, 0, 0.5, 1))],
            style: .zones,
            in: usable
        )
        let placement = try #require(placements.first)
        let zonePoint = CGPoint(x: usable.minX + usable.width * 0.25, y: usable.midY)

        let revealed = DragTargetLayoutEngine.revealedZoneGroup(
            at: zonePoint,
            placements: placements,
            in: usable,
            retaining: nil
        )
        #expect(revealed == placement.groupKey)
        #expect(
            DragTargetLayoutEngine.revealedZoneGroup(
                at: CGPoint(x: placement.frame.midX, y: placement.frame.midY),
                placements: placements,
                in: usable,
                retaining: revealed
            ) == placement.groupKey
        )
    }

    @Test func topStripUsesTriggerThenRetainsInsideStrip() throws {
        let placements = DragTargetLayoutEngine.placements(
            for: [definition("left", rect: (0, 0, 0.5, 1))],
            style: .top,
            in: usable
        )
        let trigger = DragTargetLayoutEngine.topTriggerFrame(in: usable)
        #expect(
            DragTargetLayoutEngine.shouldRevealTopStrip(
                at: CGPoint(x: trigger.midX, y: trigger.midY),
                placements: placements,
                in: usable,
                currentlyRevealed: false
            )
        )
        let placement = try #require(placements.first)
        #expect(
            DragTargetLayoutEngine.shouldRevealTopStrip(
                at: CGPoint(x: placement.frame.midX, y: placement.frame.midY),
                placements: placements,
                in: usable,
                currentlyRevealed: true
            )
        )
    }

    @Test func hitTestingIgnoresTargetsThatAreNotVisible() throws {
        let placements = DragTargetLayoutEngine.placements(
            for: [definition("left", rect: (0, 0, 0.5, 1))],
            style: .zones,
            in: usable
        )
        let placement = try #require(placements.first)
        let point = CGPoint(x: placement.frame.midX, y: placement.frame.midY)

        #expect(DragTargetLayoutEngine.hoveredPlacement(at: point, among: []) == nil)
        #expect(
            DragTargetLayoutEngine.hoveredPlacement(at: point, among: placements)?.id
                == placement.id
        )
    }

    @Test func previewUsesSharedPaddingAndCenterGeometry() throws {
        let layout = definition("middle", rect: (0.25, 0, 0.5, 1))
        #expect(
            DragTargetLayoutEngine.previewFrame(
                for: layout,
                draggedWindowFrame: .zero,
                in: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                padding: 20
            ) == CGRect(x: 270, y: 0, width: 460, height: 800)
        )

        let center = DragTargetDefinition(id: "center", name: "Center", kind: .center)
        #expect(
            DragTargetLayoutEngine.previewFrame(
                for: center,
                draggedWindowFrame: CGRect(x: 10, y: 20, width: 400, height: 300),
                in: CGRect(x: 100, y: 200, width: 1_000, height: 800),
                padding: 0
            ) == CGRect(x: 400, y: 450, width: 400, height: 300)
        )
    }

    private func definition(
        _ id: String,
        rect: (Double, Double, Double, Double)
    ) -> DragTargetDefinition {
        DragTargetDefinition(
            id: id,
            name: id,
            kind: .layout(
                try! NormalizedRect(
                    x: rect.0,
                    y: rect.1,
                    width: rect.2,
                    height: rect.3
                )
            )
        )
    }
}
