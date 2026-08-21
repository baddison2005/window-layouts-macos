// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

@MainActor
struct LaunchAtLoginManagerTests {
    @Test func enablingRegistersAndReportsEnabled() throws {
        let store = makeStore()
        let system = LoginItemSystemSpy(status: .notRegistered)
        let manager = LaunchAtLoginManager(
            settingsStore: store,
            client: system.client
        )

        try store.apply(LayoutLibrary(launchAtLogin: true))

        #expect(system.registerCount == 1)
        #expect(manager.state == .enabled)
    }

    @Test func disablingUnregistersAnEnabledLoginItem() throws {
        let store = makeStore(initial: LayoutLibrary(launchAtLogin: true))
        let system = LoginItemSystemSpy(status: .enabled)
        let manager = LaunchAtLoginManager(
            settingsStore: store,
            client: system.client
        )

        try store.apply(LayoutLibrary(launchAtLogin: false))

        #expect(system.unregisterCount == 1)
        #expect(manager.state == .disabled)
    }

    @Test func approvalStateDoesNotLoopAndCanOpenSettings() {
        let store = makeStore(initial: LayoutLibrary(launchAtLogin: true))
        let system = LoginItemSystemSpy(status: .requiresApproval)
        let manager = LaunchAtLoginManager(
            settingsStore: store,
            client: system.client
        )

        manager.retry()
        manager.openSystemSettings()

        #expect(system.registerCount == 0)
        #expect(system.openSettingsCount == 1)
        #expect(manager.state == .requiresApproval)
    }

    @Test func registrationFailureIsRecoverableWithRetry() throws {
        let store = makeStore()
        let system = LoginItemSystemSpy(status: .notRegistered)
        system.registerError = TestFailure.expected
        let manager = LaunchAtLoginManager(
            settingsStore: store,
            client: system.client
        )

        try store.apply(LayoutLibrary(launchAtLogin: true))
        guard case .failed = manager.state else {
            Issue.record("Expected a visible failure state")
            return
        }

        system.registerError = nil
        manager.retry()

        #expect(system.registerCount == 2)
        #expect(manager.state == .enabled)
    }

    @Test func unavailableStateCanRecoverAfterInstallingTheApp() throws {
        let store = makeStore()
        let system = LoginItemSystemSpy(status: .notFound)
        let manager = LaunchAtLoginManager(
            settingsStore: store,
            client: system.client
        )

        try store.apply(LayoutLibrary(launchAtLogin: true))
        #expect(manager.state == .unavailable)

        system.status = .notRegistered
        manager.retry()

        #expect(manager.state == .enabled)
    }

    private func makeStore(initial: LayoutLibrary = LayoutLibrary()) -> SettingsStore {
        let persistence = LayoutLibraryPersistence(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("layouts.json")
        )
        try! persistence.save(initial)
        return SettingsStore(persistence: persistence)
    }
}

@MainActor
private final class LoginItemSystemSpy {
    var status: LaunchAtLoginSystemStatus
    var registerError: Error?
    var unregisterError: Error?
    var registerCount = 0
    var unregisterCount = 0
    var openSettingsCount = 0

    init(status: LaunchAtLoginSystemStatus) {
        self.status = status
    }

    var client: LaunchAtLoginClient {
        LaunchAtLoginClient(
            status: { [weak self] in self?.status ?? .notFound },
            register: { [weak self] in
                guard let self else { return }
                self.registerCount += 1
                if let registerError { throw registerError }
                self.status = .enabled
            },
            unregister: { [weak self] in
                guard let self else { return }
                self.unregisterCount += 1
                if let unregisterError { throw unregisterError }
                self.status = .notRegistered
            },
            openSystemSettings: { [weak self] in
                self?.openSettingsCount += 1
            }
        )
    }
}

private enum TestFailure: Error {
    case expected
}
