// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import WindowLayouts

@MainActor
struct SpaceMovementServiceTests {
    @Test func postsCompleteGestureAndRestoresPointer() async throws {
        let fixture = Fixture()
        let service = SpaceMovementService(client: fixture.client())

        try await service.moveWindow(.next)

        #expect(fixture.events == [
            .mouseMoved(point: fixture.target.dragPoint),
            .leftMouseDown(point: fixture.target.dragPoint, eventNumber: 42),
            .keyDown(code: CGKeyCode(kVK_Control), control: true),
            .keyDown(code: CGKeyCode(kVK_RightArrow), control: true),
            .keyUp(code: CGKeyCode(kVK_RightArrow), control: true),
            .keyUp(code: CGKeyCode(kVK_Control), control: false),
            .leftMouseUp(point: fixture.target.dragPoint, eventNumber: 42),
            .mouseMoved(point: fixture.originalPointer),
        ])
        #expect(fixture.resolvedProcessIdentifiers == [nil])
    }

    @Test func waitsForPhysicalInputToBecomeNeutral() async throws {
        let fixture = Fixture()
        fixture.inputStates = [
            SpaceMovementInputState(
                primaryModifierIsDown: true,
                mouseButtonIsDown: false
            ),
            SpaceMovementInputState(
                primaryModifierIsDown: false,
                mouseButtonIsDown: true
            ),
            SpaceMovementInputState(
                primaryModifierIsDown: false,
                mouseButtonIsDown: false
            ),
        ]
        let service = SpaceMovementService(client: fixture.client())

        try await service.moveWindow(.previous, processIdentifier: 1234)

        #expect(fixture.inputStateReadCount == 3)
        #expect(fixture.resolvedProcessIdentifiers == [1234])
        #expect(fixture.events.contains(
            .keyDown(code: CGKeyCode(kVK_LeftArrow), control: true)
        ))
    }

    @Test func refusesToPostWithoutBothPrivacyPermissions() async {
        let missingAccessibility = Fixture()
        missingAccessibility.accessibilityAccess = false
        let accessibilityService = SpaceMovementService(
            client: missingAccessibility.client()
        )

        await #expect(throws: SpaceMovementError.accessibilityPermissionRequired) {
            try await accessibilityService.moveWindow(.next)
        }
        #expect(missingAccessibility.events.isEmpty)

        let missingPostAccess = Fixture()
        missingPostAccess.postEventAccess = false
        let postService = SpaceMovementService(client: missingPostAccess.client())

        await #expect(throws: SpaceMovementError.postEventPermissionRequired) {
            try await postService.moveWindow(.next)
        }
        #expect(missingPostAccess.events.isEmpty)
    }

    @Test func timesOutBeforeTargetingWhenPhysicalInputRemainsActive() async {
        let fixture = Fixture()
        fixture.fallbackInputState = SpaceMovementInputState(
            primaryModifierIsDown: true,
            mouseButtonIsDown: true
        )
        let service = SpaceMovementService(client: fixture.client())

        await #expect(throws: SpaceMovementError.inputStillActive) {
            try await service.moveWindow(.next)
        }

        #expect(fixture.inputStateReadCount == 30)
        #expect(fixture.resolvedProcessIdentifiers.isEmpty)
        #expect(fixture.events.isEmpty)
    }

    @Test func releasesSyntheticInputAndRestoresPointerAfterFailure() async {
        let fixture = Fixture()
        fixture.failingPostIndex = 4
        let service = SpaceMovementService(client: fixture.client())

        await #expect(throws: Fixture.Failure.post) {
            try await service.moveWindow(.next)
        }

        #expect(fixture.events.suffix(4) == [
            .keyUp(code: CGKeyCode(kVK_RightArrow), control: true),
            .keyUp(code: CGKeyCode(kVK_Control), control: false),
            .leftMouseUp(point: fixture.target.dragPoint, eventNumber: 42),
            .mouseMoved(point: fixture.originalPointer),
        ])
    }
}

@MainActor
private final class Fixture {
    enum Failure: Error {
        case post
    }

    let originalPointer = CGPoint(x: 800, y: 500)
    let target = SpaceMovementTarget(
        processIdentifier: 777,
        windowFrame: CGRect(x: 100, y: 100, width: 900, height: 700),
        dragPoint: CGPoint(x: 550, y: 114)
    )
    var accessibilityAccess = true
    var postEventAccess = true
    var inputStates: [SpaceMovementInputState] = []
    var fallbackInputState = SpaceMovementInputState(
        primaryModifierIsDown: false,
        mouseButtonIsDown: false
    )
    var inputStateReadCount = 0
    var resolvedProcessIdentifiers: [pid_t?] = []
    var events: [SpaceMovementSyntheticEvent] = []
    var failingPostIndex: Int?

    func client() -> SpaceMovementSystemClient {
        SpaceMovementSystemClient(
            hasAccessibilityAccess: { [unowned self] in accessibilityAccess },
            hasPostEventAccess: { [unowned self] in postEventAccess },
            requestPostEventAccess: { [unowned self] in postEventAccess },
            inputState: { [unowned self] in
                defer { inputStateReadCount += 1 }
                guard inputStateReadCount < inputStates.count else {
                    return fallbackInputState
                }
                return inputStates[inputStateReadCount]
            },
            pointerLocation: { [unowned self] in originalPointer },
            eventNumber: { 42 },
            resolveTarget: { [unowned self] processIdentifier in
                resolvedProcessIdentifiers.append(processIdentifier)
                return target
            },
            post: { [unowned self] event in
                let index = events.count
                events.append(event)
                if failingPostIndex == index {
                    throw Failure.post
                }
            },
            pause: { _ in }
        )
    }
}
