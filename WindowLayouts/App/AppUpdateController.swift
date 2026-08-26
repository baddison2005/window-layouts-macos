// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation

@MainActor
final class AppUpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(latestVersion: SemanticVersion)
        case available(AvailableAppUpdate)
        case downloading(AvailableAppUpdate)
        case installing(AvailableAppUpdate)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastAvailableUpdate: AvailableAppUpdate?

    let currentVersion: SemanticVersion
    let currentBuild: String
    let repositoryURL = GitHubAppUpdateService.repositoryURL

    private let updateService: GitHubAppUpdateService
    private let installer: AppUpdateInstaller
    private let applicationURL: URL
    private var operation: Task<Void, Never>?

    init(
        bundle: Bundle = .main,
        updateService: GitHubAppUpdateService = GitHubAppUpdateService(),
        installer: AppUpdateInstaller = AppUpdateInstaller()
    ) {
        let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        self.currentVersion = SemanticVersion(version ?? "")
            ?? SemanticVersion("0.0.0")!
        self.currentBuild = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        self.applicationURL = bundle.bundleURL
        self.updateService = updateService
        self.installer = installer
    }

    deinit {
        operation?.cancel()
    }

    var automaticInstallationAvailable: Bool {
        AppUpdateInstaller.supportsAutomaticInstallation(at: applicationURL)
    }

    func checkForUpdates() {
        operation?.cancel()
        lastAvailableUpdate = nil
        state = .checking
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let availability = try await updateService.check(
                    currentVersion: currentVersion
                )
                guard !Task.isCancelled else { return }
                switch availability {
                case .upToDate(let latestVersion):
                    state = .upToDate(latestVersion: latestVersion)
                case .available(let release):
                    lastAvailableUpdate = release
                    state = .available(release)
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func install(_ release: AvailableAppUpdate) {
        lastAvailableUpdate = release
        guard automaticInstallationAvailable else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        operation?.cancel()
        state = .downloading(release)
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await installer.prepare(release)
                guard !Task.isCancelled else { return }
                state = .installing(release)
                let installed = try await installer.install(
                    prepared,
                    currentApplicationURL: applicationURL
                )
                guard !Task.isCancelled else {
                    await installer.rollback(installed)
                    return
                }
                do {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    configuration.createsNewApplicationInstance = true
                    _ = try await NSWorkspace.shared.openApplication(
                        at: installed.applicationURL,
                        configuration: configuration
                    )
                    UserDefaults.standard.set(
                        installed.backupURL.path,
                        forKey: AppUpdateInstaller.pendingBackupDefaultsKey
                    )
                    NSApp.terminate(nil)
                } catch {
                    await installer.rollback(installed)
                    state = .failed(AppUpdateError.relaunchFailed.localizedDescription)
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func openReleasePage(_ release: AvailableAppUpdate) {
        NSWorkspace.shared.open(release.pageURL)
    }
}
