// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct MonitorTransferTests {
    private let source = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    private let destination = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)

    @Test func preservesRecognizedLayoutAndPadding() {
        let sourceFrame = LayoutEngine.rectangle(
            for: FixedLayout.leftHalf.normalizedRect,
            in: source,
            padding: 12
        )
        #expect(MonitorTransfer.destination(
            for: sourceFrame,
            from: source,
            to: destination,
            padding: 12
        ) == CGRect(x: -1_920, y: 0, width: 948, height: 1_080))
    }

    @Test func preservesFreeFormNormalizedGeometry() {
        #expect(MonitorTransfer.destination(
            for: CGRect(x: 144, y: 90, width: 720, height: 450),
            from: source,
            to: destination,
            padding: 20
        ) == CGRect(x: -1_728, y: 108, width: 960, height: 540))
    }

    @Test func preservesARecognizedCustomLayoutAcrossMonitors() throws {
        let custom = try NormalizedRect(
            x: 0.25,
            y: 0.25,
            width: 0.5,
            height: 0.5
        )
        let sourceFrame = LayoutEngine.rectangle(
            for: custom,
            in: source,
            padding: 10
        )

        #expect(MonitorTransfer.destination(
            for: sourceFrame,
            from: source,
            to: destination,
            padding: 10,
            layouts: [custom]
        ) == LayoutEngine.rectangle(
            for: custom,
            in: destination,
            padding: 10
        ))
    }

    @Test func rememberedLayoutOverridesApplicationMinimumWidth() {
        let macBook = CGRect(x: 0, y: 49, width: 2_624, height: 1_573)
        let lg = CGRect(x: -1_191, y: -2_160, width: 5_120, height: 2_160)
        let layout = FixedLayout.leftThird.normalizedRect
        let constrainedOnMac = CGRect(x: 0, y: 49, width: 940, height: 1_573)

        let inferred = MonitorTransfer.destination(
            for: constrainedOnMac,
            from: macBook,
            to: lg,
            padding: 0
        )
        let remembered = MonitorTransfer.destination(
            for: constrainedOnMac,
            from: macBook,
            to: lg,
            padding: 0,
            preferredLayout: layout
        )

        #expect(inferred.width == 1_834)
        #expect(remembered == LayoutEngine.rectangle(for: layout, in: lg))
        #expect(remembered.width == 1_707)
    }

    @Test func rememberedLayoutOverridesApplicationMinimumHeight() throws {
        let macBook = CGRect(x: 0, y: 49, width: 2_624, height: 1_573)
        let lg = CGRect(x: -1_191, y: -2_160, width: 5_120, height: 2_160)
        let layout = try NormalizedRect(
            x: 0,
            y: 0,
            width: 2.0 / 3.0,
            height: 1.0 / 3.0
        )
        let constrainedOnMac = CGRect(x: 0, y: 49, width: 1_749, height: 600)

        let remembered = MonitorTransfer.destination(
            for: constrainedOnMac,
            from: macBook,
            to: lg,
            padding: 0,
            preferredLayout: layout
        )

        #expect(remembered == LayoutEngine.rectangle(for: layout, in: lg))
        #expect(remembered.height == 720)
    }

    @Test func manualResizeInvalidatesRememberedLayout() {
        let layout = FixedLayout.leftThird.normalizedRect
        let accepted = CGRect(x: 0, y: 49, width: 940, height: 1_573)

        #expect(MonitorTransfer.applicableRememberedLayout(
            layout,
            currentFrame: accepted,
            lastAppliedFrame: accepted
        ) == layout)
        #expect(MonitorTransfer.applicableRememberedLayout(
            layout,
            currentFrame: CGRect(x: 0, y: 49, width: 1_050, height: 1_573),
            lastAppliedFrame: accepted
        ) == nil)
    }

    @Test func monitorOrderIsDeterministicAndWraps() {
        let displays = [
            DisplayGeometry(id: "right", frame: CGRect(x: 1_440, y: 0, width: 1_280, height: 720)),
            DisplayGeometry(id: "primary", frame: source),
            DisplayGeometry(id: "left", frame: destination),
        ]
        #expect(MonitorTransfer.orderedDisplays(displays).map(\.id) == ["left", "primary", "right"])
        #expect(MonitorTransfer.adjacentDisplay(to: "right", offset: 1, in: displays)?.id == "left")
        #expect(MonitorTransfer.adjacentDisplay(to: "left", offset: -1, in: displays)?.id == "right")
    }

    @Test func verticalTieBreakOrdersTopToBottom() {
        let displays = [
            DisplayGeometry(id: "below", frame: CGRect(x: 0, y: -900, width: 1_440, height: 900)),
            DisplayGeometry(id: "above", frame: CGRect(x: 0, y: 900, width: 1_440, height: 900)),
            DisplayGeometry(id: "primary", frame: source),
        ]
        #expect(MonitorTransfer.orderedDisplays(displays).map(\.id) == ["above", "primary", "below"])
    }
}
