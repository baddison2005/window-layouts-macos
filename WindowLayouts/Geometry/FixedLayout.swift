// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum FixedLayout: String, CaseIterable, Identifiable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case centerTwoThirds
    case rightTwoThirds

    var id: String { rawValue }

    var name: String {
        switch self {
        case .leftHalf: String(localized: "Left Half")
        case .rightHalf: String(localized: "Right Half")
        case .topHalf: String(localized: "Top Half")
        case .bottomHalf: String(localized: "Bottom Half")
        case .topLeft: String(localized: "Top Left")
        case .topRight: String(localized: "Top Right")
        case .bottomLeft: String(localized: "Bottom Left")
        case .bottomRight: String(localized: "Bottom Right")
        case .leftThird: String(localized: "Left Third")
        case .centerThird: String(localized: "Center Third")
        case .rightThird: String(localized: "Right Third")
        case .leftTwoThirds: String(localized: "Left Two Thirds")
        case .centerTwoThirds: String(localized: "Center Two Thirds")
        case .rightTwoThirds: String(localized: "Right Two Thirds")
        }
    }

    var normalizedRect: NormalizedRect {
        let values: (Double, Double, Double, Double) = switch self {
        case .leftHalf: (0, 0, 1 / 2, 1)
        case .rightHalf: (1 / 2, 0, 1 / 2, 1)
        case .topHalf: (0, 0, 1, 1 / 2)
        case .bottomHalf: (0, 1 / 2, 1, 1 / 2)
        case .topLeft: (0, 0, 1 / 2, 1 / 2)
        case .topRight: (1 / 2, 0, 1 / 2, 1 / 2)
        case .bottomLeft: (0, 1 / 2, 1 / 2, 1 / 2)
        case .bottomRight: (1 / 2, 1 / 2, 1 / 2, 1 / 2)
        case .leftThird: (0, 0, 1 / 3, 1)
        case .centerThird: (1 / 3, 0, 1 / 3, 1)
        case .rightThird: (2 / 3, 0, 1 / 3, 1)
        case .leftTwoThirds: (0, 0, 2 / 3, 1)
        case .centerTwoThirds: (1 / 6, 0, 2 / 3, 1)
        case .rightTwoThirds: (1 / 3, 0, 2 / 3, 1)
        }

        // Every tuple above is a compile-time-controlled valid rectangle.
        return try! NormalizedRect(
            x: values.0,
            y: values.1,
            width: values.2,
            height: values.3
        )
    }
}
