// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import OSLog

nonisolated struct LayoutLibraryLoadResult: Sendable {
    let library: LayoutLibrary
    let warning: String?
}

nonisolated struct LayoutLibraryPersistence: Sendable {
    let fileURL: URL

    static func applicationSupport() -> LayoutLibraryPersistence {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return LayoutLibraryPersistence(
            fileURL: applicationSupport
                .appendingPathComponent("Window Layouts", isDirectory: true)
                .appendingPathComponent("layout-library.json", isDirectory: false)
        )
    }

    func load() -> LayoutLibraryLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LayoutLibraryLoadResult(library: LayoutLibrary(), warning: nil)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(LayoutLibrary.self, from: data)
            return LayoutLibraryLoadResult(
                library: try decoded.validated(),
                warning: nil
            )
        } catch {
            AppDiagnostics.persistence.error(
                "The saved layout library could not be loaded: \(String(describing: error), privacy: .private)"
            )
            return LayoutLibraryLoadResult(
                library: LayoutLibrary(),
                warning: String(localized: "The saved layout library could not be loaded. Safe defaults are active and the original file was left unchanged.")
            )
        }
    }

    func save(_ library: LayoutLibrary) throws {
        let validated = try library.validated()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try data.write(to: fileURL, options: .atomic)
    }
}
