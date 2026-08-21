// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices

@MainActor
struct AccessibilityTrustClient {
    var check: () -> Bool
    var prompt: () -> Bool

    static let system = AccessibilityTrustClient(
        check: { AXIsProcessTrusted() },
        prompt: {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
    )
}

@MainActor
final class AccessibilityPermissionService {
    private let client: AccessibilityTrustClient

    init() {
        self.client = .system
    }

    init(client: AccessibilityTrustClient) {
        self.client = client
    }

    func isTrusted() -> Bool {
        client.check()
    }

    /// Prompts only when invoked from an explicit onboarding action.
    func requestAccess() -> Bool {
        client.prompt()
    }
}
