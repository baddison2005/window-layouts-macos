// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

struct WindowFillGroupTests {
    @Test func catalogProvidesNonoverlappingBuiltInGroupsAndNamedCustomGroups() throws {
        let customGroup = LayoutGroup(name: "Writing")
        let first = try NormalizedRect(x: 0, y: 0, width: 0.4, height: 1)
        let second = try NormalizedRect(x: 0.4, y: 0, width: 0.6, height: 1)
        let library = LayoutLibrary(
            customLayouts: [
                LayoutDefinition(name: "Notes", normalizedRect: first, groupID: customGroup.id),
                LayoutDefinition(name: "Editor", normalizedRect: second, groupID: customGroup.id),
            ],
            customGroups: [customGroup]
        )

        let groups = WindowFillGroupCatalog.groups(for: library)

        #expect(groups.map(\.name) == [
            "Horizontal Halves",
            "Vertical Halves",
            "Quarters",
            "Thirds",
            "Writing",
        ])
        #expect(groups.last?.layouts == [first, second])
    }

    @Test func catalogOmitsEmptyCustomGroups() {
        let emptyGroup = LayoutGroup(name: "Empty")
        let library = LayoutLibrary(customGroups: [emptyGroup])
        #expect(!WindowFillGroupCatalog.groups(for: library).map(\.name).contains("Empty"))
        #expect(WindowFillGroupCatalog.shortcutGroups(for: library).contains {
            $0.id == "custom.\(emptyGroup.id.uuidString)" && $0.layouts.isEmpty
        })
    }
}
