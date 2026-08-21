// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

@MainActor
struct OptionalOverlaySafetyTests {
    @Test func emergencyPathDisablesEveryOptionalOverlay() throws {
        let suiteName = "OptionalOverlaySafetyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: OptionalOverlaySafety.floatingButtonKey)
        defaults.set(true, forKey: OptionalOverlaySafety.dragTargetsKey)
        defaults.set(true, forKey: OptionalOverlaySafety.greenButtonPopoverKey)

        OptionalOverlaySafety.disableAll(defaults: defaults)

        #expect(!defaults.bool(forKey: OptionalOverlaySafety.floatingButtonKey))
        #expect(!defaults.bool(forKey: OptionalOverlaySafety.dragTargetsKey))
        #expect(!defaults.bool(forKey: OptionalOverlaySafety.greenButtonPopoverKey))
    }

    @Test func canonicalEmergencyDisablePublishesAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("window-layouts-overlay-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = LayoutLibraryPersistence(
            fileURL: directory.appendingPathComponent("layout-library.json")
        )
        try persistence.save(
            LayoutLibrary(
                greenButtonPanelEnabled: true,
                dragTargetsEnabled: true
            )
        )
        let store = SettingsStore(persistence: persistence)

        #expect(store.disableOptionalPanels())

        #expect(!store.library.greenButtonPanelEnabled)
        #expect(!store.library.dragTargetsEnabled)
        #expect(!persistence.load().library.greenButtonPanelEnabled)
        #expect(!persistence.load().library.dragTargetsEnabled)
    }
}
