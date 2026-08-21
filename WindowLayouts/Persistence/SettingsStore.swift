// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import OSLog

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var library: LayoutLibrary
    @Published private(set) var loadWarning: String?

    private let persistence: LayoutLibraryPersistence

    init(persistence: LayoutLibraryPersistence = .applicationSupport()) {
        self.persistence = persistence
        let result = persistence.load()
        self.library = result.library
        self.loadWarning = result.warning
    }

    func apply(_ candidate: LayoutLibrary) throws {
        let validated = try candidate.validated()
        try persistence.save(validated)
        library = validated
        loadWarning = nil
    }

    func reload() {
        let result = persistence.load()
        library = result.library
        loadWarning = result.warning
    }

    /// Emergency, best-effort runtime shutdown. Publish the disabled state even
    /// if persistence fails so an optional panel can never trap input.
    @discardableResult
    func disableOptionalPanels() -> Bool {
        var disabled = library
        disabled.greenButtonPanelEnabled = false
        disabled.dragTargetsEnabled = false
        library = disabled
        do {
            try persistence.save(disabled)
            return true
        } catch {
            AppDiagnostics.persistence.error(
                "The emergency overlay preference could not be saved: \(String(describing: error), privacy: .private)"
            )
            return false
        }
    }
}
