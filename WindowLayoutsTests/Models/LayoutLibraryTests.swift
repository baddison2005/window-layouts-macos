// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

struct LayoutLibraryTests {
    private let half = try! NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)

    @Test func safeDefaultsAreEmptyAndComplete() throws {
        let library = try LayoutLibrary().validated()

        #expect(library.schemaVersion == LayoutLibrary.currentSchemaVersion)
        #expect(library.customLayouts.isEmpty)
        #expect(library.customGroups.isEmpty)
        #expect(library.layoutPadding == 0)
        #expect(!library.showDockIcon)
        #expect(!library.greenButtonPanelEnabled)
        #expect(library.layoutPanelSize == .standard)
        #expect(!library.dragTargetsEnabled)
        #expect(library.dragTargetPlacement == .zones)
        #expect(!library.showAllDragTargets)
        #expect(!library.showAllTopDragTargets)
        #expect(library.orderedMenuGroups == MenuGroupIdentifier.allCases)
    }

    @Test func flattenedLayoutGeometryRoundTrips() throws {
        let group = LayoutGroup(name: "Writing")
        let layout = LayoutDefinition(
            name: "Notes",
            normalizedRect: half,
            groupID: group.id
        )
        let original = LayoutLibrary(
            customLayouts: [layout],
            customGroups: [group],
            layoutPadding: 12
        )

        let data = try JSONEncoder().encode(original)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""width":0.5"#))
        #expect(!json.contains("normalizedRect"))
        #expect(try JSONDecoder().decode(LayoutLibrary.self, from: data).validated() == original)
    }

    @Test func validationCanonicalizesNamesAndPadding() throws {
        let library = LayoutLibrary(
            customLayouts: [LayoutDefinition(name: "  Focus  ", normalizedRect: half)],
            customGroups: [LayoutGroup(name: "  Work  ")],
            layoutPadding: 11.6
        )
        let validated = try library.validated()

        #expect(validated.customLayouts[0].name == "Focus")
        #expect(validated.customGroups[0].name == "Work")
        #expect(validated.layoutPadding == 12)
    }

    @Test func validationRejectsTooManyOrDuplicateLayouts() {
        let duplicateID = UUID()
        let duplicates = LayoutLibrary(customLayouts: [
            LayoutDefinition(id: duplicateID, name: "One", normalizedRect: half),
            LayoutDefinition(id: duplicateID, name: "Two", normalizedRect: half),
        ])
        #expect(throws: LayoutLibraryValidationError.duplicateLayoutID) {
            try duplicates.validated()
        }

        let tooMany = LayoutLibrary(customLayouts: (0...20).map {
            LayoutDefinition(name: "Layout \($0)", normalizedRect: half)
        })
        #expect(throws: LayoutLibraryValidationError.tooManyLayouts(21)) {
            try tooMany.validated()
        }
    }

    @Test func validationRejectsBrokenReferencesAndOrdering() {
        let brokenReference = LayoutLibrary(customLayouts: [
            LayoutDefinition(
                name: "Orphan",
                normalizedRect: half,
                groupID: UUID()
            ),
        ])
        #expect(throws: LayoutLibraryValidationError.invalidGroupReference) {
            try brokenReference.validated()
        }

        let brokenOrder = LayoutLibrary(menuGroupOrder: ["halves", "window"])
        #expect(throws: LayoutLibraryValidationError.invalidMenuGroupOrder) {
            try brokenOrder.validated()
        }

        let invalidPadding = LayoutLibrary(layoutPadding: 201)
        #expect(throws: LayoutLibraryValidationError.invalidPadding) {
            try invalidPadding.validated()
        }
    }

    @Test func decodingRejectsInvalidCustomGeometry() {
        let data = Data(
            #"{"schemaVersion":1,"customLayouts":[{"id":"00000000-0000-0000-0000-000000000001","name":"Bad","x":0,"y":0,"width":2,"height":1}],"customGroups":[],"menuGroupOrder":["halves","quarters","thirds","twoThirds","custom","window"],"layoutPadding":0}"#.utf8
        )
        #expect(throws: Error.self) {
            try JSONDecoder().decode(LayoutLibrary.self, from: data)
        }
    }

    @Test func versionOneMigratesWithSafeCurrentDefaults() throws {
        let data = Data(
            #"{"schemaVersion":1,"customLayouts":[],"customGroups":[],"menuGroupOrder":["halves","quarters","thirds","twoThirds","custom","window"],"layoutPadding":8}"#.utf8
        )

        let library = try JSONDecoder().decode(LayoutLibrary.self, from: data).validated()

        #expect(library.schemaVersion == LayoutLibrary.currentSchemaVersion)
        #expect(library.shortcuts.isEmpty)
        #expect(!library.launchAtLogin)
        #expect(!library.showDockIcon)
        #expect(!library.greenButtonPanelEnabled)
        #expect(library.layoutPanelSize == .standard)
        #expect(!library.dragTargetsEnabled)
        #expect(library.dragTargetPlacement == .zones)
        #expect(library.layoutPadding == 8)
    }

    @Test func shortcutValidationUsesKeyAndModifiersForDuplicateIdentity() {
        let duplicate = LayoutLibrary(shortcuts: [
            "fixed.leftHalf": KeyboardShortcut(
                keyCode: 123,
                modifiers: [.control, .option],
                keyLabel: "Left"
            ),
            "fixed.rightHalf": KeyboardShortcut(
                keyCode: 123,
                modifiers: [.control, .option],
                keyLabel: "Different label"
            ),
        ])

        #expect(throws: LayoutLibraryValidationError.duplicateShortcut) {
            try duplicate.validated()
        }
    }

    @Test func shortcutValidationRejectsUnknownActions() {
        let library = LayoutLibrary(shortcuts: [
            "unknown.action": KeyboardShortcut(
                keyCode: 0,
                modifiers: [.command],
                keyLabel: "A"
            ),
        ])

        #expect(throws: LayoutLibraryValidationError.invalidShortcutAction) {
            try library.validated()
        }
    }

    @Test func shortcutValidationAcceptsCustomFillGroupAction() throws {
        let group = LayoutGroup(name: "Writing")
        let shortcut = KeyboardShortcut(
            keyCode: 17,
            modifiers: [.control, .option],
            keyLabel: "T"
        )
        let library = LayoutLibrary(
            customGroups: [group],
            shortcuts: [group.fillShortcutActionID.rawValue: shortcut]
        )

        let validated = try library.validated()

        #expect(validated.shortcuts[group.fillShortcutActionID.rawValue] == shortcut)
    }
}
