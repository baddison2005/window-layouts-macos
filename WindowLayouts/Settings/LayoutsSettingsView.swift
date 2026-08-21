// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct LayoutsSettingsView: View {
    @Binding var library: LayoutLibrary
    @State private var selectedLayoutID: UUID?

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
