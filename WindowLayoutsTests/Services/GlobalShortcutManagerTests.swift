// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon
import Foundation
import Testing
@testable import WindowLayouts

@MainActor
struct GlobalShortcutManagerTests {
    @Test func appliesSavedAssignmentsAndDispatchesStableActions() throws {
        let persistence = LayoutLibraryPersistence(fileURL: temporaryFileURL())
        let store = SettingsStore(persistence: persistence)
        let service = ShortcutServiceSpy()
        var performed: [WindowAction] = []
        let manager = GlobalShortcutManager(
            settingsStore: store,
            service: service,
            actionHandler: { performed.append($0) }
        )
        let shortcut = KeyboardShortcut(
            keyCode: 123,
            modifiers: [.control, .option],
            keyLabel: "←"
        )

        try store.apply(LayoutLibrary(shortcuts: ["fixed.leftHalf": shortcut]))

        #expect(service.assignments[ShortcutActionID(rawValue: "fixed.leftHalf")] == shortcut)
        service.onAction?(ShortcutActionID(rawValue: "fixed.leftHalf"))
        #expect(performed == [.fixed(.leftHalf)])
        _ = manager
    }

    @Test func exposesRegistrationFailuresAndRetries() throws {
        let persistence = LayoutLibraryPersistence(fileURL: temporaryFileURL())
        let store = SettingsStore(persistence: persistence)
        let service = ShortcutServiceSpy()
        service.failures = [
            ShortcutRegistrationFailure(
                actionID: ShortcutActionID(rawValue: "window.center"),
                status: OSStatus(eventHotKeyExistsErr)
            ),
        ]
        let manager = GlobalShortcutManager(
            settingsStore: store,
            service: service,
            actionHandler: { _ in }
        )

        try store.apply(LayoutLibrary(shortcuts: [
            "window.center": KeyboardShortcut(
                keyCode: 8,
                modifiers: [.command, .option],
                keyLabel: "C"
            ),
        ]))
        #expect(manager.registrationFailures.count == 1)

        service.failures = []
        manager.retry()
        #expect(manager.registrationFailures.isEmpty)
        #expect(service.replaceCount >= 3)
    }

    @Test func dispatchesFillTargetDisplayShortcut() throws {
        let persistence = LayoutLibraryPersistence(fileURL: temporaryFileURL())
        let store = SettingsStore(persistence: persistence)
        let service = ShortcutServiceSpy()
        var filledGroups: [WindowFillGroup] = []
        let manager = GlobalShortcutManager(
            settingsStore: store,
            service: service,
            actionHandler: { _ in },
            fillScreenHandler: { filledGroups.append($0) }
        )
        let shortcut = KeyboardShortcut(
            keyCode: 17,
            modifiers: [.control, .option],
            keyLabel: "T"
        )
        let actionID = ShortcutActionID(rawValue: "fill.builtin.thirds")

        try store.apply(LayoutLibrary(shortcuts: [actionID.rawValue: shortcut]))
        service.onAction?(actionID)

        #expect(filledGroups.count == 1)
        #expect(filledGroups.first?.id == "builtin.thirds")
        #expect(filledGroups.first?.name == "Thirds")
        _ = manager
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("layouts.json")
    }
}

@MainActor
private final class ShortcutServiceSpy: GlobalShortcutRegistering {
    var onAction: ((ShortcutActionID) -> Void)?
    var assignments: [ShortcutActionID: KeyboardShortcut] = [:]
    var failures: [ShortcutRegistrationFailure] = []
    var replaceCount = 0

    func replaceRegistrations(
        _ assignments: [ShortcutActionID: KeyboardShortcut]
    ) -> [ShortcutRegistrationFailure] {
        replaceCount += 1
        self.assignments = assignments
        return failures
    }

    func stop() {}
}
