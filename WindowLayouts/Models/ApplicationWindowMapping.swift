// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum ApplicationWindowRequirement: String, Codable, CaseIterable, Sendable {
    case firstEligibleWindow
    case documentWindow

    var name: String {
        switch self {
        case .firstEligibleWindow:
            String(localized: "First eligible window")
        case .documentWindow:
            String(localized: "Document window")
        }
    }
}

nonisolated struct ApplicationLayoutReference: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case fixed
        case custom
    }

    var kind: Kind
    var identifier: String

    static func fixed(_ layout: FixedLayout) -> Self {
        Self(kind: .fixed, identifier: layout.rawValue)
    }

    static func custom(_ identifier: UUID) -> Self {
        Self(kind: .custom, identifier: identifier.uuidString)
    }

    func action(in library: LayoutLibrary) -> WindowAction? {
        switch kind {
        case .fixed:
            guard let layout = FixedLayout(rawValue: identifier) else { return nil }
            return .fixed(layout)
        case .custom:
            guard let id = UUID(uuidString: identifier),
                  let layout = library.customLayouts.first(where: { $0.id == id }) else {
                return nil
            }
            return .custom(layout)
        }
    }

    func name(in library: LayoutLibrary) -> String? {
        action(in: library)?.name
    }
}

nonisolated struct ApplicationWindowMapping: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var bundleIdentifier: String
    var applicationName: String
    var layout: ApplicationLayoutReference
    var displayIdentifier: String
    var displayName: String
    var windowRequirement: ApplicationWindowRequirement

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        applicationName: String,
        layout: ApplicationLayoutReference,
        displayIdentifier: String,
        displayName: String,
        windowRequirement: ApplicationWindowRequirement = .firstEligibleWindow
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.layout = layout
        self.displayIdentifier = displayIdentifier
        self.displayName = displayName
        self.windowRequirement = windowRequirement
    }
}
