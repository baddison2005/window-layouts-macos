// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated struct LayoutGridSelection: Equatable, Sendable {
    static let columns = 24
    static let rows = 12

    var column: Int
    var row: Int
    var columnSpan: Int
    var rowSpan: Int

    init(column: Int, row: Int, columnSpan: Int, rowSpan: Int) {
        self.column = Self.clamp(column, minimum: 0, maximum: Self.columns - 1)
        self.row = Self.clamp(row, minimum: 0, maximum: Self.rows - 1)
        self.columnSpan = Self.clamp(
            columnSpan,
            minimum: 1,
            maximum: Self.columns - self.column
        )
        self.rowSpan = Self.clamp(
            rowSpan,
            minimum: 1,
            maximum: Self.rows - self.row
        )
    }

    init(normalizedRect: NormalizedRect) {
        let column = Int((normalizedRect.x * Double(Self.columns)).rounded())
        let row = Int((normalizedRect.y * Double(Self.rows)).rounded())
        self.init(
            column: column,
            row: row,
            columnSpan: Int((normalizedRect.width * Double(Self.columns)).rounded()),
            rowSpan: Int((normalizedRect.height * Double(Self.rows)).rounded())
        )
    }

    static func spanning(
        startColumn: Int,
        startRow: Int,
        endColumn: Int,
        endRow: Int
    ) -> LayoutGridSelection {
        let left = min(startColumn, endColumn)
        let top = min(startRow, endRow)
        let right = max(startColumn, endColumn)
        let bottom = max(startRow, endRow)
        return LayoutGridSelection(
            column: left,
            row: top,
            columnSpan: right - left + 1,
            rowSpan: bottom - top + 1
        )
    }

    var normalizedRect: NormalizedRect {
        try! NormalizedRect(
            x: Double(column) / Double(Self.columns),
            y: Double(row) / Double(Self.rows),
            width: Double(columnSpan) / Double(Self.columns),
            height: Double(rowSpan) / Double(Self.rows)
        )
    }

    private static func clamp(_ value: Int, minimum: Int, maximum: Int) -> Int {
        max(minimum, min(value, maximum))
    }
}
