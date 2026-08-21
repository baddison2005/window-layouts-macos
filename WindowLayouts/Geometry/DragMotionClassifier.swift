// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

nonisolated enum DragMotionClassification: Equatable, Sendable {
    case unchanged
    case moving
    case resizing
}

nonisolated enum DragMotionClassifier {
    static let movementThreshold: CGFloat = 2
    static let sizeTolerance: CGFloat = 1

    static func classify(
        from initialFrame: CGRect,
        to currentFrame: CGRect
    ) -> DragMotionClassification {
        guard [
            initialFrame.minX, initialFrame.minY,
            initialFrame.width, initialFrame.height,
            currentFrame.minX, currentFrame.minY,
            currentFrame.width, currentFrame.height,
        ].allSatisfy(\.isFinite) else { return .unchanged }

        let sizeChanged = abs(initialFrame.width - currentFrame.width) > sizeTolerance
            || abs(initialFrame.height - currentFrame.height) > sizeTolerance
        if sizeChanged { return .resizing }

        let originChanged = abs(initialFrame.minX - currentFrame.minX) > movementThreshold
            || abs(initialFrame.minY - currentFrame.minY) > movementThreshold
        return originChanged ? .moving : .unchanged
    }
}
