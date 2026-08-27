// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import OSLog

@MainActor
final class WindowLayoutsController: ObservableObject {
    @Published private(set) var hasAccessibilityAccess: Bool
    @Published private(set) var hasPostEventAccess: Bool
    @Published private(set) var monitorCount: Int
    @Published private(set) var isPerformingAction = false
    @Published private(set) var statusMessage: String?

    private let permissionService: AccessibilityPermissionService
    private let windowService: WindowAccessibilityService
    private let spaceMovementService: SpaceMovementService
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        let permissionService = AccessibilityPermissionService()
        self.permissionService = permissionService
        self.windowService = WindowAccessibilityService()
        let spaceMovementService = SpaceMovementService()
        self.spaceMovementService = spaceMovementService
        self.settingsStore = settingsStore
        self.hasAccessibilityAccess = permissionService.isTrusted()
        self.hasPostEventAccess = spaceMovementService.hasPostEventAccess
        self.monitorCount = ScreenService.snapshots().count
    }

    init(
        permissionService: AccessibilityPermissionService,
        windowService: WindowAccessibilityService,
        settingsStore: SettingsStore,
        spaceMovementService: SpaceMovementService? = nil
    ) {
        self.permissionService = permissionService
        self.windowService = windowService
        self.spaceMovementService = spaceMovementService ?? SpaceMovementService()
        self.settingsStore = settingsStore
        self.hasAccessibilityAccess = permissionService.isTrusted()
        self.hasPostEventAccess = self.spaceMovementService.hasPostEventAccess
        self.monitorCount = ScreenService.snapshots().count
    }

    func refreshAccessibilityAccess() {
        hasAccessibilityAccess = permissionService.isTrusted()
        hasPostEventAccess = spaceMovementService.hasPostEventAccess
    }

    func refreshEnvironment() {
        refreshAccessibilityAccess()
        monitorCount = ScreenService.snapshots().count
    }

    func requestAccessibilityAccess() {
        hasAccessibilityAccess = permissionService.requestAccess()
        statusMessage = hasAccessibilityAccess
            ? String(localized: "Accessibility access is enabled.")
            : String(localized: "Grant access in System Settings, then choose Check Again.")
    }

    func requestPostEventAccess() {
        _ = spaceMovementService.requestPostEventAccess()
        hasPostEventAccess = spaceMovementService.hasPostEventAccess
        statusMessage = hasPostEventAccess
            ? String(localized: "Input event posting access is enabled.")
            : String(localized: "Grant access in System Settings, then choose Check Again.")
    }

    func moveWindowToSpace(_ direction: SpaceMovementDirection) {
        moveWindowToSpace(direction, targetingProcessIdentifier: nil)
    }

    func moveWindowToSpace(
        _ direction: SpaceMovementDirection,
        targetingProcessIdentifier processIdentifier: pid_t
    ) {
        moveWindowToSpace(
            direction,
            targetingProcessIdentifier: Optional(processIdentifier)
        )
    }

    private func moveWindowToSpace(
        _ direction: SpaceMovementDirection,
        targetingProcessIdentifier processIdentifier: pid_t?
    ) {
        let library = settingsStore.library
        guard library.experimentalSpaceMovementEnabled else {
            statusMessage = SpaceMovementError.featureDisabled.localizedDescription
            return
        }
        guard library.missionControlSpaceShortcutsConfirmed else {
            statusMessage = SpaceMovementError.shortcutConfirmationRequired.localizedDescription
            return
        }

        refreshEnvironment()
        guard hasAccessibilityAccess else {
            statusMessage = SpaceMovementError.accessibilityPermissionRequired.localizedDescription
            return
        }
        guard hasPostEventAccess else {
            statusMessage = SpaceMovementError.postEventPermissionRequired.localizedDescription
            return
        }
        guard !isPerformingAction else { return }

        isPerformingAction = true
        statusMessage = nil
        Task {
            do {
                try await spaceMovementService.moveWindow(
                    direction,
                    processIdentifier: processIdentifier
                )
                statusMessage = String(localized: "\(direction.name) requested.")
            } catch let error as SpaceMovementError {
                AppDiagnostics.windowOperations.error(
                    "Experimental Space movement failed direction=\(direction.rawValue, privacy: .private) error=\(String(describing: error), privacy: .private)"
                )
                if error == .accessibilityPermissionRequired {
                    hasAccessibilityAccess = false
                } else if error == .postEventPermissionRequired {
                    hasPostEventAccess = false
                }
                statusMessage = error.localizedDescription
            } catch {
                AppDiagnostics.windowOperations.error(
                    "Experimental Space movement failed direction=\(direction.rawValue, privacy: .private) error=\(String(describing: error), privacy: .private)"
                )
                statusMessage = String(localized: "The experimental Space movement gesture could not be completed.")
            }
            isPerformingAction = false
        }
    }

    func perform(_ action: WindowAction) {
        perform(action, targetingProcessIdentifier: nil)
    }

    func perform(_ action: WindowAction, targetingProcessIdentifier: pid_t) {
        perform(action, targetingProcessIdentifier: Optional(targetingProcessIdentifier))
    }

    func fillScreen(using group: WindowFillGroup) {
        fillScreen(using: group, targetingProcessIdentifier: nil)
    }

    func fillScreen(
        using group: WindowFillGroup,
        targetingProcessIdentifier processIdentifier: pid_t
    ) {
        fillScreen(
            using: group,
            targetingProcessIdentifier: Optional(processIdentifier)
        )
    }

    private func fillScreen(
        using group: WindowFillGroup,
        targetingProcessIdentifier processIdentifier: pid_t?
    ) {
        let targetProcessIdentifier = Int(processIdentifier ?? 0)
        AppDiagnostics.windowOperations.debug(
            "Fill invoked group=\(group.name, privacy: .private(mask: .hash)) targetPID=\(targetProcessIdentifier, privacy: .private)"
        )
        refreshEnvironment()
        guard hasAccessibilityAccess else {
            statusMessage = WindowAccessibilityError.permissionRequired.localizedDescription
            return
        }
        guard !isPerformingAction else { return }

        let screens = ScreenService.snapshots()
        monitorCount = screens.count
        guard !screens.isEmpty else {
            statusMessage = WindowAccessibilityError.noUsableScreen.localizedDescription
            return
        }

        isPerformingAction = true
        statusMessage = nil
        let padding = CGFloat(settingsStore.library.layoutPadding)
        Task {
            do {
                let result = try await windowService.fillScreen(
                    using: group,
                    processIdentifier: processIdentifier,
                    screens: screens,
                    padding: padding
                )
                let noun = result.appliedCount == 1 ? "window" : "windows"
                statusMessage = result.skippedCount == 0
                    ? String(localized: "Filled \(result.appliedCount) \(noun) using \(group.name).")
                    : String(localized: "Filled \(result.appliedCount) \(noun) using \(group.name); \(result.skippedCount) unavailable.")
            } catch let error as WindowAccessibilityError {
                AppDiagnostics.windowOperations.error(
                    "Fill failed group=\(group.name, privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .private)"
                )
                if error == .permissionRequired {
                    hasAccessibilityAccess = false
                }
                statusMessage = error.localizedDescription
            } catch {
                AppDiagnostics.windowOperations.error(
                    "Fill failed group=\(group.name, privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .private)"
                )
                statusMessage = String(localized: "The display could not be filled.")
            }
            isPerformingAction = false
        }
    }

    private func perform(
        _ action: WindowAction,
        targetingProcessIdentifier processIdentifier: pid_t?
    ) {
        let targetProcessIdentifier = Int(processIdentifier ?? 0)
        AppDiagnostics.windowOperations.debug(
            "Action invoked name=\(action.name, privacy: .private(mask: .hash)) targetPID=\(targetProcessIdentifier, privacy: .private)"
        )
        refreshEnvironment()
        guard hasAccessibilityAccess else {
            statusMessage = WindowAccessibilityError.permissionRequired.localizedDescription
            return
        }
        guard !isPerformingAction else { return }

        let screens = ScreenService.snapshots()
        let library = settingsStore.library
        let knownLayouts = FixedLayout.allCases.map(\.normalizedRect)
            + library.customLayouts.map(\.normalizedRect)
        monitorCount = screens.count
        guard !screens.isEmpty else {
            statusMessage = WindowAccessibilityError.noUsableScreen.localizedDescription
            return
        }

        isPerformingAction = true
        statusMessage = nil
        Task {
            do {
                try await windowService.perform(
                    action,
                    processIdentifier: processIdentifier,
                    screens: screens,
                    padding: CGFloat(library.layoutPadding),
                    knownLayouts: knownLayouts
                )
                statusMessage = String(localized: "\(action.name) applied.")
            } catch let error as WindowAccessibilityError {
                AppDiagnostics.windowOperations.error(
                    "Action failed name=\(action.name, privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .private)"
                )
                if error == .permissionRequired {
                    hasAccessibilityAccess = false
                }
                statusMessage = error.localizedDescription
            } catch {
                AppDiagnostics.windowOperations.error(
                    "Action failed name=\(action.name, privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .private)"
                )
                statusMessage = String(localized: "The window operation could not be completed.")
            }
            isPerformingAction = false
        }
    }

    func beginDragSession(
        screens: [ScreenSnapshot]
    ) async throws -> WindowDragSnapshot {
        try await windowService.beginDragSession(screens: screens)
    }

    func frame(for dragSession: WindowDragSession) async throws -> CGRect {
        try await windowService.frame(for: dragSession)
    }

    func cancelDragSession(_ dragSession: WindowDragSession) {
        Task {
            await windowService.cancelDragSession(dragSession)
        }
    }

    func perform(
        _ action: WindowAction,
        dragSession: WindowDragSession,
        destinationScreenID: String? = nil
    ) {
        AppDiagnostics.windowOperations.debug(
            "Drag action invoked name=\(action.name, privacy: .private(mask: .hash))"
        )
        refreshEnvironment()
        guard hasAccessibilityAccess else {
            cancelDragSession(dragSession)
            statusMessage = WindowAccessibilityError.permissionRequired.localizedDescription
            return
        }
        guard !isPerformingAction else {
            cancelDragSession(dragSession)
            return
        }

        let screens = ScreenService.snapshots()
        let library = settingsStore.library
        let knownLayouts = FixedLayout.allCases.map(\.normalizedRect)
            + library.customLayouts.map(\.normalizedRect)
        guard !screens.isEmpty else {
            cancelDragSession(dragSession)
            statusMessage = WindowAccessibilityError.noUsableScreen.localizedDescription
            return
        }

        isPerformingAction = true
        statusMessage = nil
        Task {
            do {
                try await windowService.perform(
                    action,
                    dragSession: dragSession,
                    destinationScreenID: destinationScreenID,
                    screens: screens,
                    padding: CGFloat(library.layoutPadding),
                    knownLayouts: knownLayouts
                )
                statusMessage = String(localized: "\(action.name) applied.")
            } catch let error as WindowAccessibilityError {
                AppDiagnostics.windowOperations.error(
                    "Drag action failed name=\(action.name, privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .private)"
                )
                if error == .permissionRequired {
                    hasAccessibilityAccess = false
                }
                statusMessage = error.localizedDescription
            } catch {
                AppDiagnostics.windowOperations.error(
                    "Drag action failed name=\(action.name, privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .private)"
                )
                statusMessage = String(localized: "The dragged window operation could not be completed.")
            }
            isPerformingAction = false
        }
    }

    func disableOptionalOverlays() {
        OptionalOverlaySafety.disableAll()
        Task {
            await windowService.cancelAllDragSessions()
        }
        let saved = settingsStore.disableOptionalPanels()
        statusMessage = saved
            ? String(localized: "Optional overlays are disabled.")
            : String(localized: "Optional overlays are disabled for this session, but the setting could not be saved.")
    }
}

@MainActor
enum OptionalOverlaySafety {
    static let floatingButtonKey = "floatingButtonEnabled"
    static let dragTargetsKey = "dragTargetsEnabled"
    static let greenButtonPopoverKey = "greenButtonPopoverEnabled"

    static func disableAll(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: floatingButtonKey)
        defaults.set(false, forKey: dragTargetsKey)
        defaults.set(false, forKey: greenButtonPopoverKey)
    }
}
