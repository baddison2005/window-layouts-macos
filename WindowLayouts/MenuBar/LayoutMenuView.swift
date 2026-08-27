// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct LayoutMenuView: View {
    @ObservedObject var controller: WindowLayoutsController
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var targetController: DockIntegrationController

    private var actionsDisabled: Bool {
        targetController.targetProcessIdentifier == nil
            || !controller.hasAccessibilityAccess
            || controller.isPerformingAction
    }

    private var monitorActionsDisabled: Bool {
        actionsDisabled || controller.monitorCount < 2
    }

    private var spaceActionsDisabled: Bool {
        actionsDisabled
            || !controller.hasPostEventAccess
            || !settingsStore.library.experimentalSpaceMovementEnabled
            || !settingsStore.library.missionControlSpaceShortcutsConfirmed
    }

    var body: some View {
        Text(
            targetController.targetApplicationName.map { "Apply to: \($0)" }
                ?? "No eligible app"
        )
        Divider()

        if !controller.hasAccessibilityAccess {
            Text("Accessibility access is required")
            Button("Grant Accessibility Access…") {
                controller.requestAccessibilityAccess()
            }
            Button("Check Again") {
                controller.refreshAccessibilityAccess()
            }
            Divider()
        }

        ForEach(settingsStore.library.orderedMenuGroups) { group in
            menuSection(group)
        }

        Menu("Fill Target Display") {
            ForEach(WindowFillGroupCatalog.groups(for: settingsStore.library)) { group in
                Button(group.name) {
                    fillScreen(using: group)
                }
                .disabled(actionsDisabled)
            }
        }
        .disabled(actionsDisabled)

        if let statusMessage = controller.statusMessage {
            Divider()
            Text(statusMessage)
        }

        Divider()

        // This remains available even when Accessibility is denied or an
        // optional panel fails in a future phase.
        Button("Disable Optional Overlays") {
            controller.disableOptionalOverlays()
        }

        SettingsLink {
            Text("Configure Window Layouts Experimental…")
        }

        Button("Quit Window Layouts Experimental") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onAppear {
            targetController.refreshTargetApplication()
            controller.refreshEnvironment()
        }
    }

    @ViewBuilder
    private func menuSection(_ group: MenuGroupIdentifier) -> some View {
        switch group {
        case .halves, .quarters, .thirds, .twoThirds:
            Section(group.name) {
                ForEach(group.fixedLayouts) { layout in
                    layoutButton(layout)
                }
            }
        case .custom:
            customLayoutsSection
        case .window:
            Section("Window") {
                Button("Center") {
                    perform(.center)
                }
                .disabled(actionsDisabled)

                Button("Maximize") {
                    perform(.maximize)
                }
                .disabled(actionsDisabled)

                Button("Restore") {
                    perform(.restore)
                }
                .disabled(actionsDisabled)

                Divider()

                Button("Move to Previous Monitor") {
                    perform(.moveToPreviousMonitor)
                }
                .disabled(monitorActionsDisabled)

                Button("Move to Next Monitor") {
                    perform(.moveToNextMonitor)
                }
                .disabled(monitorActionsDisabled)

                Divider()

                Button("Move Window to Previous Space") {
                    moveWindowToSpace(.previous)
                }
                .disabled(spaceActionsDisabled)

                Button("Move Window to Next Space") {
                    moveWindowToSpace(.next)
                }
                .disabled(spaceActionsDisabled)
            }
        }
    }

    @ViewBuilder
    private var customLayoutsSection: some View {
        let library = settingsStore.library
        Section("Custom") {
            if library.customLayouts.isEmpty {
                Text("No Custom Layouts")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.customGroups) { group in
                    let layouts = library.customLayouts.filter { $0.groupID == group.id }
                    if !layouts.isEmpty {
                        Menu(group.name) {
                            ForEach(layouts) { layout in
                                customLayoutButton(layout)
                            }
                        }
                    }
                }

                let unassigned = library.customLayouts.filter { $0.groupID == nil }
                if !unassigned.isEmpty {
                    Menu("Unassigned") {
                        ForEach(unassigned) { layout in
                            customLayoutButton(layout)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func layoutButton(_ layout: FixedLayout) -> some View {
        Button(layout.name) {
            perform(.fixed(layout))
        }
        .disabled(actionsDisabled)
    }

    @ViewBuilder
    private func customLayoutButton(_ layout: LayoutDefinition) -> some View {
        Button(layout.name) {
            perform(.custom(layout))
        }
        .disabled(actionsDisabled)
    }

    private func perform(_ action: WindowAction) {
        guard let processIdentifier = targetController.targetProcessIdentifier else {
            return
        }
        controller.perform(
            action,
            targetingProcessIdentifier: processIdentifier
        )
    }

    private func fillScreen(using group: WindowFillGroup) {
        guard let processIdentifier = targetController.targetProcessIdentifier else {
            return
        }
        controller.fillScreen(
            using: group,
            targetingProcessIdentifier: processIdentifier
        )
    }

    private func moveWindowToSpace(_ direction: SpaceMovementDirection) {
        guard let processIdentifier = targetController.targetProcessIdentifier else {
            return
        }
        controller.moveWindowToSpace(
            direction,
            targetingProcessIdentifier: processIdentifier
        )
    }
}
