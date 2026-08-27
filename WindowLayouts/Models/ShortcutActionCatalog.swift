// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated struct ShortcutActionID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }
}

nonisolated enum ShortcutActionCategory: String, CaseIterable, Identifiable, Sendable {
    case fixedLayouts
    case customLayouts
    case fillTargetDisplay
    case windowActions
    case experimentalSpaceMovement

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fixedLayouts: String(localized: "Fixed Layouts")
        case .customLayouts: String(localized: "Custom Layouts")
        case .fillTargetDisplay: String(localized: "Fill Target Display")
        case .windowActions: String(localized: "Window Actions")
        case .experimentalSpaceMovement: String(localized: "Experimental Space Movement")
        }
    }
}

nonisolated enum ShortcutCommand: Equatable, Sendable {
    case window(WindowAction)
    case fillScreen(WindowFillGroup)
    case moveToSpace(SpaceMovementDirection)
}

nonisolated struct ShortcutActionDescriptor: Identifiable, Sendable {
    let id: ShortcutActionID
    let label: String
    let category: ShortcutActionCategory
    let command: ShortcutCommand
}

nonisolated enum ShortcutActionCatalog {
    static func descriptors(for library: LayoutLibrary) -> [ShortcutActionDescriptor] {
        let fixed = FixedLayout.allCases.map { layout in
            ShortcutActionDescriptor(
                id: layout.shortcutActionID,
                label: layout.name,
                category: .fixedLayouts,
                command: .window(.fixed(layout))
            )
        }
        let custom = library.customLayouts.map { layout in
            ShortcutActionDescriptor(
                id: layout.shortcutActionID,
                label: layout.name,
                category: .customLayouts,
                command: .window(.custom(layout))
            )
        }
        let fillDisplay = WindowFillGroupCatalog.shortcutGroups(for: library).map { group in
            ShortcutActionDescriptor(
                id: group.shortcutActionID,
                label: group.name,
                category: .fillTargetDisplay,
                command: .fillScreen(group)
            )
        }
        let window = [
            ShortcutActionDescriptor(
                id: ShortcutActionID(rawValue: "window.center"),
                label: "Center",
                category: .windowActions,
                command: .window(.center)
            ),
            ShortcutActionDescriptor(
                id: ShortcutActionID(rawValue: "window.maximize"),
                label: "Maximize",
                category: .windowActions,
                command: .window(.maximize)
            ),
            ShortcutActionDescriptor(
                id: ShortcutActionID(rawValue: "window.restore"),
                label: "Restore",
                category: .windowActions,
                command: .window(.restore)
            ),
            ShortcutActionDescriptor(
                id: ShortcutActionID(rawValue: "monitor.previous"),
                label: "Move to Previous Monitor",
                category: .windowActions,
                command: .window(.moveToPreviousMonitor)
            ),
            ShortcutActionDescriptor(
                id: ShortcutActionID(rawValue: "monitor.next"),
                label: "Move to Next Monitor",
                category: .windowActions,
                command: .window(.moveToNextMonitor)
            ),
        ]
        let spaces = SpaceMovementDirection.allCases.map { direction in
            ShortcutActionDescriptor(
                id: direction.shortcutActionID,
                label: direction.name,
                category: .experimentalSpaceMovement,
                command: .moveToSpace(direction)
            )
        }
        return fixed + custom + fillDisplay + window + spaces
    }

    static func descriptor(
        for id: ShortcutActionID,
        in library: LayoutLibrary
    ) -> ShortcutActionDescriptor? {
        descriptors(for: library).first { $0.id == id }
    }

    static func conflictingActionID(
        for shortcut: KeyboardShortcut,
        excluding excludedID: ShortcutActionID,
        in library: LayoutLibrary
    ) -> ShortcutActionID? {
        library.shortcuts.first { assignment in
            assignment.key != excludedID.rawValue
                && assignment.value.identity == shortcut.identity
        }.map { ShortcutActionID(rawValue: $0.key) }
    }
}

nonisolated extension SpaceMovementDirection {
    var shortcutActionID: ShortcutActionID {
        ShortcutActionID(rawValue: "space.\(rawValue)")
    }
}

nonisolated extension FixedLayout {
    var shortcutActionID: ShortcutActionID {
        ShortcutActionID(rawValue: "fixed.\(rawValue)")
    }
}

nonisolated extension LayoutDefinition {
    var shortcutActionID: ShortcutActionID {
        ShortcutActionID(rawValue: "custom.\(id.uuidString.lowercased())")
    }
}

nonisolated extension LayoutGroup {
    var fillShortcutActionID: ShortcutActionID {
        ShortcutActionID(rawValue: "fill.custom.\(id.uuidString.lowercased())")
    }
}

nonisolated extension WindowFillGroup {
    var shortcutActionID: ShortcutActionID {
        ShortcutActionID(rawValue: "fill.\(id.lowercased())")
    }
}
