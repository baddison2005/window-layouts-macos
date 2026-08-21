// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation
import OSLog

nonisolated enum ExternalApplicationTracking {
    static func updatedProcessIdentifier(
        current: pid_t?,
        candidate: pid_t?,
        own: pid_t
    ) -> pid_t? {
        guard let candidate, candidate > 0, candidate != own else {
            return current
        }
        return candidate
    }
}

@MainActor
final class DockIntegrationController: ObservableObject {
    private enum DockCommand {
        case window(WindowAction)
        case fillScreen(WindowFillGroup)
        case configure
        case disableOptionalOverlays
    }

    private let settingsStore: SettingsStore
    private let windowController: WindowLayoutsController
    private let workspace: NSWorkspace
    private let ownProcessIdentifier: pid_t
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObserver: NSObjectProtocol?
    private var commands: [Int: DockCommand] = [:]
    private var nextCommandTag = 1
    private var lastExternalProcessIdentifier: pid_t?
    @Published private(set) var targetApplicationName: String?
    private var openSettingsAction: (() -> Void)?

    init(
        settingsStore: SettingsStore,
        windowController: WindowLayoutsController,
        workspace: NSWorkspace = .shared,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.settingsStore = settingsStore
        self.windowController = windowController
        self.workspace = workspace
        self.ownProcessIdentifier = ownProcessIdentifier

        refreshTargetApplication()
        workspaceObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.recordExternalApplication(application)
            }
        }

        settingsStore.$library
            .map(\.showDockIcon)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isVisible in
                self?.applyActivationPolicy(showDockIcon: isVisible)
            }
            .store(in: &cancellables)
    }

    deinit {
        if let workspaceObserver {
            workspace.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func makeDockMenu() -> NSMenu? {
        guard settingsStore.library.showDockIcon else { return nil }

        refreshTargetApplication()
        windowController.refreshEnvironment()
        commands.removeAll()
        nextCommandTag = 1

        let menu = NSMenu(title: String(localized: "Window Layouts"))
        menu.autoenablesItems = false

        let targetName = targetApplicationName ?? String(localized: "No eligible app")
        let targetItem = NSMenuItem(
            title: String(localized: "Apply to: \(targetName)"),
            action: nil,
            keyEquivalent: ""
        )
        targetItem.isEnabled = false
        menu.addItem(targetItem)
        menu.addItem(.separator())

        for group in settingsStore.library.orderedMenuGroups {
            menu.addItem(menuItem(for: group))
        }
        menu.addItem(fillScreenMenuItem())

        menu.addItem(.separator())
        menu.addItem(commandItem(
            title: String(localized: "Configure Window Layouts…"),
            command: .configure,
            enabled: openSettingsAction != nil
        ))
        menu.addItem(commandItem(
            title: String(localized: "Disable Optional Overlays"),
            command: .disableOptionalOverlays,
            enabled: true
        ))
        return menu
    }

    func applicationDidFinishLaunching() {
        guard settingsStore.library.showDockIcon else { return }
        applyActivationPolicy(showDockIcon: true)
    }

    var targetProcessIdentifier: pid_t? {
        guard let processIdentifier = lastExternalProcessIdentifier,
              let application = NSRunningApplication(
                processIdentifier: processIdentifier
              ),
              !application.isTerminated else {
            return nil
        }
        return processIdentifier
    }

    func installOpenSettingsAction(_ action: @escaping () -> Void) {
        openSettingsAction = action
    }

    func refreshTargetApplication() {
        recordExternalApplication(workspace.frontmostApplication)
        if targetProcessIdentifier == nil {
            lastExternalProcessIdentifier = nil
            targetApplicationName = nil
        }
    }

    private var windowActionsEnabled: Bool {
        targetProcessIdentifier != nil
            && windowController.hasAccessibilityAccess
            && !windowController.isPerformingAction
    }

    private func recordExternalApplication(_ application: NSRunningApplication?) {
        let previous = lastExternalProcessIdentifier
        lastExternalProcessIdentifier = ExternalApplicationTracking
            .updatedProcessIdentifier(
                current: previous,
                candidate: application?.processIdentifier,
                own: ownProcessIdentifier
            )
        if lastExternalProcessIdentifier != previous,
           application?.processIdentifier == lastExternalProcessIdentifier {
            targetApplicationName = application?.localizedName
        } else if targetApplicationName == nil,
                  application?.processIdentifier == lastExternalProcessIdentifier {
            targetApplicationName = application?.localizedName
        }
    }

    private func applyActivationPolicy(showDockIcon: Bool) {
        if showDockIcon {
            installWindowLayoutsDockIcon()
        }

        let desiredPolicy: NSApplication.ActivationPolicy = showDockIcon
            ? .regular
            : .accessory
        guard NSApp.activationPolicy() != desiredPolicy else { return }
        _ = NSApp.setActivationPolicy(desiredPolicy)
    }

    private func installWindowLayoutsDockIcon() {
        let packagedIcon = Bundle.main
            .url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
        guard let sourceImage = packagedIcon ?? NSImage(named: "MenuBarIcon"),
              let icon = sourceImage.copy() as? NSImage else {
            AppDiagnostics.lifecycle.error(
                "The Window Layouts Dock icon resource could not be loaded."
            )
            return
        }

        icon.isTemplate = false
        NSApp.applicationIconImage = icon
        NSApp.dockTile.display()
    }

    private func menuItem(for group: MenuGroupIdentifier) -> NSMenuItem {
        let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: group.name)
        submenu.autoenablesItems = false

        switch group {
        case .halves, .quarters, .thirds, .twoThirds:
            for layout in group.fixedLayouts {
                submenu.addItem(commandItem(
                    title: layout.name,
                    command: .window(.fixed(layout)),
                    enabled: windowActionsEnabled
                ))
            }
        case .custom:
            populateCustomLayouts(in: submenu)
        case .window:
            populateWindowActions(in: submenu)
        }

        item.submenu = submenu
        return item
    }

    private func populateCustomLayouts(in menu: NSMenu) {
        let library = settingsStore.library
        guard !library.customLayouts.isEmpty else {
            let empty = NSMenuItem(
                title: String(localized: "No Custom Layouts"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for group in library.customGroups {
            let layouts = library.customLayouts.filter { $0.groupID == group.id }
            guard !layouts.isEmpty else { continue }
            let groupItem = NSMenuItem(
                title: group.name,
                action: nil,
                keyEquivalent: ""
            )
            let groupMenu = NSMenu(title: group.name)
            groupMenu.autoenablesItems = false
            for layout in layouts {
                groupMenu.addItem(customLayoutItem(layout))
            }
            groupItem.submenu = groupMenu
            menu.addItem(groupItem)
        }

        let unassigned = library.customLayouts.filter { $0.groupID == nil }
        if !unassigned.isEmpty {
            let unassignedItem = NSMenuItem(
                title: String(localized: "Unassigned"),
                action: nil,
                keyEquivalent: ""
            )
            let unassignedMenu = NSMenu(title: String(localized: "Unassigned"))
            unassignedMenu.autoenablesItems = false
            for layout in unassigned {
                unassignedMenu.addItem(customLayoutItem(layout))
            }
            unassignedItem.submenu = unassignedMenu
            menu.addItem(unassignedItem)
        }
    }

    private func customLayoutItem(_ layout: LayoutDefinition) -> NSMenuItem {
        commandItem(
            title: layout.name,
            command: .window(.custom(layout)),
            enabled: windowActionsEnabled
        )
    }

    private func populateWindowActions(in menu: NSMenu) {
        menu.addItem(commandItem(
            title: String(localized: "Center"),
            command: .window(.center),
            enabled: windowActionsEnabled
        ))
        menu.addItem(commandItem(
            title: String(localized: "Maximize"),
            command: .window(.maximize),
            enabled: windowActionsEnabled
        ))
        menu.addItem(commandItem(
            title: String(localized: "Restore"),
            command: .window(.restore),
            enabled: windowActionsEnabled
        ))
        menu.addItem(.separator())

        let monitorActionsEnabled = windowActionsEnabled
            && windowController.monitorCount > 1
        menu.addItem(commandItem(
            title: String(localized: "Move to Previous Monitor"),
            command: .window(.moveToPreviousMonitor),
            enabled: monitorActionsEnabled
        ))
        menu.addItem(commandItem(
            title: String(localized: "Move to Next Monitor"),
            command: .window(.moveToNextMonitor),
            enabled: monitorActionsEnabled
        ))
    }

    private func fillScreenMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Fill Target Display"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: String(localized: "Fill Target Display"))
        submenu.autoenablesItems = false
        for group in WindowFillGroupCatalog.groups(for: settingsStore.library) {
            submenu.addItem(commandItem(
                title: group.name,
                command: .fillScreen(group),
                enabled: windowActionsEnabled
            ))
        }
        item.submenu = submenu
        return item
    }

    private func commandItem(
        title: String,
        command: DockCommand,
        enabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(performCommand(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = nextCommandTag
        item.isEnabled = enabled
        commands[nextCommandTag] = command
        nextCommandTag += 1
        return item
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = commands[sender.tag] else { return }
        switch command {
        case .window(let action):
            guard let processIdentifier = targetProcessIdentifier else {
                return
            }
            windowController.perform(
                action,
                targetingProcessIdentifier: processIdentifier
            )
        case .fillScreen(let group):
            guard let processIdentifier = targetProcessIdentifier else {
                return
            }
            windowController.fillScreen(
                using: group,
                targetingProcessIdentifier: processIdentifier
            )
        case .configure:
            openSettingsAction?()
        case .disableOptionalOverlays:
            windowController.disableOptionalOverlays()
        }
    }
}

@MainActor
final class WindowLayoutsAppDelegate: NSObject, NSApplicationDelegate {
    static weak var dockIntegrationController: DockIntegrationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.dockIntegrationController?.applicationDidFinishLaunching()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        Self.dockIntegrationController?.makeDockMenu()
    }
}
