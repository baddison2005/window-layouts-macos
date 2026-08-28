// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LayoutsSettingsView: View {
    @Binding var library: LayoutLibrary
    @State private var selectedLayoutID: UUID?
    @State private var transferAlert: LayoutTransferAlert?
    @State private var pendingImport: CustomLayoutArchive?
    @State private var transferStatus: String?

    private var selectedIndex: Int? {
        guard let selectedLayoutID else { return nil }
        return library.customLayouts.firstIndex { $0.id == selectedLayoutID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved layouts")
                    .font(.headline)

                List(selection: $selectedLayoutID) {
                    ForEach(library.customGroups) { group in
                        let layouts = library.customLayouts.filter { $0.groupID == group.id }
                        if !layouts.isEmpty {
                            Section(group.name) {
                                layoutRows(layouts)
                            }
                        }
                    }

                    let unassigned = library.customLayouts.filter { $0.groupID == nil }
                    if !unassigned.isEmpty {
                        Section("Unassigned") {
                            layoutRows(unassigned)
                        }
                    }
                }
                .overlay {
                    if library.customLayouts.isEmpty {
                        ContentUnavailableView(
                            "No Custom Layouts",
                            systemImage: "rectangle.dashed",
                            description: Text("Select Add to create one.")
                        )
                    }
                }

                HStack {
                    Button("Add", systemImage: "plus") {
                        addLayout()
                    }
                    .disabled(
                        library.customLayouts.count >= LayoutLibrary.maximumCustomLayouts
                    )

                    Button("Remove", systemImage: "trash") {
                        removeSelectedLayout()
                    }
                    .disabled(selectedIndex == nil)
                }

                HStack {
                    Button("Move Up", systemImage: "arrow.up") {
                        moveSelectedLayout(by: -1)
                    }
                    .disabled(adjacentLayoutIndex(offset: -1) == nil)

                    Button("Move Down", systemImage: "arrow.down") {
                        moveSelectedLayout(by: 1)
                    }
                    .disabled(adjacentLayoutIndex(offset: 1) == nil)
                }

                Divider()

                HStack {
                    Button("Import…", systemImage: "square.and.arrow.down") {
                        chooseArchiveToImport()
                    }

                    Button("Export…", systemImage: "square.and.arrow.up") {
                        exportArchive()
                    }
                }

                if let transferStatus {
                    Text(transferStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(library.customLayouts.count) of \(LayoutLibrary.maximumCustomLayouts) layouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 260)

            Divider()

            if let selectedIndex {
                LayoutDefinitionEditor(
                    layout: $library.customLayouts[selectedIndex],
                    groups: library.customGroups
                )
                .id(library.customLayouts[selectedIndex].id)
            } else {
                ContentUnavailableView(
                    "Add or select a layout",
                    systemImage: "rectangle.grid.2x2"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectFirstLayoutIfNeeded()
        }
        .onChange(of: library.customLayouts.map(\.id)) {
            selectFirstLayoutIfNeeded()
        }
        .alert(item: $transferAlert) { alert in
            switch alert {
            case .confirmImport(let layoutCount, let groupCount):
                Alert(
                    title: Text("Replace Custom Layouts?"),
                    message: Text(
                        "This will replace the current custom layouts and groups in this Settings draft with \(layoutCount) layouts and \(groupCount) groups. Changes are not saved until you click Apply."
                    ),
                    primaryButton: .destructive(Text("Replace")) {
                        applyPendingImport()
                    },
                    secondaryButton: .cancel {
                        pendingImport = nil
                    }
                )
            case .error(let message):
                Alert(
                    title: Text("Custom Layout Transfer Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    @ViewBuilder
    private func layoutRows(_ layouts: [LayoutDefinition]) -> some View {
        ForEach(layouts) { layout in
            Text(layout.name)
                .tag(layout.id)
        }
    }

    private func addLayout() {
        guard library.customLayouts.count < LayoutLibrary.maximumCustomLayouts else { return }
        let layout = LayoutDefinition(
            name: "Custom Layout \(library.customLayouts.count + 1)",
            normalizedRect: try! NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        )
        library.customLayouts.append(layout)
        selectedLayoutID = layout.id
    }

    private func removeSelectedLayout() {
        guard let selectedIndex else { return }
        let actionID = library.customLayouts[selectedIndex].shortcutActionID.rawValue
        library.shortcuts.removeValue(forKey: actionID)
        library.customLayouts.remove(at: selectedIndex)
        selectedLayoutID = library.customLayouts.indices.contains(selectedIndex)
            ? library.customLayouts[selectedIndex].id
            : library.customLayouts.last?.id
    }

    private func adjacentLayoutIndex(offset: Int) -> Int? {
        guard let selectedIndex else { return nil }
        let groupID = library.customLayouts[selectedIndex].groupID
        let matchingIndices = library.customLayouts.indices.filter {
            library.customLayouts[$0].groupID == groupID
        }
        guard let position = matchingIndices.firstIndex(of: selectedIndex) else { return nil }
        let targetPosition = position + offset
        guard matchingIndices.indices.contains(targetPosition) else { return nil }
        return matchingIndices[targetPosition]
    }

    private func moveSelectedLayout(by offset: Int) {
        guard let selectedIndex,
              let targetIndex = adjacentLayoutIndex(offset: offset) else { return }
        library.customLayouts.swapAt(selectedIndex, targetIndex)
    }

    private func selectFirstLayoutIfNeeded() {
        if let selectedLayoutID,
           library.customLayouts.contains(where: { $0.id == selectedLayoutID }) {
            return
        }
        selectedLayoutID = library.customLayouts.first?.id
    }

    private func exportArchive() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Window Layouts Custom Layouts.json"
        panel.title = String(localized: "Export Custom Layouts")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(CustomLayoutArchive(library: library))
            try data.write(to: url, options: .atomic)
            transferStatus = String(localized: "Custom layouts exported.")
        } catch {
            transferAlert = .error(error.localizedDescription)
        }
    }

    private func chooseArchiveToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = String(localized: "Import Custom Layouts")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let archive = try JSONDecoder().decode(
                CustomLayoutArchive.self,
                from: Data(contentsOf: url)
            )
            _ = try archive.applying(to: library)
            pendingImport = archive
            transferAlert = .confirmImport(
                layoutCount: archive.customLayouts.count,
                groupCount: archive.customGroups.count
            )
        } catch {
            transferAlert = .error(error.localizedDescription)
        }
    }

    private func applyPendingImport() {
        guard let pendingImport else { return }
        do {
            library = try pendingImport.applying(to: library)
            selectedLayoutID = library.customLayouts.first?.id
            transferStatus = String(localized: "Custom layouts imported. Click Apply to save.")
            self.pendingImport = nil
        } catch {
            self.pendingImport = nil
            transferAlert = .error(error.localizedDescription)
        }
    }
}

private enum LayoutTransferAlert: Identifiable {
    case confirmImport(layoutCount: Int, groupCount: Int)
    case error(String)

    var id: String {
        switch self {
        case .confirmImport(let layoutCount, let groupCount):
            "confirm-\(layoutCount)-\(groupCount)"
        case .error(let message):
            "error-\(message)"
        }
    }
}

private struct LayoutDefinitionEditor: View {
    @Binding var layout: LayoutDefinition
    let groups: [LayoutGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name")
                .font(.headline)
            TextField("Layout name", text: $layout.name)

            Text("Custom group")
                .font(.headline)
            Picker("Custom group", selection: $layout.groupID) {
                Text("Unassigned").tag(nil as UUID?)
                ForEach(groups) { group in
                    Text(group.name).tag(group.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)

            Text("Drag across the 24 × 12 grid to choose the window’s position and size.")
                .foregroundStyle(.secondary)

            LayoutGridEditor(normalizedRect: $layout.normalizedRect)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(geometryDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var geometryDescription: String {
        let selection = LayoutGridSelection(normalizedRect: layout.normalizedRect)
        let x = Int((layout.normalizedRect.x * 100).rounded())
        let y = Int((layout.normalizedRect.y * 100).rounded())
        let width = Int((layout.normalizedRect.width * 100).rounded())
        let height = Int((layout.normalizedRect.height * 100).rounded())
        return "Position: \(x)%, \(y)% · Size: \(width)% × \(height)% · Grid: \(selection.columnSpan) × \(selection.rowSpan)"
    }
}
