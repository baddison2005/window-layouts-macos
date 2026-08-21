// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import WindowLayouts

struct FocusedApplicationSelectionTests {
    @Test func prefersTheSystemWideAXFocusedApplication() {
        #expect(
            FocusedApplicationSelection.processIdentifier(
                axFocusedProcessIdentifier: 41,
                workspaceFrontmostProcessIdentifier: 82
            ) == 41
        )
    }

    @Test func fallsBackToTheWorkspaceFrontmostApplication() {
        #expect(
            FocusedApplicationSelection.processIdentifier(
                axFocusedProcessIdentifier: nil,
                workspaceFrontmostProcessIdentifier: 82
            ) == 82
        )
    }

    @Test func rejectsInvalidProcessIdentifiers() {
        #expect(
            FocusedApplicationSelection.processIdentifier(
                axFocusedProcessIdentifier: 0,
                workspaceFrontmostProcessIdentifier: -1
            ) == nil
        )
    }
}
