// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

struct LayoutLibraryPersistenceTests {
    private func temporaryLocation() -> (directory: URL, persistence: LayoutLibraryPersistence) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("window-layouts-tests-\(UUID().uuidString)", isDirectory: true)
        return (
            directory,
            LayoutLibraryPersistence(
                fileURL: directory.appendingPathComponent("layout-library.json")
            )
        )
    }

    @Test func missingFileUsesSafeDefaultsWithoutCreatingAFile() {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let result = location.persistence.load()

        #expect(result.library == LayoutLibrary())
        #expect(result.warning == nil)
        #expect(!FileManager.default.fileExists(atPath: location.persistence.fileURL.path))
    }

    @Test func validSettingsSurviveRelaunch() throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let layout = LayoutDefinition(
            name: "Reading",
            normalizedRect: try NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
        )
        let library = LayoutLibrary(
            customLayouts: [layout],
            layoutPadding: 18,
            shortcuts: [
                layout.shortcutActionID.rawValue: KeyboardShortcut(
                    keyCode: 15,
                    modifiers: [.command, .option],
                    keyLabel: "R"
                ),
            ],
            launchAtLogin: true,
            showDockIcon: true,
            greenButtonPanelEnabled: true,
            layoutPanelSize: .big,
            dragTargetsEnabled: true,
            dragTargetPlacement: .top,
            showAllTopDragTargets: true
        )

        try location.persistence.save(library)
        let reloaded = location.persistence.load()

        #expect(reloaded.warning == nil)
        #expect(reloaded.library == library)
    }

    @Test func corruptFileFallsBackWithoutDestroyingTheOriginal() throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try FileManager.default.createDirectory(
            at: location.directory,
            withIntermediateDirectories: true
        )
        let corruptData = Data("{ definitely not valid JSON".utf8)
        try corruptData.write(to: location.persistence.fileURL)

        let result = location.persistence.load()

        #expect(result.library == LayoutLibrary())
        #expect(result.warning != nil)
        #expect(try Data(contentsOf: location.persistence.fileURL) == corruptData)
    }

    @MainActor
    @Test func settingsStorePublishesOnlySuccessfullySavedSettings() throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = SettingsStore(persistence: location.persistence)
        var candidate = store.library
        candidate.layoutPadding = 24

        try store.apply(candidate)

        #expect(store.library.layoutPadding == 24)
        #expect(location.persistence.load().library.layoutPadding == 24)
    }
}
