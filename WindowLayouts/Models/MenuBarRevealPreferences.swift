// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated struct MenuBarRevealPreferences: Codable, Equatable, Sendable {
    static let activationDistances = 4...50
    static let hideDelays = 0...10

    var enabled = false
    var activationDistance = 10
    var hideDelaySeconds = 3

    init(enabled: Bool = false, activationDistance: Int = 10, hideDelaySeconds: Int = 3) {
        self.enabled = enabled
        self.activationDistance = activationDistance
        self.hideDelaySeconds = hideDelaySeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        activationDistance = try values.decodeIfPresent(Int.self, forKey: .activationDistance) ?? activationDistance
        hideDelaySeconds = try values.decodeIfPresent(Int.self, forKey: .hideDelaySeconds) ?? hideDelaySeconds
    }
}
