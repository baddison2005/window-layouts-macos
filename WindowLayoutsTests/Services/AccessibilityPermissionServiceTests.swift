// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import Testing
@testable import WindowLayouts

@MainActor
struct AccessibilityPermissionServiceTests {
    @Test func checksWithoutPromptingAndPromptsOnlyWhenRequested() {
        var checkCount = 0
        var promptCount = 0
        let service = AccessibilityPermissionService(
            client: AccessibilityTrustClient(
                check: {
                    checkCount += 1
                    return false
                },
                prompt: {
                    promptCount += 1
                    return true
                }
            )
        )

        #expect(service.isTrusted() == false)
        #expect(checkCount == 1)
        #expect(promptCount == 0)
        #expect(service.requestAccess() == true)
        #expect(promptCount == 1)
    }

    @Test func mapsDefensiveAXErrors() {
        #expect(WindowAccessibilityService.translatedError(
            .cannotComplete,
            operation: "lookup"
        ) == .targetTimedOut(operation: "lookup"))
        #expect(WindowAccessibilityService.translatedError(
            .apiDisabled,
            operation: "lookup"
        ) == .permissionRequired)
        #expect(WindowAccessibilityService.translatedError(
            .invalidUIElement,
            operation: "lookup"
        ) == .accessibilityFailure(
            operation: "lookup",
            code: AXError.invalidUIElement.rawValue
        ))
    }
}
