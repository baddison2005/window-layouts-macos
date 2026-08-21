// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated struct KeyboardShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let command = KeyboardShortcutModifiers(rawValue: 1 << 0)
    static let option = KeyboardShortcutModifiers(rawValue: 1 << 1)
    static let control = KeyboardShortcutModifiers(rawValue: 1 << 2)
    static let shift = KeyboardShortcutModifiers(rawValue: 1 << 3)

    static let supported: KeyboardShortcutModifiers = [
        .command,
        .option,
        .control,
        .shift,
    ]

    var containsPrimaryModifier: Bool {
        !intersection([.command, .option, .control]).isEmpty
    }
}

nonisolated enum KeyboardShortcutValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedModifier
    case primaryModifierRequired
    case invalidKeyCode
    case missingKeyLabel

    var errorDescription: String? {
        switch self {
        case .unsupportedModifier:
            String(localized: "The shortcut contains an unsupported modifier.")
        case .primaryModifierRequired:
            String(localized: "Use at least one of Command, Option, or Control.")
        case .invalidKeyCode:
            String(localized: "The shortcut key code is invalid.")
        case .missingKeyLabel:
            String(localized: "The shortcut key could not be identified.")
        }
    }
}

nonisolated struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: KeyboardShortcutModifiers
    var keyLabel: String

    init(keyCode: UInt32, modifiers: KeyboardShortcutModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    var displayName: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    var identity: KeyboardShortcutIdentity {
        KeyboardShortcutIdentity(keyCode: keyCode, modifiers: modifiers)
    }

    func validated() throws -> KeyboardShortcut {
        guard modifiers.subtracting(.supported).isEmpty else {
            throw KeyboardShortcutValidationError.unsupportedModifier
        }
        guard modifiers.containsPrimaryModifier else {
            throw KeyboardShortcutValidationError.primaryModifierRequired
        }
        guard keyCode <= UInt32(UInt16.max) else {
            throw KeyboardShortcutValidationError.invalidKeyCode
        }
        let label = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            throw KeyboardShortcutValidationError.missingKeyLabel
        }
        var result = self
        result.keyLabel = String(label.prefix(12))
        return result
    }
}

nonisolated struct KeyboardShortcutIdentity: Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: KeyboardShortcutModifiers
}
