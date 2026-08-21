// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct GeneralSettingsView: View {
    @Binding var library: LayoutLibrary
    @ObservedObject var controller: WindowLayoutsController
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        Form {
            Section("Layout padding") {
                Stepper(
                    "\(Int(library.layoutPadding.rounded())) logical points",
                    value: $library.layoutPadding,
                    in: 0...Double(LayoutEngine.maximumPadding),
                    step: 1
                )
                Text(
                    "Padding is applied only to internal layout edges; display edges remain flush."
                )
                .foregroundStyle(.secondary)
            }

            Section("Green button layout panel") {
                Toggle(
                    "Show layouts when hovering over a window’s green button",
                    isOn: $library.greenButtonPanelEnabled
                )

                Picker("Panel size", selection: $library.layoutPanelSize) {
                    ForEach(LayoutPanelSize.allCases) { size in
                        Text(size.name).tag(size)
                    }
                }
                .disabled(!library.greenButtonPanelEnabled)

                Text(
                    "Window Layouts uses the public Accessibility position of the green button to show a separate nonactivating panel. It does not modify or replace Apple’s built-in title-bar menu. Changes take effect after Apply."
                )
                .foregroundStyle(.secondary)
            }

            Section("Drag targets") {
                Toggle(
                    "Show layout targets while dragging a window",
                    isOn: $library.dragTargetsEnabled
                )

                Picker("Target placement", selection: $library.dragTargetPlacement) {
                    ForEach(DragTargetPlacementStyle.allCases) { style in
                        Text(style.name).tag(style)
                    }
                }
                .disabled(!library.dragTargetsEnabled)

                if library.dragTargetPlacement == .zones {
                    Toggle(
                        "Display zone targets immediately",
                        isOn: $library.showAllDragTargets
                    )
                    .disabled(!library.dragTargetsEnabled)
                } else {
                    Toggle(
                        "Display the top-center strip immediately",
                        isOn: $library.showAllTopDragTargets
                    )
                    .disabled(!library.dragTargetsEnabled)
                }

                Text(
                    "Targets and previews are separate, nonactivating panels that always ignore mouse events. Window Layouts observes the pointer and applies a hovered layout only after the drag ends. Changes take effect after Apply."
                )
                .foregroundStyle(.secondary)

                Text(
                    "If drag events are not detected on this Mac, allow Window Layouts under System Settings → Privacy & Security → Input Monitoring, then relaunch it. Window Layouts never synthesizes or modifies input events."
                )
                .foregroundStyle(.secondary)
            }

            Section("Accessibility") {
                Text(
                    "Window Layouts uses the public macOS Accessibility API to find, move, and resize the focused window. It never bypasses macOS privacy controls."
                )

                LabeledContent("Status") {
                    Text(controller.hasAccessibilityAccess ? "Enabled" : "Required")
                        .foregroundStyle(
                            controller.hasAccessibilityAccess ? .green : .secondary
                        )
                }

                HStack {
                    if !controller.hasAccessibilityAccess {
                        Button("Grant Accessibility Access…") {
                            controller.requestAccessibilityAccess()
                        }
                    }
                    Button("Check Again") {
                        controller.refreshAccessibilityAccess()
                    }
                }
            }

            Section("Launch at login") {
                Toggle(
                    "Open Window Layouts when I log in",
                    isOn: $library.launchAtLogin
                )

                LabeledContent("Current status") {
                    Text(launchAtLoginManager.state.label)
                }

                if let message = launchAtLoginManager.state.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                if launchAtLoginManager.state == .requiresApproval {
                    HStack {
                        Button("Open Login Items Settings…") {
                            launchAtLoginManager.openSystemSettings()
                        }
                        Button("Check Again") {
                            launchAtLoginManager.retry()
                        }
                    }
                }

                if case .failed = launchAtLoginManager.state {
                    Button("Retry") {
                        launchAtLoginManager.retry()
                    }
                }

                if launchAtLoginManager.state == .unavailable {
                    Button("Retry") {
                        launchAtLoginManager.retry()
                    }
                }

                Text(
                    "This change takes effect after you choose Apply. A build run directly from Xcode may have a temporary location; verify the setting again after installing the signed app in Applications."
                )
                .foregroundStyle(.secondary)
            }

            Section("Dock") {
                Toggle(
                    "Show Window Layouts in the Dock",
                    isOn: $library.showDockIcon
                )

                Text(
                    "Control-click or right-click the Dock icon to apply layouts to the last active third-party app. A normal click retains the standard macOS app-activation behavior. The menu-bar item remains available at all times. Changes take effect after Apply."
                )
                .foregroundStyle(.secondary)
            }

            Section("Overlay safety") {
                Text(
                    "The green-button panel is compact and accepts input only while visibly open. Every drag-target and preview panel always ignores mouse events. The menu-bar item is always the emergency disable path."
                )
                Button("Disable Optional Overlays") {
                    controller.disableOptionalOverlays()
                }
            }

            Section("Platform limits") {
                Text(
                    "Monitor movement uses public Accessibility and screen APIs. Moving third-party windows between Spaces is unavailable because macOS provides no public API for it."
                )
            }
        }
        .formStyle(.grouped)
    }
}
