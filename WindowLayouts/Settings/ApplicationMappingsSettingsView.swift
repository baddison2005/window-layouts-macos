// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationMappingsSettingsView: View {
    @Binding var library: LayoutLibrary
    let screens: [ScreenSnapshot]

    @State private var selectedMappingID: UUID?
    @State private var statusMessage: String?

    private var selectedIndex: Int? {
        guard let selectedMappingID else { return nil }
        return library.applicationWindowMappings.firstIndex { $0.id == selectedMappingID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mapped applications")
                    .font(.headline)

                List(selection: $selectedMappingID) {
                    ForEach(library.applicationWindowMappings) { mapping in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mapping.applicationName)
                            Text(mapping.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mapping.id)
                    }
                }
                .overlay {
                    if library.applicationWindowMappings.isEmpty {
                        ContentUnavailableView(
                            "No Application Mappings",
                            systemImage: "app.badge",
                            description: Text("Select Add Application to create one.")
                        )
                    }
                }

                HStack {
                    Button("Add Application…", systemImage: "plus") {
                        chooseApplication()
                    }
                    .disabled(
                        library.applicationWindowMappings.count
                            >= LayoutLibrary.maximumApplicationMappings
                    )

                    Button("Remove", systemImage: "trash") {
                        removeSelectedMapping()
                    }
                    .disabled(selectedIndex == nil)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 300)

            Divider()

            if let selectedIndex {
                mappingEditor(index: selectedIndex)
            } else {
                ContentUnavailableView(
                    "Add or select an application",
                    systemImage: "app.badge"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selectFirstMappingIfNeeded() }
        .onChange(of: library.applicationWindowMappings.map(\.id)) {
            selectFirstMappingIfNeeded()
        }
    }

    @ViewBuilder
    private func mappingEditor(index: Int) -> some View {
        Form {
            LabeledContent("Application") {
                Text(library.applicationWindowMappings[index].applicationName)
            }
            LabeledContent("Bundle identifier") {
                Text(library.applicationWindowMappings[index].bundleIdentifier)
                    .textSelection(.enabled)
            }

            Picker(
                "Layout",
                selection: $library.applicationWindowMappings[index].layout
            ) {
                Section("Built-in") {
                    ForEach(FixedLayout.allCases) { layout in
                        Text(layout.name)
                            .tag(ApplicationLayoutReference.fixed(layout))
                    }
                }
                if !library.customLayouts.isEmpty {
                    Section("Custom") {
                        ForEach(library.customLayouts) { layout in
                            Text(layout.name)
                                .tag(ApplicationLayoutReference.custom(layout.id))
                        }
                    }
                }
            }

            Picker(
                "Display",
                selection: displaySelection(index: index)
            ) {
                if !screens.contains(where: {
                    $0.persistentID
                        == library.applicationWindowMappings[index].displayIdentifier
                }) {
                    Text("\(library.applicationWindowMappings[index].displayName) (unavailable)")
                        .tag(library.applicationWindowMappings[index].displayIdentifier)
                }
                ForEach(screens, id: \.persistentID) { screen in
                    Text(screen.name).tag(screen.persistentID)
                }
            }

            Picker(
                "Window to place",
                selection: $library.applicationWindowMappings[index].windowRequirement
            ) {
                ForEach(ApplicationWindowRequirement.allCases, id: \.rawValue) { requirement in
                    Text(requirement.name).tag(requirement)
                }
            }

            if library.applicationWindowMappings[index].windowRequirement == .documentWindow {
                Text(
                    "Use Document window for applications such as Microsoft Word or Excel that first show a start screen. Window Layouts waits until a document is opened or created."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(
                "Mappings apply only when the application was closed and is launched after Window Layouts' startup grace period. Applications already open or restored when you log in are not moved."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displaySelection(index: Int) -> Binding<String> {
        Binding(
            get: { library.applicationWindowMappings[index].displayIdentifier },
            set: { identifier in
                library.applicationWindowMappings[index].displayIdentifier = identifier
                if let screen = screens.first(where: { $0.persistentID == identifier }) {
                    library.applicationWindowMappings[index].displayName = screen.name
                }
            }
        )
    }

    private func chooseApplication() {
        guard let defaultScreen = screens.first else {
            statusMessage = String(localized: "No display is currently available.")
            return
        }

        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an Application")
        panel.prompt = String(localized: "Add Application")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK,
              let applicationURL = panel.url,
              let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier else {
            return
        }
        if bundleIdentifier == Bundle.main.bundleIdentifier {
            statusMessage = String(localized: "Window Layouts cannot map itself.")
            return
        }
        if let existing = library.applicationWindowMappings.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            selectedMappingID = existing.id
            statusMessage = String(localized: "That application is already mapped.")
            return
        }

        let displayName = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let applicationName = displayName
            ?? bundleName
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let mapping = ApplicationWindowMapping(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            layout: .fixed(.leftHalf),
            displayIdentifier: defaultScreen.persistentID,
            displayName: defaultScreen.name
        )
        library.applicationWindowMappings.append(mapping)
        selectedMappingID = mapping.id
        statusMessage = nil
    }

    private func removeSelectedMapping() {
        guard let selectedIndex else { return }
        library.applicationWindowMappings.remove(at: selectedIndex)
        selectedMappingID = library.applicationWindowMappings.indices.contains(selectedIndex)
            ? library.applicationWindowMappings[selectedIndex].id
            : library.applicationWindowMappings.last?.id
    }

    private func selectFirstMappingIfNeeded() {
        if let selectedMappingID,
           library.applicationWindowMappings.contains(where: { $0.id == selectedMappingID }) {
            return
        }
        selectedMappingID = library.applicationWindowMappings.first?.id
    }
}
