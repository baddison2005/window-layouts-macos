// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import OSLog
import ServiceManagement

nonisolated enum LaunchAtLoginSystemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

nonisolated enum LaunchAtLoginState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
    case failed(String)

    var label: String {
        switch self {
        case .disabled: String(localized: "Disabled")
        case .enabled: String(localized: "Enabled")
        case .requiresApproval: String(localized: "Approval required")
        case .unavailable: String(localized: "Unavailable")
        case .failed: String(localized: "Failed")
        }
    }

    var message: String? {
        switch self {
        case .disabled, .enabled:
            nil
        case .requiresApproval:
            String(localized: "macOS requires approval in System Settings > General > Login Items.")
        case .unavailable:
            String(localized: "macOS could not find this app as a login item. Run a signed app bundle and try again.")
        case let .failed(message):
            message
        }
    }
}

@MainActor
struct LaunchAtLoginClient {
    var status: () -> LaunchAtLoginSystemStatus
    var register: () throws -> Void
    var unregister: () throws -> Void
    var openSystemSettings: () -> Void

    static let live = LaunchAtLoginClient(
        status: {
            switch SMAppService.mainApp.status {
            case .notRegistered: .notRegistered
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notFound: .notFound
            @unknown default: .notFound
            }
        },
        register: {
            try SMAppService.mainApp.register()
        },
        unregister: {
            try SMAppService.mainApp.unregister()
        },
        openSystemSettings: {
            SMAppService.openSystemSettingsLoginItems()
        }
    )
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState = .disabled

    private let settingsStore: SettingsStore
    private let client: LaunchAtLoginClient
    private var settingsObservation: AnyCancellable?
    private var lastDesiredValue: Bool?

    convenience init(settingsStore: SettingsStore) {
        self.init(settingsStore: settingsStore, client: .live)
    }

    init(
        settingsStore: SettingsStore,
        client: LaunchAtLoginClient
    ) {
        self.settingsStore = settingsStore
        self.client = client
        settingsObservation = settingsStore.$library.sink { [weak self] library in
            self?.reconcile(desired: library.launchAtLogin)
        }
    }

    func retry() {
        reconcile(desired: settingsStore.library.launchAtLogin, force: true)
    }

    func openSystemSettings() {
        client.openSystemSettings()
    }

    private func reconcile(desired: Bool, force: Bool = false) {
        guard force || lastDesiredValue != desired else { return }
        lastDesiredValue = desired

        if desired {
            enableIfNeeded()
        } else {
            disableIfNeeded()
        }
    }

    private func enableIfNeeded() {
        switch client.status() {
        case .enabled:
            state = .enabled
        case .requiresApproval:
            state = .requiresApproval
        case .notFound:
            state = .unavailable
        case .notRegistered:
            do {
                try client.register()
                updateStateAfterEnableAttempt()
            } catch {
                AppDiagnostics.lifecycle.error(
                    "Launch at login could not be enabled: \(String(describing: error), privacy: .private)"
                )
                state = .failed(String(localized: "Launch at login could not be enabled: \(error.localizedDescription)"))
            }
        }
    }

    private func updateStateAfterEnableAttempt() {
        switch client.status() {
        case .enabled:
            state = .enabled
        case .requiresApproval:
            state = .requiresApproval
        case .notFound:
            state = .unavailable
        case .notRegistered:
            state = .failed(String(localized: "macOS did not enable the login item."))
        }
    }

    private func disableIfNeeded() {
        switch client.status() {
        case .notRegistered, .notFound:
            state = .disabled
        case .enabled, .requiresApproval:
            do {
                try client.unregister()
                if client.status() == .notRegistered {
                    state = .disabled
                } else {
                    state = .failed(String(localized: "macOS did not disable the login item."))
                }
            } catch {
                AppDiagnostics.lifecycle.error(
                    "Launch at login could not be disabled: \(String(describing: error), privacy: .private)"
                )
                state = .failed(String(localized: "Launch at login could not be disabled: \(error.localizedDescription)"))
            }
        }
    }
}
