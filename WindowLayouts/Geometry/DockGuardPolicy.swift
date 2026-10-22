// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation

/// Pure geometry in global Quartz logical points (positive Y points down).
/// Shared bottom edges are always exempt, including idle/zero-delta samples.
nonisolated struct DockGuardPolicy {
    static let edgeBand: CGFloat = 2
    static let inwardOffset: CGFloat = 6
    static let dwell: TimeInterval = 0.15
    private var candidateScreen: String?
    private var candidateSince: TimeInterval = 0
    private var previousPoint: CGPoint?
    private var cooldownUntil: TimeInterval = 0

    mutating func reset() {
        candidateScreen = nil
        previousPoint = nil
    }

    mutating func inputReleased(at time: TimeInterval) {
        reset()
        cooldownUntil = time + 0.5
    }

    /// Shared edges are geometric exemptions; pointer speed/direction must
    /// never determine whether a user can cross a display boundary.
    static func isSharedBottomEdge(point: CGPoint, screen: ScreenSnapshot, screens: [ScreenSnapshot]) -> Bool {
        screens.contains { other in
            other.id != screen.id
                && abs(other.frame.minY - screen.frame.maxY) <= 1
                && point.x >= other.frame.minX - 8
                && point.x <= other.frame.maxX + 8
        }
    }

    static func sameDisplayGeometry(_ a: [ScreenSnapshot], _ b: [ScreenSnapshot]) -> Bool {
        a.count == b.count && a.allSatisfy { left in
            b.contains { $0.id == left.id && $0.persistentID == left.persistentID && $0.frame == left.frame }
        }
    }

    /// Called before the Dock receives a mouse-movement event. Only exposed
    /// sections of a nonpreferred display's bottom edge are adjusted.
    func strongCorrection(
        point: CGPoint, deltaY: CGFloat, now: TimeInterval,
        screens: [ScreenSnapshot], preferredID: String?, mouseIsDown: Bool, bypass: Bool
    ) -> CGPoint? {
        guard let preferredID, screens.contains(where: { $0.id == preferredID }),
              !mouseIsDown, !bypass, now >= cooldownUntil,
              point.x.isFinite, point.y.isFinite, deltaY.isFinite,
              let screen = screens.first(where: { $0.frame.contains(point) }),
              screen.id != preferredID,
              point.y >= screen.frame.maxY - Self.edgeBand else { return nil }
        guard !Self.isSharedBottomEdge(point: point, screen: screen, screens: screens) else { return nil }
        return CGPoint(x: point.x, y: screen.frame.maxY - Self.inwardOffset)
    }

    mutating func correction(
        point: CGPoint, now: TimeInterval, screens: [ScreenSnapshot],
        preferredID: String?, mouseIsDown: Bool, bypass: Bool
    ) -> CGPoint? {
        guard let preferredID, screens.contains(where: { $0.id == preferredID }),
              !mouseIsDown, !bypass, now >= cooldownUntil,
              point.x.isFinite, point.y.isFinite,
              let screen = screens.first(where: { $0.frame.contains(point) }),
              screen.id != preferredID,
              point.y >= screen.frame.maxY - Self.edgeBand else {
            reset()
            return nil
        }
        guard !Self.isSharedBottomEdge(point: point, screen: screen, screens: screens) else {
            reset(); return nil
        }

        let moved = previousPoint.map { hypot(point.x - $0.x, point.y - $0.y) > 0.01 } ?? true
        previousPoint = point
        if candidateScreen != screen.id || moved {
            candidateScreen = screen.id
            candidateSince = now
            return nil
        }
        guard now - candidateSince >= Self.dwell else { return nil }
        reset()
        return CGPoint(x: point.x, y: screen.frame.maxY - Self.inwardOffset)
    }
}
