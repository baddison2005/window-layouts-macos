// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import WindowLayouts

struct SemanticVersionTests {
    @Test func parsesReleaseTagsAndPlainVersions() {
        #expect(SemanticVersion("v1.2.0")?.description == "1.2.0")
        #expect(SemanticVersion("1.2.0")?.description == "1.2.0")
        #expect(SemanticVersion(" V10.20.30 \n")?.description == "10.20.30")
    }

    @Test func rejectsIncompleteOrNonReleaseVersions() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("1.2") == nil)
        #expect(SemanticVersion("1.2.0-beta") == nil)
        #expect(SemanticVersion("version-1.2.0") == nil)
    }

    @Test func comparesEachNumericComponent() {
        #expect(SemanticVersion("1.2.0")! > SemanticVersion("1.1.9")!)
        #expect(SemanticVersion("1.10.0")! > SemanticVersion("1.2.99")!)
        #expect(SemanticVersion("2.0.0")! > SemanticVersion("1.99.99")!)
        #expect(SemanticVersion("1.2.0") == SemanticVersion("v1.2.0"))
    }
}
