// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

struct NormalizedRectTests {
    @Test func validatesBoundsAndFiniteValues() throws {
        let valid = try NormalizedRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        #expect(valid.width == 0.5)

        #expect(throws: NormalizedRectError.nonFiniteValue) {
            try NormalizedRect(x: .nan, y: 0, width: 1, height: 1)
        }
        #expect(throws: NormalizedRectError.nonPositiveSize) {
            try NormalizedRect(x: 0, y: 0, width: 0, height: 1)
        }
        #expect(throws: NormalizedRectError.outsideUnitBounds) {
            try NormalizedRect(x: 0.75, y: 0, width: 0.5, height: 1)
        }
    }

    @Test func decodingRejectsInvalidGeometry() throws {
        let data = Data(#"{"x":0,"y":0,"width":2,"height":1}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NormalizedRect.self, from: data)
        }
    }

    @Test func fixedLayoutsAreStableAndValid() {
        #expect(FixedLayout.allCases.count == 14)
        #expect(FixedLayout.leftHalf.normalizedRect == (
            try! NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        ))
        #expect(FixedLayout.centerTwoThirds.normalizedRect == (
            try! NormalizedRect(x: 1 / 6, y: 0, width: 2 / 3, height: 1)
        ))
    }
}
