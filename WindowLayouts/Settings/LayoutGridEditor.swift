// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct LayoutGridEditor: View {
    @Binding var normalizedRect: NormalizedRect

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let selection = LayoutGridSelection(normalizedRect: normalizedRect)
                let cellWidth = size.width / Double(LayoutGridSelection.columns)
                let cellHeight = size.height / Double(LayoutGridSelection.rows)
                let selectedRect = CGRect(
                    x: Double(selection.column) * cellWidth,
                    y: Double(selection.row) * cellHeight,
                    width: Double(selection.columnSpan) * cellWidth,
                    height: Double(selection.rowSpan) * cellHeight
                )

                context.fill(
                    Path(selectedRect),
                    with: .color(.accentColor.opacity(0.62))
                )

                var grid = Path()
                for column in 0...LayoutGridSelection.columns {
                    let x = Double(column) * cellWidth
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for row in 0...LayoutGridSelection.rows {
                    let y = Double(row) * cellHeight
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(
                    grid,
                    with: .color(Color(nsColor: .separatorColor).opacity(0.7)),
                    lineWidth: 0.75
                )
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = cell(at: value.startLocation, in: proxy.size)
                        let end = cell(at: value.location, in: proxy.size)
                        normalizedRect = LayoutGridSelection.spanning(
                            startColumn: start.column,
                            startRow: start.row,
                            endColumn: end.column,
                            endRow: end.row
                        ).normalizedRect
                    }
            )
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityLabel("Custom layout grid")
        .accessibilityValue(geometryDescription)
        .accessibilityHint(
            "Use the named accessibility actions to move or resize the selected region."
        )
        .accessibilityAction(named: "Move selection left") {
            adjustSelection(columnDelta: -1)
        }
        .accessibilityAction(named: "Move selection right") {
            adjustSelection(columnDelta: 1)
        }
        .accessibilityAction(named: "Move selection up") {
            adjustSelection(rowDelta: -1)
        }
        .accessibilityAction(named: "Move selection down") {
            adjustSelection(rowDelta: 1)
        }
        .accessibilityAction(named: "Make selection narrower") {
            adjustSelection(columnSpanDelta: -1)
        }
        .accessibilityAction(named: "Make selection wider") {
            adjustSelection(columnSpanDelta: 1)
        }
        .accessibilityAction(named: "Make selection shorter") {
            adjustSelection(rowSpanDelta: -1)
        }
        .accessibilityAction(named: "Make selection taller") {
            adjustSelection(rowSpanDelta: 1)
        }
    }

    private var geometryDescription: String {
        let selection = LayoutGridSelection(normalizedRect: normalizedRect)
        return "Column \(selection.column + 1), row \(selection.row + 1), width \(selection.columnSpan), height \(selection.rowSpan)"
    }

    private func adjustSelection(
        columnDelta: Int = 0,
        rowDelta: Int = 0,
        columnSpanDelta: Int = 0,
        rowSpanDelta: Int = 0
    ) {
        let selection = LayoutGridSelection(normalizedRect: normalizedRect)
        let columnSpan = max(
            1,
            min(
                LayoutGridSelection.columns - selection.column,
                selection.columnSpan + columnSpanDelta
            )
        )
        let rowSpan = max(
            1,
            min(
                LayoutGridSelection.rows - selection.row,
                selection.rowSpan + rowSpanDelta
            )
        )
        let column = max(
            0,
            min(
                LayoutGridSelection.columns - columnSpan,
                selection.column + columnDelta
            )
        )
        let row = max(
            0,
            min(
                LayoutGridSelection.rows - rowSpan,
                selection.row + rowDelta
            )
        )
        normalizedRect = LayoutGridSelection(
            column: column,
            row: row,
            columnSpan: columnSpan,
            rowSpan: rowSpan
        ).normalizedRect
    }

    private func cell(at point: CGPoint, in size: CGSize) -> (column: Int, row: Int) {
        let safeWidth = max(size.width, 1)
        let safeHeight = max(size.height, 1)
        let column = Int(floor(point.x / safeWidth * Double(LayoutGridSelection.columns)))
        let row = Int(floor(point.y / safeHeight * Double(LayoutGridSelection.rows)))
        return (
            max(0, min(column, LayoutGridSelection.columns - 1)),
            max(0, min(row, LayoutGridSelection.rows - 1))
        )
    }
}
