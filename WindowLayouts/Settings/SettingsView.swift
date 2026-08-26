// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: WindowLayoutsController
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var shortcutManager: GlobalShortcutManager
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @StateObject private var draft: SettingsDraft
    @StateObject private var updateController = AppUpdateController()
    @State private var statusMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(
        controller: WindowLayoutsController,
        settingsStore: SettingsStore,
        shortcutManager: GlobalShortcutManager,
        launchAtLoginManager: LaunchAtLoginManager
    ) {
        self.controller = controller
        self.settingsStore = settingsStore
        self.shortcutManager = shortcutManager
        self.launchAtLoginManager = launchAtLoginManager
        _draft = StateObject(wrappedValue: SettingsDraft(library: settingsStore.library))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let warning = settingsStore.loadWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top)
            }

            TabView {
                LayoutsSettingsView(library: $draft.library)
                    .tabItem {
                        Label("Layouts", systemImage: "rectangle.3.group")
                    }

                GroupsSettingsView(library: $draft.library)
                    .tabItem {
                        Label("Groups", systemImage: "list.bullet.indent")
                    }

                ShortcutsSettingsView(
                    library: $draft.library,
                    shortcutManager: shortcutManager
                )
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }

                GeneralSettingsView(
                    library: $draft.library,
                    controller: controller,
                    launchAtLoginManager: launchAtLoginManager
                )
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

                AboutSettingsView(updateController: updateController)
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .padding()

            Divider()

            HStack {
                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    draft.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    applyChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.hasChanges)
            }
            .padding()
        }
        .frame(minWidth: 920, idealWidth: 980, minHeight: 680, idealHeight: 740)
        .onAppear {
            draft.reset(from: settingsStore.library)
            controller.refreshEnvironment()
        }
        .onDisappear {
            draft.cancel()
        }
    }

    private func applyChanges() {
        do {
            try settingsStore.apply(draft.library)
            draft.markApplied(settingsStore.library)
            statusMessage = String(localized: "Settings saved.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
