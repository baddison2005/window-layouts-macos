// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct WindowLayoutsApp: App {
    @NSApplicationDelegateAdaptor(WindowLayoutsAppDelegate.self)
    private var appDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var controller: WindowLayoutsController
    @StateObject private var shortcutManager: GlobalShortcutManager
    @StateObject private var launchAtLoginManager: LaunchAtLoginManager
    @StateObject private var greenButtonPanelController: GreenButtonPanelController
    @StateObject private var dragTargetController: DragTargetController
    @StateObject private var dockIntegrationController: DockIntegrationController
    @Environment(\.openSettings) private var openSettings

    init() {
        let settingsStore = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        let controller = WindowLayoutsController(settingsStore: settingsStore)
        _controller = StateObject(wrappedValue: controller)
        _shortcutManager = StateObject(
            wrappedValue: GlobalShortcutManager(
                settingsStore: settingsStore,
                controller: controller
            )
        )
        _launchAtLoginManager = StateObject(
            wrappedValue: LaunchAtLoginManager(settingsStore: settingsStore)
        )
        _greenButtonPanelController = StateObject(
            wrappedValue: GreenButtonPanelController(
                settingsStore: settingsStore,
                windowController: controller
            )
        )
        _dragTargetController = StateObject(
            wrappedValue: DragTargetController(
                settingsStore: settingsStore,
                windowController: controller
            )
        )
        let dockIntegrationController = DockIntegrationController(
            settingsStore: settingsStore,
            windowController: controller
        )
        _dockIntegrationController = StateObject(
            wrappedValue: dockIntegrationController
        )
        WindowLayoutsAppDelegate.dockIntegrationController = dockIntegrationController
    }

    var body: some Scene {
        let _ = dockIntegrationController.installOpenSettingsAction {
            openSettings()
        }

        MenuBarExtra {
            LayoutMenuView(
                controller: controller,
                settingsStore: settingsStore,
                targetController: dockIntegrationController
            )
        } label: {
            Image("MenuBarIconCompact")
                .renderingMode(.original)
                .accessibilityLabel("Window Layouts")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                controller: controller,
                settingsStore: settingsStore,
                shortcutManager: shortcutManager,
                launchAtLoginManager: launchAtLoginManager
            )
        }
    }
}
