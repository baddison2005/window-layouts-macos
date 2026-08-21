// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ShortcutsSettingsView: View {
    @Binding var library: LayoutLibrary
    @ObservedObject var shortcutManager: GlobalShortcutManager
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section {
                Text(
                    "Choose Record Shortcut, then type a key combination. Use at least one of Command, Option, or Control. Press Delete to clear or Escape to cancel recording."
                )
                .foregroundStyle(.secondary)
            }

            ForEach(ShortcutActionCategory.allCases) { category in
                let descriptors = ShortcutActionCatalog.descriptors(for: library)
                    .filter { $0.category == category }
                if !descriptors.isEmpty {
                    Section(category.name) {
                        ForEach(descriptors) { descriptor in
                            HStack {
                                Text(descriptor.label)
                                Spacer()
                                ShortcutRecorder(
                                    shortcut: library.shortcuts[descriptor.id.rawValue],
                                    onChange: { shortcut in
                                        update(shortcut, for: descriptor)
                                    },
                                    onError: { validationMessage = $0 }
                                )
                            }
                        }
                    }
                }
            }

            if let validationMessage {
                Section("Shortcut issue") {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if !shortcutManager.registrationFailures.isEmpty {
                Section("Registration failures") {
                    ForEach(shortcutManager.registrationFailures) { failure in
                        let label = ShortcutActionCatalog.descriptor(
                            for: failure.actionID,
                            in: library
                        )?.label ?? failure.actionID.rawValue
                        Text("\(label): \(failure.message)")
                    }
                    Button("Retry Saved Shortcuts") {
                        shortcutManager.retry()
                    }
                }
            }

            Section("macOS limitation") {
                Text(
                    "Shortcuts are registered non-exclusively. Window Layouts prevents duplicates within its own settings, but macOS does not provide a complete public registry of shortcuts used by other apps. If another app uses the same combination, both apps may respond."
                )
                .foregroundStyle(.secondary)
                Text("Shortcut changes take effect after you choose Apply.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func update(
        _ shortcut: KeyboardShortcut?,
        for descriptor: ShortcutActionDescriptor
    ) -> Bool {
        guard let shortcut else {
            library.shortcuts.removeValue(forKey: descriptor.id.rawValue)
            validationMessage = nil
            return true
        }

        if let conflictID = ShortcutActionCatalog.conflictingActionID(
            for: shortcut,
            excluding: descriptor.id,
            in: library
        ) {
            let conflictLabel = ShortcutActionCatalog.descriptor(
                for: conflictID,
                in: library
            )?.label ?? conflictID.rawValue
            validationMessage = "\(shortcut.displayName) is already assigned to \(conflictLabel)."
            return false
        }

        library.shortcuts[descriptor.id.rawValue] = shortcut
        validationMessage = nil
        return true
    }
}
