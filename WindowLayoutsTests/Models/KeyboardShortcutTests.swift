// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import WindowLayouts

struct KeyboardShortcutTests {
    @Test func displayNameUsesMacModifierOrder() {
        let shortcut = KeyboardShortcut(
            keyCode: 2,
            modifiers: [.command, .option, .control, .shift],
            keyLabel: "D"
        )

        #expect(shortcut.displayName == "⌃⌥⇧⌘D")
    }

    @Test func shortcutNeedsPrimaryModifier() {
        let shortcut = KeyboardShortcut(
            keyCode: 2,
            modifiers: [.shift],
            keyLabel: "D"
        )

        #expect(throws: KeyboardShortcutValidationError.primaryModifierRequired) {
            try shortcut.validated()
        }
    }

    @Test func identityIgnoresPresentationLabel() {
        let first = KeyboardShortcut(keyCode: 123, modifiers: [.control], keyLabel: "Left")
        let second = KeyboardShortcut(keyCode: 123, modifiers: [.control], keyLabel: "←")

        #expect(first.identity == second.identity)
    }

    @Test func detectsExactMissionControlSpaceNavigationShortcuts() {
        #expect(KeyboardShortcut(
            keyCode: 123,
            modifiers: [.control],
            keyLabel: "←"
        ).isMissionControlSpaceNavigationShortcut)
        #expect(KeyboardShortcut(
            keyCode: 124,
            modifiers: [.control],
            keyLabel: "→"
        ).isMissionControlSpaceNavigationShortcut)
        #expect(!KeyboardShortcut(
            keyCode: 124,
            modifiers: [.control, .option],
            keyLabel: "→"
        ).isMissionControlSpaceNavigationShortcut)
    }
}
