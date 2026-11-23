// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing
@testable import WindowLayouts

struct MenuBarRevealPolicyTests {
    private let display = CGRect(x: -200, y: 100, width: 1200, height: 800)

    private func sample(
        _ policy: inout MenuBarRevealPolicy, x: CGFloat = 150, y: CGFloat,
        time: TimeInterval, busy: Bool = false, areas: [CGRect]? = nil,
        screen: CGRect? = nil, distance: Int = 10
    ) -> Bool {
        let frame = screen ?? display
        return policy.hoverReady(
            pointer: CGPoint(x: x, y: y), time: time,
            display: MenuBarRevealDisplay(frame: frame, topAreas: areas ?? [frame], menuBarHeight: 24),
            distance: distance, inputInUse: busy
        )
    }

    @Test func approachingFromBelowRevealsOncePerVisit() {
        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: 115, time: 0))
        #expect(!sample(&policy, y: 107, time: 0.1))
        #expect(!sample(&policy, y: 107, time: 0.3))
        #expect(sample(&policy, y: 107, time: 0.4))
        policy.recordRevealAttempt(at: 0.4)
        #expect(!sample(&policy, y: 107, time: 1))
        #expect(!sample(&policy, y: 107, time: 2))
        #expect(!sample(&policy, y: 115, time: 3))
        #expect(!sample(&policy, y: 100, time: 4))
        #expect(sample(&policy, y: 100, time: 5))
    }

    @Test func releaseDelayStartsOnDepartureAndRestartsAfterReentry() {
        var policy = MenuBarRevealPolicy()
        #expect(!release(&policy, inside: true, time: 1))
        #expect(!release(&policy, inside: true, time: 10))
        #expect(!release(&policy, inside: false, time: 11))
        #expect(!release(&policy, inside: true, time: 13))
        #expect(!release(&policy, inside: false, time: 15))
        #expect(!release(&policy, inside: false, time: 17.9))
        #expect(release(&policy, inside: false, time: 18))
    }

    @Test func zeroDelayReleasesAsSoonAsPointerLeaves() {
        var policy = MenuBarRevealPolicy()
        #expect(!release(&policy, inside: true, time: 1, delay: 0))
        #expect(release(&policy, inside: false, time: 2, delay: 0))
    }

    private func release(
        _ policy: inout MenuBarRevealPolicy, inside: Bool, time: TimeInterval, delay: Int = 3
    ) -> Bool {
        policy.shouldRelease(pointerInHoldZone: inside, time: time, delay: delay)
    }

    @Test func movingAcrossInEitherDirectionDoesNotReveal() {
        var policy = MenuBarRevealPolicy()
        for (index, y) in [95.0, 101, 104, 107, 110, 114, 110, 107, 104, 101, 98].enumerated() {
            #expect(!sample(&policy, y: y, time: Double(index) * 0.1))
        }
        // Crossing remains uninterrupted. A new stationary pause is intentional.
        #expect(!sample(&policy, y: 105, time: 2))
        #expect(sample(&policy, y: 105, time: 3))
    }

    @Test func externalDisplayUsesTheSameFiftyPointActivationZone() {
        let external = CGRect(x: -550, y: -800, width: 1900, height: 900)
        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: -749, time: 0, screen: external, distance: 50))
        #expect(!sample(&policy, y: -749, time: 1, screen: external, distance: 50))
        #expect(!sample(&policy, y: -750, time: 2, screen: external, distance: 50))
        #expect(sample(&policy, y: -750, time: 3, screen: external, distance: 50))
        #expect(!sample(&policy, y: 150, time: 4, distance: 50))
        #expect(sample(&policy, y: 150, time: 5, distance: 50))
    }

    @Test func holdZoneStaysOnItsDisplayAndIncludesTheActivationDistance() {
        let target = MenuBarRevealDisplay(frame: display, topAreas: [display], menuBarHeight: 32)
        #expect(target.containsHoldPoint(CGPoint(x: 150, y: 130), distance: 10))
        #expect(target.containsHoldPoint(CGPoint(x: 150, y: 149), distance: 50))
        #expect(!target.containsHoldPoint(CGPoint(x: 150, y: 151), distance: 50))
        #expect(!target.containsHoldPoint(CGPoint(x: 150, y: 99), distance: 50))
        #expect(!target.containsHoldPoint(CGPoint(x: 1001, y: 110), distance: 50))
    }

    @Test func secondDisplayHoverStaysReadyWhileTheFirstDelayRuns() {
        let external = CGRect(x: -550, y: -800, width: 1900, height: 900)
        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: 107, time: 0))
        #expect(sample(&policy, y: 107, time: 0.3))
        policy.recordRevealAttempt(at: 0.3)
        #expect(!release(&policy, inside: false, time: 1))

        #expect(!sample(&policy, y: -795, time: 2, screen: external))
        #expect(sample(&policy, y: -795, time: 2.3, screen: external))
        #expect(!release(&policy, inside: false, time: 2.3))
        #expect(release(&policy, inside: false, time: 4))
        policy.resetReleaseDelay()
        #expect(sample(&policy, y: -795, time: 4, screen: external))
        policy.recordRevealAttempt(at: 4)
        #expect(!sample(&policy, y: -795, time: 4.1, screen: external))
        #expect(!release(&policy, inside: false, time: 5))
        #expect(release(&policy, inside: false, time: 8))
    }

    @Test func leavingTheNextDisplayZoneDropsAnUnservedHover() {
        let external = CGRect(x: -550, y: -800, width: 1900, height: 900)
        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: -795, time: 0, screen: external))
        #expect(sample(&policy, y: -795, time: 1, screen: external))
        #expect(!sample(&policy, y: -770, time: 2, screen: external))
        #expect(!sample(&policy, y: -795, time: 3, screen: external))
        #expect(sample(&policy, y: -795, time: 4, screen: external))
    }

    @Test func failedAttachmentRetriesOnceAfterAppKitSettles() {
        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: 105, time: 0))
        #expect(sample(&policy, y: 105, time: 0.3))
        policy.recordRevealAttempt(at: 0.3, canRetry: true)
        #expect(!sample(&policy, y: 105, time: 0.6))
        #expect(sample(&policy, y: 105, time: 0.8))
        policy.recordRevealAttempt(at: 0.8, canRetry: true)
        #expect(!sample(&policy, y: 105, time: 1.5))
    }

    @Test func closingAMenuRearmsHoverWithoutResettingTheHoldCountdown() {
        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: 105, time: 0))
        #expect(sample(&policy, y: 105, time: 0.3))
        policy.recordRevealAttempt(at: 0.3)
        #expect(!release(&policy, inside: false, time: 1))
        policy.resetHover()
        #expect(!sample(&policy, y: 105, time: 2))
        #expect(sample(&policy, y: 105, time: 2.3))
        #expect(release(&policy, inside: false, time: 4))
    }

    @Test func unexpectedDismissalOnlyRearmsTheOriginalDisplaysHover() {
        let external = CGRect(x: -550, y: -800, width: 1900, height: 900)
        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: -795, time: 0, screen: external))
        #expect(sample(&policy, y: -795, time: 0.3, screen: external))
        policy.recordRevealAttempt(at: 0.3)
        policy.allowRetryAfterDismissal(on: display, at: 1)
        #expect(!sample(&policy, y: -795, time: 1.5, screen: external))
        policy.allowRetryAfterDismissal(on: external, at: 2)
        #expect(!sample(&policy, y: -795, time: 2.2, screen: external))
        #expect(sample(&policy, y: -795, time: 2.5, screen: external))
        policy.recordRevealAttempt(at: 2.5)
        policy.allowRetryAfterDismissal(on: external, at: 3)
        #expect(!sample(&policy, y: -795, time: 4, screen: external))
    }

    @Test func cutoutCornersAndInputInUseNeverReveal() {
        let areas = [
            CGRect(x: -200, y: 100, width: 540, height: 32),
            CGRect(x: 460, y: 100, width: 540, height: 32)
        ]
        for x in [-195.0, 410, 995] {
            var policy = MenuBarRevealPolicy()
            #expect(!sample(&policy, x: x, y: 115, time: 0, areas: areas))
            #expect(!sample(&policy, x: x, y: 105, time: 1, areas: areas))
            #expect(!sample(&policy, x: x, y: 105, time: 2, areas: areas))
        }

        var policy = MenuBarRevealPolicy()
        #expect(!sample(&policy, y: 115, time: 0))
        #expect(!sample(&policy, y: 105, time: 1))
        #expect(!sample(&policy, y: 105, time: 2, busy: true))
        #expect(!sample(&policy, y: 105, time: 3))
        #expect(sample(&policy, y: 105, time: 4))
    }

    @Test func existingSettingsKeepTheHelperOffAndNewValuesStayBounded() throws {
        var library = try JSONDecoder().decode(LayoutLibrary.self, from: Data(#"{"schemaVersion":7}"#.utf8))
        #expect(!library.menuBarReveal.enabled)
        let existing = try JSONDecoder().decode(
            MenuBarRevealPreferences.self, from: Data(#"{"enabled":true,"activationDistance":12}"#.utf8)
        )
        #expect(existing == MenuBarRevealPreferences(enabled: true, activationDistance: 12, hideDelaySeconds: 3))
        library.menuBarReveal = MenuBarRevealPreferences(
            enabled: true, activationDistance: 1_000, hideDelaySeconds: 1_000
        )
        let validated = try library.validated()
        let reloaded = try JSONDecoder().decode(LayoutLibrary.self, from: JSONEncoder().encode(validated))
        #expect(reloaded.menuBarReveal == MenuBarRevealPreferences(
            enabled: true, activationDistance: 50, hideDelaySeconds: 10
        ))
    }

    @MainActor
    @Test func invisibleContentDisablesMouseInputBeforeItsWindowIsShown() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 20, height: 20),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        panel.contentView = MenuBarRevealContentView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(panel.ignoresMouseEvents)
        #expect(panel.alphaValue == 0)
        #expect(!panel.isVisible)
    }
}
