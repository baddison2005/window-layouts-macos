// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

@MainActor
final class GlobalShortcutManager: ObservableObject {
    @Published private(set) var registrationFailures: [ShortcutRegistrationFailure] = []

    private let settingsStore: SettingsStore
    private let service: GlobalShortcutRegistering
    private let actionHandler: (WindowAction) -> Void
    private let fillScreenHandler: (WindowFillGroup) -> Void
    private var settingsObservation: AnyCancellable?

    convenience init(
        settingsStore: SettingsStore,
        controller: WindowLayoutsController
    ) {
        self.init(
            settingsStore: settingsStore,
            service: CarbonGlobalShortcutService(),
            actionHandler: { [weak controller] action in
                controller?.perform(action)
            },
            fillScreenHandler: { [weak controller] group in
                controller?.fillScreen(using: group)
            }
        )
    }

    init(
        settingsStore: SettingsStore,
        service: GlobalShortcutRegistering,
        actionHandler: @escaping (WindowAction) -> Void,
        fillScreenHandler: @escaping (WindowFillGroup) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.service = service
        self.actionHandler = actionHandler
        self.fillScreenHandler = fillScreenHandler

        service.onAction = { [weak self] actionID in
            self?.perform(actionID)
        }
        settingsObservation = settingsStore.$library.sink { [weak self] library in
            self?.apply(library)
        }
    }

    func retry() {
        apply(settingsStore.library)
    }

    private func apply(_ library: LayoutLibrary) {
        let assignments = Dictionary(
            uniqueKeysWithValues: library.shortcuts.map {
                (ShortcutActionID(rawValue: $0.key), $0.value)
            }
        )
        registrationFailures = service.replaceRegistrations(assignments)
    }

    private func perform(_ actionID: ShortcutActionID) {
        guard let descriptor = ShortcutActionCatalog.descriptor(
            for: actionID,
            in: settingsStore.library
        ) else { return }
        switch descriptor.command {
        case .window(let action):
            actionHandler(action)
        case .fillScreen(let group):
            fillScreenHandler(group)
        }
    }
}
