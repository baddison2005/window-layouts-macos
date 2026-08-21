// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct GreenButtonLayoutPanelView: View {
    @ObservedObject var controller: WindowLayoutsController
    @ObservedObject var settingsStore: SettingsStore
    let perform: (WindowAction) -> Void
    let fillScreen: (WindowFillGroup) -> Void
    let close: () -> Void
    let disable: () -> Void

    private var actionsDisabled: Bool {
        !controller.hasAccessibilityAccess || controller.isPerformingAction
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image("MenuBarIconCompact")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text("Window Layouts")
                    .font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close Window Layouts panel")
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(settingsStore.library.orderedMenuGroups) { group in
                        panelSection(group)
                    }

                    panelHeading("Fill Target Display")
                    ForEach(
                        WindowFillGroupCatalog.groups(for: settingsStore.library)
                    ) { group in
                        Button {
                            fillScreen(group)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.2x2")
                                    .frame(width: 38, height: 24)
                                    .accessibilityHidden(true)
                                Text(group.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(LayoutPanelRowButtonStyle())
                        .disabled(actionsDisabled)
                    }
                }
                .padding(.trailing, 4)
            }

            Divider()

            SettingsLink {
                Label("Configure Window Layouts…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: disable) {
                Label("Disable Green Button Panel", systemImage: "eye.slash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func panelSection(_ group: MenuGroupIdentifier) -> some View {
        switch group {
        case .halves, .quarters, .thirds, .twoThirds:
            panelHeading(group.name)
            ForEach(group.fixedLayouts) { layout in
                panelButton(
                    label: layout.name,
                    normalizedRect: layout.normalizedRect,
                    action: .fixed(layout)
                )
            }
        case .custom:
            customSections
        case .window:
            windowSection
        }
    }

    @ViewBuilder
    private var customSections: some View {
        let library = settingsStore.library
        if !library.customLayouts.isEmpty {
            panelHeading("Custom")
            ForEach(library.customGroups) { group in
                let layouts = library.customLayouts.filter { $0.groupID == group.id }
                if !layouts.isEmpty {
                    Text(group.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                    ForEach(layouts) { layout in
                        panelButton(
                            label: layout.name,
                            normalizedRect: layout.normalizedRect,
                            action: .custom(layout)
                        )
                    }
                }
            }

            let unassigned = library.customLayouts.filter { $0.groupID == nil }
            if !unassigned.isEmpty {
                Text("Unassigned")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                ForEach(unassigned) { layout in
                    panelButton(
                        label: layout.name,
                        normalizedRect: layout.normalizedRect,
                        action: .custom(layout)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var windowSection: some View {
        panelHeading("Window")
        panelButton(label: "Center", systemImage: "align.horizontal.center", action: .center)
        panelButton(label: "Maximize", systemImage: "arrow.up.left.and.arrow.down.right", action: .maximize)
        panelButton(label: "Restore", systemImage: "arrow.uturn.backward", action: .restore)
        panelButton(
            label: "Move to Previous Monitor",
            systemImage: "arrow.backward.to.line",
            action: .moveToPreviousMonitor,
            disabled: controller.monitorCount < 2
        )
        panelButton(
            label: "Move to Next Monitor",
            systemImage: "arrow.forward.to.line",
            action: .moveToNextMonitor,
            disabled: controller.monitorCount < 2
        )
    }

    private func panelHeading(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(.tint)
            .padding(.top, 6)
    }

    private func panelButton(
        label: String,
        normalizedRect: NormalizedRect,
        action: WindowAction
    ) -> some View {
        Button {
            perform(action)
        } label: {
            HStack(spacing: 10) {
                LayoutPanelPreview(normalizedRect: normalizedRect)
                    .accessibilityHidden(true)
                Text(label)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LayoutPanelRowButtonStyle())
        .disabled(actionsDisabled)
    }

    private func panelButton(
        label: String,
        systemImage: String,
        action: WindowAction,
        disabled: Bool = false
    ) -> some View {
        Button {
            perform(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 38, height: 24)
                    .accessibilityHidden(true)
                Text(label)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LayoutPanelRowButtonStyle())
        .disabled(actionsDisabled || disabled)
    }
}

private struct LayoutPanelPreview: View {
    let normalizedRect: NormalizedRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(.secondary, lineWidth: 1)
            RoundedRectangle(cornerRadius: 1)
                .fill(.purple.opacity(0.8))
                .frame(
                    width: max(1, 38 * normalizedRect.width),
                    height: max(1, 24 * normalizedRect.height)
                )
                .offset(
                    x: 38 * normalizedRect.x,
                    y: 24 * normalizedRect.y
                )
        }
        .frame(width: 38, height: 24)
    }
}

private struct LayoutPanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LayoutPanelRowButtonBody(configuration: configuration)
    }
}

private struct LayoutPanelRowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var isHighlighted: Bool {
        isEnabled && (isHovered || configuration.isPressed)
    }

    var body: some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .foregroundStyle(isHighlighted ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isHighlighted
                            ? Color.accentColor
                            : Color.primary.opacity(0.001)
                    )
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onHover { isHovered = $0 }
    }
}
