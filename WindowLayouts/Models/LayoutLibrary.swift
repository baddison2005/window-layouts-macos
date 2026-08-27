// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum MenuGroupIdentifier: String, CaseIterable, Identifiable, Sendable {
    case halves
    case quarters
    case thirds
    case twoThirds
    case custom
    case window

    var id: String { rawValue }

    var name: String {
        switch self {
        case .halves: String(localized: "Halves")
        case .quarters: String(localized: "Quarters")
        case .thirds: String(localized: "Thirds")
        case .twoThirds: String(localized: "Two Thirds")
        case .custom: String(localized: "Custom")
        case .window: String(localized: "Window")
        }
    }

    var fixedLayouts: [FixedLayout] {
        switch self {
        case .halves:
            [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
        case .quarters:
            [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .thirds:
            [.leftThird, .centerThird, .rightThird]
        case .twoThirds:
            [.leftTwoThirds, .centerTwoThirds, .rightTwoThirds]
        case .custom, .window:
            []
        }
    }
}

nonisolated struct LayoutDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var normalizedRect: NormalizedRect
    var groupID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        normalizedRect: NormalizedRect,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.normalizedRect = normalizedRect
        self.groupID = groupID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case x
        case y
        case width
        case height
        case groupID = "groupId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        normalizedRect = try NormalizedRect(
            x: container.decode(Double.self, forKey: .x),
            y: container.decode(Double.self, forKey: .y),
            width: container.decode(Double.self, forKey: .width),
            height: container.decode(Double.self, forKey: .height)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(normalizedRect.x, forKey: .x)
        try container.encode(normalizedRect.y, forKey: .y)
        try container.encode(normalizedRect.width, forKey: .width)
        try container.encode(normalizedRect.height, forKey: .height)
        try container.encodeIfPresent(groupID, forKey: .groupID)
    }
}

nonisolated struct LayoutGroup: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

nonisolated enum LayoutLibraryValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)
    case tooManyLayouts(Int)
    case duplicateLayoutID
    case duplicateGroupID
    case emptyLayoutName
    case emptyGroupName
    case invalidGroupReference
    case invalidMenuGroupOrder
    case invalidPadding
    case invalidShortcut
    case duplicateShortcut
    case invalidShortcutAction

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            String(localized: "The layout library uses an unsupported schema version.")
        case .tooManyLayouts:
            String(localized: "A layout library may contain no more than 20 custom layouts.")
        case .duplicateLayoutID:
            String(localized: "Custom layout identifiers must be unique.")
        case .duplicateGroupID:
            String(localized: "Custom group identifiers must be unique.")
        case .emptyLayoutName:
            String(localized: "Every custom layout must have a name.")
        case .emptyGroupName:
            String(localized: "Every custom group must have a name.")
        case .invalidGroupReference:
            String(localized: "A custom layout refers to a group that does not exist.")
        case .invalidMenuGroupOrder:
            String(localized: "The menu group order is incomplete or contains duplicates.")
        case .invalidPadding:
            String(localized: "Layout padding must be between 0 and 200 logical points.")
        case .invalidShortcut:
            String(localized: "A global shortcut is invalid.")
        case .duplicateShortcut:
            String(localized: "The same global shortcut cannot be assigned to more than one action.")
        case .invalidShortcutAction:
            String(localized: "A global shortcut refers to an action that does not exist.")
        }
    }
}

nonisolated struct LayoutLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 6
    static let maximumCustomLayouts = 20
    static let maximumNameLength = 80
    static let defaultMenuGroupOrder = MenuGroupIdentifier.allCases.map(\.rawValue)

    var schemaVersion: Int
    var customLayouts: [LayoutDefinition]
    var customGroups: [LayoutGroup]
    var menuGroupOrder: [String]
    var layoutPadding: Double
    var shortcuts: [String: KeyboardShortcut]
    var launchAtLogin: Bool
    var showDockIcon: Bool
    var greenButtonPanelEnabled: Bool
    var layoutPanelSize: LayoutPanelSize
    var dragTargetsEnabled: Bool
    var dragTargetPlacement: DragTargetPlacementStyle
    var showAllDragTargets: Bool
    var showAllTopDragTargets: Bool
    var experimentalSpaceMovementEnabled: Bool
    var missionControlSpaceShortcutsConfirmed: Bool

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        customLayouts: [LayoutDefinition] = [],
        customGroups: [LayoutGroup] = [],
        menuGroupOrder: [String] = Self.defaultMenuGroupOrder,
        layoutPadding: Double = 0,
        shortcuts: [String: KeyboardShortcut] = [:],
        launchAtLogin: Bool = false,
        showDockIcon: Bool = false,
        greenButtonPanelEnabled: Bool = false,
        layoutPanelSize: LayoutPanelSize = .standard,
        dragTargetsEnabled: Bool = false,
        dragTargetPlacement: DragTargetPlacementStyle = .zones,
        showAllDragTargets: Bool = false,
        showAllTopDragTargets: Bool = false,
        experimentalSpaceMovementEnabled: Bool = false,
        missionControlSpaceShortcutsConfirmed: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.customLayouts = customLayouts
        self.customGroups = customGroups
        self.menuGroupOrder = menuGroupOrder
        self.layoutPadding = layoutPadding
        self.shortcuts = shortcuts
        self.launchAtLogin = launchAtLogin
        self.showDockIcon = showDockIcon
        self.greenButtonPanelEnabled = greenButtonPanelEnabled
        self.layoutPanelSize = layoutPanelSize
        self.dragTargetsEnabled = dragTargetsEnabled
        self.dragTargetPlacement = dragTargetPlacement
        self.showAllDragTargets = showAllDragTargets
        self.showAllTopDragTargets = showAllTopDragTargets
        self.experimentalSpaceMovementEnabled = experimentalSpaceMovementEnabled
        self.missionControlSpaceShortcutsConfirmed = missionControlSpaceShortcutsConfirmed
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case customLayouts
        case customGroups
        case menuGroupOrder
        case layoutPadding
        case shortcuts
        case launchAtLogin
        case showDockIcon
        case greenButtonPanelEnabled
        case layoutPanelSize
        case dragTargetsEnabled
        case dragTargetPlacement
        case showAllDragTargets
        case showAllTopDragTargets
        case experimentalSpaceMovementEnabled
        case missionControlSpaceShortcutsConfirmed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        customLayouts = try container.decodeIfPresent(
            [LayoutDefinition].self,
            forKey: .customLayouts
        ) ?? []
        customGroups = try container.decodeIfPresent(
            [LayoutGroup].self,
            forKey: .customGroups
        ) ?? []
        menuGroupOrder = try container.decodeIfPresent(
            [String].self,
            forKey: .menuGroupOrder
        ) ?? Self.defaultMenuGroupOrder
        layoutPadding = try container.decodeIfPresent(
            Double.self,
            forKey: .layoutPadding
        ) ?? 0
        shortcuts = try container.decodeIfPresent(
            [String: KeyboardShortcut].self,
            forKey: .shortcuts
        ) ?? [:]
        launchAtLogin = try container.decodeIfPresent(
            Bool.self,
            forKey: .launchAtLogin
        ) ?? false
        showDockIcon = try container.decodeIfPresent(
            Bool.self,
            forKey: .showDockIcon
        ) ?? false
        greenButtonPanelEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .greenButtonPanelEnabled
        ) ?? false
        layoutPanelSize = try container.decodeIfPresent(
            LayoutPanelSize.self,
            forKey: .layoutPanelSize
        ) ?? .standard
        dragTargetsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .dragTargetsEnabled
        ) ?? false
        dragTargetPlacement = try container.decodeIfPresent(
            DragTargetPlacementStyle.self,
            forKey: .dragTargetPlacement
        ) ?? .zones
        showAllDragTargets = try container.decodeIfPresent(
            Bool.self,
            forKey: .showAllDragTargets
        ) ?? false
        showAllTopDragTargets = try container.decodeIfPresent(
            Bool.self,
            forKey: .showAllTopDragTargets
        ) ?? false
        experimentalSpaceMovementEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .experimentalSpaceMovementEnabled
        ) ?? false
        missionControlSpaceShortcutsConfirmed = try container.decodeIfPresent(
            Bool.self,
            forKey: .missionControlSpaceShortcutsConfirmed
        ) ?? false
    }

    var orderedMenuGroups: [MenuGroupIdentifier] {
        menuGroupOrder.compactMap(MenuGroupIdentifier.init(rawValue:))
    }

    func validated() throws -> LayoutLibrary {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw LayoutLibraryValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard customLayouts.count <= Self.maximumCustomLayouts else {
            throw LayoutLibraryValidationError.tooManyLayouts(customLayouts.count)
        }
        guard layoutPadding.isFinite,
              layoutPadding >= 0,
              layoutPadding <= Double(LayoutEngine.maximumPadding) else {
            throw LayoutLibraryValidationError.invalidPadding
        }

        let groupIDs = customGroups.map(\.id)
        guard Set(groupIDs).count == groupIDs.count else {
            throw LayoutLibraryValidationError.duplicateGroupID
        }
        let layoutIDs = customLayouts.map(\.id)
        guard Set(layoutIDs).count == layoutIDs.count else {
            throw LayoutLibraryValidationError.duplicateLayoutID
        }

        let supportedMenuGroups = Set(Self.defaultMenuGroupOrder)
        guard menuGroupOrder.count == supportedMenuGroups.count,
              Set(menuGroupOrder) == supportedMenuGroups else {
            throw LayoutLibraryValidationError.invalidMenuGroupOrder
        }

        var result = self
        result.schemaVersion = Self.currentSchemaVersion
        for index in result.customGroups.indices {
            let name = result.customGroups[index].name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw LayoutLibraryValidationError.emptyGroupName
            }
            result.customGroups[index].name = String(name.prefix(Self.maximumNameLength))
        }

        let validGroupIDs = Set(groupIDs)
        for index in result.customLayouts.indices {
            let name = result.customLayouts[index].name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw LayoutLibraryValidationError.emptyLayoutName
            }
            if let groupID = result.customLayouts[index].groupID,
               !validGroupIDs.contains(groupID) {
                throw LayoutLibraryValidationError.invalidGroupReference
            }
            result.customLayouts[index].name = String(name.prefix(Self.maximumNameLength))
        }

        let validActionIDs = Set(
            ShortcutActionCatalog.descriptors(for: result).map(\.id.rawValue)
        )
        var usedShortcuts: Set<KeyboardShortcutIdentity> = []
        for (actionID, shortcut) in result.shortcuts {
            guard validActionIDs.contains(actionID) else {
                throw LayoutLibraryValidationError.invalidShortcutAction
            }
            let validatedShortcut: KeyboardShortcut
            do {
                validatedShortcut = try shortcut.validated()
            } catch {
                throw LayoutLibraryValidationError.invalidShortcut
            }
            if actionID.hasPrefix("space."),
               validatedShortcut.isMissionControlSpaceNavigationShortcut {
                throw LayoutLibraryValidationError.invalidShortcut
            }
            guard usedShortcuts.insert(validatedShortcut.identity).inserted else {
                throw LayoutLibraryValidationError.duplicateShortcut
            }
            result.shortcuts[actionID] = validatedShortcut
        }

        result.layoutPadding = result.layoutPadding.rounded()
        return result
    }
}
