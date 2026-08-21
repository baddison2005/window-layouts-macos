// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

nonisolated enum LayoutPanelSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small
    case standard = "default"
    case big
    case extraBig

    var id: String { rawValue }

    var name: String {
        switch self {
        case .small: String(localized: "Small")
        case .standard: String(localized: "Default")
        case .big: String(localized: "Big")
        case .extraBig: String(localized: "Extra Big")
        }
    }

    /// Compact menu dimensions in logical points, never physical pixels.
    var panelSize: CGSize {
        switch self {
        case .small: CGSize(width: 260, height: 390)
        case .standard: CGSize(width: 310, height: 500)
        case .big: CGSize(width: 350, height: 570)
        case .extraBig: CGSize(width: 410, height: 680)
        }
    }
}
