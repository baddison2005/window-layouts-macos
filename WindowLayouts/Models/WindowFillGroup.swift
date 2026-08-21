// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated struct WindowFillGroup: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let layouts: [NormalizedRect]
}

nonisolated enum WindowFillGroupCatalog {
    static func groups(for library: LayoutLibrary) -> [WindowFillGroup] {
        shortcutGroups(for: library).filter { !$0.layouts.isEmpty }
    }

    static func shortcutGroups(for library: LayoutLibrary) -> [WindowFillGroup] {
        var groups = [
            WindowFillGroup(
                id: "builtin.horizontal-halves",
                name: String(localized: "Horizontal Halves"),
                layouts: [
                    FixedLayout.leftHalf.normalizedRect,
                    FixedLayout.rightHalf.normalizedRect,
                ]
            ),
            WindowFillGroup(
                id: "builtin.vertical-halves",
                name: String(localized: "Vertical Halves"),
                layouts: [
                    FixedLayout.topHalf.normalizedRect,
                    FixedLayout.bottomHalf.normalizedRect,
                ]
            ),
            WindowFillGroup(
                id: "builtin.quarters",
                name: String(localized: "Quarters"),
                layouts: [
                    FixedLayout.topLeft.normalizedRect,
                    FixedLayout.topRight.normalizedRect,
                    FixedLayout.bottomLeft.normalizedRect,
                    FixedLayout.bottomRight.normalizedRect,
                ]
            ),
            WindowFillGroup(
                id: "builtin.thirds",
                name: String(localized: "Thirds"),
                layouts: [
                    FixedLayout.leftThird.normalizedRect,
                    FixedLayout.centerThird.normalizedRect,
                    FixedLayout.rightThird.normalizedRect,
                ]
            ),
        ]

        groups.append(contentsOf: library.customGroups.map { group in
            let layouts = library.customLayouts
                .filter { $0.groupID == group.id }
                .map(\.normalizedRect)
            return WindowFillGroup(
                id: "custom.\(group.id.uuidString)",
                name: group.name,
                layouts: layouts
            )
        })
        return groups
    }
}

nonisolated struct WindowFillResult: Equatable, Sendable {
    let appliedCount: Int
    let skippedCount: Int
}
