// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct GroupsSettingsView: View {
    @Binding var library: LayoutLibrary
    @State private var selectedGroupID: UUID?
    @State private var selectedMenuGroupID: String?
    @State private var newGroupName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom groups")
                    .font(.headline)
                Text("Layouts appear under these groups in the Custom menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List(selection: $selectedGroupID) {
                    ForEach(library.customGroups) { group in
                        Text(group.name).tag(group.id)
                    }
                }

                if let index = selectedGroupIndex {
                    TextField("Group name", text: $library.customGroups[index].name)
                }

                HStack {
                    TextField("New group", text: $newGroupName)
                    Button("Add") {
                        addGroup()
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Button("Remove", systemImage: "trash") {
                        removeSelectedGroup()
                    }
                    .disabled(selectedGroupIndex == nil)

                    Button("Up", systemImage: "arrow.up") {
                        moveSelectedGroup(by: -1)
                    }
                    .disabled(!canMoveSelectedGroup(by: -1))

                    Button("Down", systemImage: "arrow.down") {
                        moveSelectedGroup(by: 1)
                    }
                    .disabled(!canMoveSelectedGroup(by: 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Menu group order")
                    .font(.headline)
                Text("Reorder the built-in and Custom sections in the menu-bar menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List(selection: $selectedMenuGroupID) {
                    ForEach(library.menuGroupOrder, id: \.self) { identifier in
                        Text(MenuGroupIdentifier(rawValue: identifier)?.name ?? identifier)
                            .tag(identifier)
                    }
                }

                HStack {
                    Button("Up", systemImage: "arrow.up") {
                        moveSelectedMenuGroup(by: -1)
                    }
                    .disabled(!canMoveSelectedMenuGroup(by: -1))

                    Button("Down", systemImage: "arrow.down") {
                        moveSelectedMenuGroup(by: 1)
                    }
                    .disabled(!canMoveSelectedMenuGroup(by: 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectedGroupID = selectedGroupID ?? library.customGroups.first?.id
            selectedMenuGroupID = selectedMenuGroupID ?? library.menuGroupOrder.first
        }
    }

    private var selectedGroupIndex: Int? {
        guard let selectedGroupID else { return nil }
        return library.customGroups.firstIndex { $0.id == selectedGroupID }
    }

    private var selectedMenuGroupIndex: Int? {
        guard let selectedMenuGroupID else { return nil }
        return library.menuGroupOrder.firstIndex(of: selectedMenuGroupID)
    }

    private func addGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = LayoutGroup(name: String(name.prefix(LayoutLibrary.maximumNameLength)))
        library.customGroups.append(group)
        selectedGroupID = group.id
        newGroupName = ""
    }

    private func removeSelectedGroup() {
        guard let selectedGroupIndex else { return }
        let removedGroup = library.customGroups[selectedGroupIndex]
        let removedID = removedGroup.id
        library.shortcuts.removeValue(forKey: removedGroup.fillShortcutActionID.rawValue)
        library.customGroups.remove(at: selectedGroupIndex)
        for index in library.customLayouts.indices
        where library.customLayouts[index].groupID == removedID {
            library.customLayouts[index].groupID = nil
        }
        selectedGroupID = library.customGroups.indices.contains(selectedGroupIndex)
            ? library.customGroups[selectedGroupIndex].id
            : library.customGroups.last?.id
    }

    private func canMoveSelectedGroup(by offset: Int) -> Bool {
        guard let selectedGroupIndex else { return false }
        return library.customGroups.indices.contains(selectedGroupIndex + offset)
    }

    private func moveSelectedGroup(by offset: Int) {
        guard let selectedGroupIndex,
              library.customGroups.indices.contains(selectedGroupIndex + offset) else { return }
        library.customGroups.swapAt(selectedGroupIndex, selectedGroupIndex + offset)
    }

    private func canMoveSelectedMenuGroup(by offset: Int) -> Bool {
        guard let selectedMenuGroupIndex else { return false }
        return library.menuGroupOrder.indices.contains(selectedMenuGroupIndex + offset)
    }

    private func moveSelectedMenuGroup(by offset: Int) {
        guard let selectedMenuGroupIndex,
              library.menuGroupOrder.indices.contains(selectedMenuGroupIndex + offset) else {
            return
        }
        library.menuGroupOrder.swapAt(
            selectedMenuGroupIndex,
            selectedMenuGroupIndex + offset
        )
    }
}
