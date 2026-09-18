// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation
import OSLog

nonisolated struct RunningApplicationDescriptor: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let isRegularApplication: Bool
}

nonisolated enum ApplicationLaunchMappingPolicy {
    static func shouldHandleLaunch(
        isArmed: Bool,
        launched: RunningApplicationDescriptor,
        runningApplications: [RunningApplicationDescriptor]
    ) -> Bool {
        guard isArmed,
              launched.isRegularApplication,
              let bundleIdentifier = launched.bundleIdentifier else {
            return false
        }
        return !runningApplications.contains {
            $0.processIdentifier != launched.processIdentifier
                && $0.bundleIdentifier == bundleIdentifier
                && $0.isRegularApplication
        }
    }
}

@MainActor
final class ApplicationLaunchMappingController: ObservableObject {
    static let startupGracePeriod = Duration.seconds(30)

    private let settingsStore: SettingsStore
    private let windowService: WindowAccessibilityService
    private let workspace: NSWorkspace
    private var launchObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var startupTask: Task<Void, Never>?
    private var mappingTasks: [pid_t: Task<Void, Never>] = [:]
    private var isArmed = false

    init(
        settingsStore: SettingsStore,
        windowService: WindowAccessibilityService,
        workspace: NSWorkspace = .shared
    ) {
        self.settingsStore = settingsStore
        self.windowService = windowService
        self.workspace = workspace
        installObservers()
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: Self.startupGracePeriod)
            guard !Task.isCancelled else { return }
            self?.isArmed = true
            AppDiagnostics.applicationMappings.debug(
                "Application mappings armed after startup grace period"
            )
        }
    }

    deinit {
        startupTask?.cancel()
        mappingTasks.values.forEach { $0.cancel() }
        if let launchObserver {
            workspace.notificationCenter.removeObserver(launchObserver)
        }
        if let terminationObserver {
            workspace.notificationCenter.removeObserver(terminationObserver)
        }
    }

    private func installObservers() {
        launchObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.applicationDidLaunch(application)
            }
        }
        terminationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.applicationDidTerminate(application)
            }
        }
    }

    private func applicationDidLaunch(_ application: NSRunningApplication) {
        let launched = descriptor(for: application)
        let running = workspace.runningApplications.map(descriptor(for:))
        guard ApplicationLaunchMappingPolicy.shouldHandleLaunch(
            isArmed: isArmed,
            launched: launched,
            runningApplications: running
        ), let bundleIdentifier = application.bundleIdentifier,
           let mapping = settingsStore.library.applicationWindowMappings.first(where: {
               $0.bundleIdentifier == bundleIdentifier
           }), let action = mapping.layout.action(in: settingsStore.library) else {
            return
        }

        let screens = ScreenService.snapshots()
        guard let destination = ScreenGeometryResolver.mappedScreen(
            persistentID: mapping.displayIdentifier,
            fallbackName: mapping.displayName,
            among: screens
        ) else {
            AppDiagnostics.applicationMappings.error(
                "Mapped display unavailable app=\(mapping.applicationName, privacy: .private(mask: .hash))"
            )
            return
        }

        let processIdentifier = application.processIdentifier
        let library = settingsStore.library
        let knownLayouts = FixedLayout.allCases.map(\.normalizedRect)
            + library.customLayouts.map(\.normalizedRect)
        let windowService = self.windowService
        mappingTasks[processIdentifier]?.cancel()
        mappingTasks[processIdentifier] = Task { [weak self] in
            do {
                try await windowService.performApplicationMapping(
                    action,
                    processIdentifier: processIdentifier,
                    applicationBundleIdentifier: bundleIdentifier,
                    applicationName: mapping.applicationName,
                    windowRequirement: mapping.windowRequirement,
                    destinationScreenID: destination.id,
                    screens: screens,
                    padding: CGFloat(library.layoutPadding),
                    knownLayouts: knownLayouts
                )
                AppDiagnostics.applicationMappings.info(
                    "Application mapping applied app=\(mapping.applicationName, privacy: .private(mask: .hash)) pid=\(Int(processIdentifier), privacy: .private)"
                )
            } catch is CancellationError {
                return
            } catch {
                AppDiagnostics.applicationMappings.error(
                    "Application mapping failed app=\(mapping.applicationName, privacy: .private(mask: .hash)) pid=\(Int(processIdentifier), privacy: .private) error=\(String(describing: error), privacy: .private)"
                )
            }
            self?.mappingTasks[processIdentifier] = nil
        }
    }

    private func applicationDidTerminate(_ application: NSRunningApplication) {
        mappingTasks.removeValue(forKey: application.processIdentifier)?.cancel()
    }

    private func descriptor(for application: NSRunningApplication) -> RunningApplicationDescriptor {
        RunningApplicationDescriptor(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            isRegularApplication: application.activationPolicy == .regular
        )
    }
}
