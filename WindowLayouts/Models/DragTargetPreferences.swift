// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum DragTargetPlacementStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case zones
    case top

    var id: String { rawValue }

    var name: String {
        switch self {
        case .zones: String(localized: "Layout zone centers")
        case .top: String(localized: "Top-center strip")
        }
    }
}
