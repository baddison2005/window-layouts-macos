// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import WindowLayouts

struct LayoutGridSelectionTests {
    @Test func usesTheKDETwentyFourByTwelveGrid() {
        #expect(LayoutGridSelection.columns == 24)
        #expect(LayoutGridSelection.rows == 12)

        let selection = LayoutGridSelection(
            normalizedRect: FixedLayout.centerThird.normalizedRect
        )
        #expect(selection.column == 8)
        #expect(selection.row == 0)
        #expect(selection.columnSpan == 8)
        #expect(selection.rowSpan == 12)
        #expect(selection.normalizedRect == FixedLayout.centerThird.normalizedRect)
    }

    @Test func reverseDragProducesTheSameNormalizedRectangle() throws {
        let selection = LayoutGridSelection.spanning(
            startColumn: 17,
            startRow: 8,
            endColumn: 6,
            endRow: 2
        )
        #expect(selection.column == 6)
        #expect(selection.row == 2)
        #expect(selection.columnSpan == 12)
        #expect(selection.rowSpan == 7)
        #expect(selection.normalizedRect == (
            try NormalizedRect(
                x: 0.25,
                y: 2.0 / 12.0,
                width: 0.5,
                height: 7.0 / 12.0
            )
        ))
    }

    @Test func selectionIsClampedToTheGrid() {
        let selection = LayoutGridSelection(
            column: -4,
            row: 20,
            columnSpan: 100,
            rowSpan: 100
        )
        #expect(selection.column == 0)
        #expect(selection.row == 11)
        #expect(selection.columnSpan == 24)
        #expect(selection.rowSpan == 1)
    }
}
