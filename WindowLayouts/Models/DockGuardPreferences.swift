// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics

nonisolated enum DockGuardBypassModifier: String, Codable, CaseIterable, Sendable {
    case option, shift, control, command

    var name: String { rawValue.capitalized }
    var flag: CGEventFlags {
        switch self {
        case .option: .maskAlternate
        case .shift: .maskShift
        case .control: .maskControl
        case .command: .maskCommand
        }
    }
}

nonisolated struct DockGuardPreferences: Codable, Equatable, Sendable {
    var enabled = false
    // nil follows the built-in display, rather than whichever display is main.
    var preferredDisplayID: String?
    var bypassModifier: DockGuardBypassModifier = .option
    var strength: DockGuardStrength = .gentle

    init(enabled: Bool = false, preferredDisplayID: String? = nil,
         bypassModifier: DockGuardBypassModifier = .option,
         strength: DockGuardStrength = .gentle) {
        self.enabled = enabled
        self.preferredDisplayID = preferredDisplayID
        self.bypassModifier = bypassModifier
        self.strength = strength
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, preferredDisplayID, bypassModifier, strength
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        preferredDisplayID = try values.decodeIfPresent(String.self, forKey: .preferredDisplayID)
        bypassModifier = try values.decodeIfPresent(DockGuardBypassModifier.self, forKey: .bypassModifier) ?? .option
        strength = try values.decodeIfPresent(DockGuardStrength.self, forKey: .strength) ?? .gentle
    }
}

nonisolated enum DockGuardStrength: String, Codable, CaseIterable, Sendable {
    case gentle, strong
    var name: String {
        switch self {
        case .gentle: "Gentle (idle pointer only)"
        case .strong: "Strong (guard incoming movement)"
        }
    }
}
