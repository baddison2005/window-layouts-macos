// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

struct ApplicationLaunchMappingTests {
    private let launched = RunningApplicationDescriptor(
        processIdentifier: 42,
        bundleIdentifier: "com.example.Editor",
        isRegularApplication: true
    )

    @Test func startupGraceSuppressesLaunches() {
        #expect(!ApplicationLaunchMappingPolicy.shouldHandleLaunch(
            isArmed: false,
            launched: launched,
            runningApplications: [launched]
        ))
    }

    @Test func newlyLaunchedClosedApplicationIsHandledAfterArming() {
        #expect(ApplicationLaunchMappingPolicy.shouldHandleLaunch(
            isArmed: true,
            launched: launched,
            runningApplications: [launched]
        ))
    }

    @Test func secondInstanceIsIgnoredWhileApplicationIsAlreadyOpen() {
        let existing = RunningApplicationDescriptor(
            processIdentifier: 41,
            bundleIdentifier: launched.bundleIdentifier,
            isRegularApplication: true
        )
        #expect(!ApplicationLaunchMappingPolicy.shouldHandleLaunch(
            isArmed: true,
            launched: launched,
            runningApplications: [existing, launched]
        ))
    }

    @Test func helpersAndApplicationsWithoutBundleIdentifiersAreIgnored() {
        let helper = RunningApplicationDescriptor(
            processIdentifier: 43,
            bundleIdentifier: "com.example.Helper",
            isRegularApplication: false
        )
        let unidentified = RunningApplicationDescriptor(
            processIdentifier: 44,
            bundleIdentifier: nil,
            isRegularApplication: true
        )
        #expect(!ApplicationLaunchMappingPolicy.shouldHandleLaunch(
            isArmed: true,
            launched: helper,
            runningApplications: [helper]
        ))
        #expect(!ApplicationLaunchMappingPolicy.shouldHandleLaunch(
            isArmed: true,
            launched: unidentified,
            runningApplications: [unidentified]
        ))
    }
}
