// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// All coordinates use global Quartz logical points, with Y increasing down.
nonisolated struct MenuBarRevealDisplay: Equatable {
    let frame: CGRect
    let topAreas: [CGRect]
    let menuBarHeight: CGFloat

    func containsActivationPoint(_ pointer: CGPoint, distance: Int) -> Bool {
        frame.contains(pointer)
            && pointer.y - frame.minY <= CGFloat(distance)
            && pointer.x >= frame.minX + 24 && pointer.x < frame.maxX - 24
            && topAreas.contains { pointer.x >= $0.minX + 2 && pointer.x < $0.maxX - 2 }
    }

    func containsHoldPoint(_ pointer: CGPoint, distance: Int) -> Bool {
        frame.contains(pointer)
            && pointer.y - frame.minY <= max(menuBarHeight, CGFloat(distance))
    }
}

nonisolated struct MenuBarRevealPolicy {
    static let dwell: TimeInterval = 0.25
    private static let retryDelay: TimeInterval = 0.4

    private struct Hover {
        let display: CGRect
        let anchor: CGPoint
        let since: TimeInterval
        var attempts = 0
        var nextAttemptAt: TimeInterval = 0
    }

    private var hover: Hover?
    private var leftMenuBarAt: TimeInterval?

    mutating func hoverReady(
        pointer: CGPoint, time: TimeInterval, display: MenuBarRevealDisplay?,
        distance: Int, inputInUse: Bool
    ) -> Bool {
        guard !inputInUse, let display, display.containsActivationPoint(pointer, distance: distance) else {
            hover = nil
            return false
        }

        if let hover, hover.display == display.frame,
           hypot(hover.anchor.x - pointer.x, hover.anchor.y - pointer.y) <= 1 {
            return hover.attempts < 2 && time >= hover.nextAttemptAt && time - hover.since >= Self.dwell
        }
        hover = Hover(display: display.frame, anchor: pointer, since: time)
        return false
    }

    mutating func recordRevealAttempt(at time: TimeInterval, canRetry: Bool = false) {
        hover?.attempts += 1
        hover?.nextAttemptAt = canRetry ? time + Self.retryDelay : .infinity
    }

    mutating func allowRetryAfterDismissal(on display: CGRect, at time: TimeInterval) {
        guard hover?.display == display, hover?.attempts == 1 else { return }
        hover?.nextAttemptAt = time + Self.retryDelay
    }

    mutating func resetHover() {
        hover = nil
    }

    mutating func resetReleaseDelay() {
        leftMenuBarAt = nil
    }

    mutating func shouldRelease(pointerInHoldZone: Bool, time: TimeInterval, delay: Int) -> Bool {
        guard !pointerInHoldZone else {
            leftMenuBarAt = nil
            return false
        }

        let departure = leftMenuBarAt ?? time
        leftMenuBarAt = departure
        return time - departure >= TimeInterval(delay)
    }
}
