// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct DragMotionClassifierTests {
    private let initial = CGRect(x: 100, y: 200, width: 800, height: 600)

    @Test func requiresPositionMovementBeyondNoise() {
        #expect(
            DragMotionClassifier.classify(
                from: initial,
                to: initial.offsetBy(dx: 1, dy: -1)
            ) == .unchanged
        )
        #expect(
            DragMotionClassifier.classify(
                from: initial,
                to: initial.offsetBy(dx: 8, dy: 0)
            ) == .moving
        )
    }

    @Test func rejectsInteractiveResizeEvenWhenTheOriginAlsoMoves() {
        #expect(
            DragMotionClassifier.classify(
                from: initial,
                to: CGRect(x: 110, y: 210, width: 790, height: 590)
            ) == .resizing
        )
    }
}
