// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing
@testable import WindowLayouts

struct ExternalApplicationTrackingTests {
    @Test func recordsAnExternalApplication() {
        #expect(
            ExternalApplicationTracking.updatedProcessIdentifier(
                current: nil,
                candidate: 42,
                own: 7
            ) == 42
        )
    }

    @Test func keepsTheExternalApplicationWhenWindowLayoutsActivates() {
        #expect(
            ExternalApplicationTracking.updatedProcessIdentifier(
                current: 42,
                candidate: 7,
                own: 7
            ) == 42
        )
    }

    @Test func ignoresMissingAndInvalidCandidates() {
        #expect(
            ExternalApplicationTracking.updatedProcessIdentifier(
                current: 42,
                candidate: nil,
                own: 7
            ) == 42
        )
        #expect(
            ExternalApplicationTracking.updatedProcessIdentifier(
                current: 42,
                candidate: 0,
                own: 7
            ) == 42
        )
    }
}

@MainActor
struct DockIntegrationControllerTests {
    @Test func dockMenuConfigureInvokesThePublicSettingsAction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "window-layouts-dock-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = LayoutLibraryPersistence(
            fileURL: directory.appendingPathComponent("layout-library.json")
        )
        try persistence.save(LayoutLibrary(showDockIcon: true))
        let settingsStore = SettingsStore(persistence: persistence)
        let windowController = WindowLayoutsController(
            settingsStore: settingsStore
        )
        let dockController = DockIntegrationController(
            settingsStore: settingsStore,
            windowController: windowController
        )
        var settingsOpened = false
        dockController.installOpenSettingsAction {
            settingsOpened = true
        }

        let menu = try #require(dockController.makeDockMenu())
        let fillItem = try #require(
            menu.items.first { $0.title == "Fill Target Display" }
        )
        #expect(fillItem.submenu?.items.map(\.title) == [
            "Horizontal Halves",
            "Vertical Halves",
            "Quarters",
            "Thirds",
        ])

        let configureItem = try #require(
            menu.items.first {
                $0.title == "Configure Window Layouts Experimental…"
            }
        )
        #expect(configureItem.isEnabled)

        let action = try #require(configureItem.action)
        #expect(
            NSApp.sendAction(
                action,
                to: configureItem.target,
                from: configureItem
            )
        )

        #expect(settingsOpened)
    }
}
