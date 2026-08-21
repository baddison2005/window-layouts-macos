// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum NormalizedRectError: Error, Equatable, Sendable {
    case nonFiniteValue
    case nonPositiveSize
    case outsideUnitBounds
}

/// A platform-neutral rectangle whose origin is measured from the top-left.
nonisolated struct NormalizedRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) throws {
        let values = [x, y, width, height]
        guard values.allSatisfy(\.isFinite) else {
            throw NormalizedRectError.nonFiniteValue
        }
        guard width > 0, height > 0 else {
            throw NormalizedRectError.nonPositiveSize
        }

        let epsilon = 0.000_001
        guard x >= 0,
              y >= 0,
              x + width <= 1 + epsilon,
              y + height <= 1 + epsilon else {
            throw NormalizedRectError.outsideUnitBounds
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)

        do {
            try self.init(x: x, y: y, width: width, height: height)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Normalized rectangles must be finite, positive, and contained in 0...1.",
                    underlyingError: error
                )
            )
        }
    }
}
