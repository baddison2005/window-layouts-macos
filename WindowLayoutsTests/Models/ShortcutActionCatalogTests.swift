// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

struct ShortcutActionCatalogTests {
    @Test func customActionIDSurvivesReordering() throws {
        let rect = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let first = LayoutDefinition(name: "First", normalizedRect: rect)
        let second = LayoutDefinition(name: "Second", normalizedRect: rect)
        let original = LayoutLibrary(customLayouts: [first, second])
        let reordered = LayoutLibrary(customLayouts: [second, first])

        let originalIDs = Set(
            ShortcutActionCatalog.descriptors(for: original).map(\.id)
        )
        let reorderedIDs = Set(
            ShortcutActionCatalog.descriptors(for: reordered).map(\.id)
        )

        #expect(originalIDs == reorderedIDs)
        #expect(first.shortcutActionID.rawValue.contains(first.id.uuidString.lowercased()))
    }

    @Test func reportsInternalConflictByPhysicalCombination() {
        let existing = KeyboardShortcut(
            keyCode: 123,
            modifiers: [.control, .option],
            keyLabel: "←"
        )
        let candidate = KeyboardShortcut(
            keyCode: 123,
            modifiers: [.control, .option],
            keyLabel: "Left"
        )
        let library = LayoutLibrary(shortcuts: ["fixed.leftHalf": existing])

        #expect(ShortcutActionCatalog.conflictingActionID(
            for: candidate,
            excluding: ShortcutActionID(rawValue: "fixed.rightHalf"),
            in: library
        ) == ShortcutActionID(rawValue: "fixed.leftHalf"))
    }

    @Test func fillGroupActionIDsAreStableAcrossRenamingAndReordering() throws {
        let firstGroup = LayoutGroup(name: "Writing")
        let secondGroup = LayoutGroup(name: "Planning")
        let rect = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let layout = LayoutDefinition(
            name: "Editor",
            normalizedRect: rect,
            groupID: firstGroup.id
        )
        let original = LayoutLibrary(
            customLayouts: [layout],
            customGroups: [firstGroup, secondGroup]
        )
        var renamedGroup = firstGroup
        renamedGroup.name = "Development"
        let edited = LayoutLibrary(
            customLayouts: [layout],
            customGroups: [secondGroup, renamedGroup]
        )

        let originalFillIDs = Set(
            ShortcutActionCatalog.descriptors(for: original)
                .filter { $0.category == .fillTargetDisplay }
                .map(\.id)
        )
        let editedFillIDs = Set(
            ShortcutActionCatalog.descriptors(for: edited)
                .filter { $0.category == .fillTargetDisplay }
                .map(\.id)
        )

        #expect(originalFillIDs == editedFillIDs)
        #expect(originalFillIDs.contains(firstGroup.fillShortcutActionID))
        #expect(originalFillIDs.contains(secondGroup.fillShortcutActionID))
        #expect(originalFillIDs.contains(ShortcutActionID(
            rawValue: "fill.builtin.horizontal-halves"
        )))
    }

    @Test func experimentalSpaceActionsHaveStableIDs() {
        let descriptors = ShortcutActionCatalog.descriptors(for: LayoutLibrary())
            .filter { $0.category == .experimentalSpaceMovement }

        #expect(descriptors.map(\.id.rawValue) == ["space.previous", "space.next"])
        #expect(descriptors.map(\.command) == [
            .moveToSpace(.previous),
            .moveToSpace(.next),
        ])
    }
}

struct ShortcutKeyLabelTests {
    @Test func labelsArrowAndCharacterKeys() {
        #expect(ShortcutKeyLabel.label(keyCode: 123, characters: nil) == "←")
        #expect(ShortcutKeyLabel.label(keyCode: 0, characters: "a") == "A")
    }
}
