// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

nonisolated struct WindowFrameDescriptor: Equatable, Sendable {
    let processIdentifier: pid_t
    let frame: CGRect
}

nonisolated enum VisibleWindowMatching {
    static let frameTolerance: CGFloat = 12

    /// Returns AX candidate indices in the front-to-back order reported by the
    /// public Core Graphics on-screen window list. Each AX window is consumed
    /// at most once, which prevents an identical off-Space AX frame from also
    /// matching the one visible Core Graphics window.
    static func candidateIndices(
        for visibleWindows: [WindowFrameDescriptor],
        among candidates: [WindowFrameDescriptor],
        tolerance: CGFloat = frameTolerance
    ) -> [Int] {
        var unused = Set(candidates.indices)
        var result: [Int] = []

        for visible in visibleWindows {
            let match = unused
                .filter {
                    candidates[$0].processIdentifier == visible.processIdentifier
                        && framesMatch(
                            candidates[$0].frame,
                            visible.frame,
                            tolerance: tolerance
                        )
                }
                .min {
                    let firstDistance = frameDistance(
                        candidates[$0].frame,
                        visible.frame
                    )
                    let secondDistance = frameDistance(
                        candidates[$1].frame,
                        visible.frame
                    )
                    if firstDistance != secondDistance {
                        return firstDistance < secondDistance
                    }
                    return $0 < $1
                }
            guard let match else { continue }
            unused.remove(match)
            result.append(match)
        }
        return result
    }

    static func layoutIndices(windowCount: Int, layoutCount: Int) -> [Int] {
        guard windowCount > 0, layoutCount > 0 else { return [] }
        return (0..<windowCount).map { $0 % layoutCount }
    }

    private static func framesMatch(
        _ first: CGRect,
        _ second: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.maxX - second.maxX) <= tolerance
            && abs(first.maxY - second.maxY) <= tolerance
    }

    private static func frameDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        abs(first.minX - second.minX)
            + abs(first.minY - second.minY)
            + abs(first.maxX - second.maxX)
            + abs(first.maxY - second.maxY)
    }
}
