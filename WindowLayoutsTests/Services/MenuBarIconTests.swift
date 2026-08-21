// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing
@testable import WindowLayouts

@MainActor
struct MenuBarIconTests {
    @Test func compactAssetHasMenuBarSizedIntrinsicDimensions() throws {
        let image = try #require(NSImage(named: "MenuBarIconCompact"))

        #expect(image.size == NSSize(width: 16, height: 16))
    }

    @Test func greenPanelMonitorSymbolsExist() {
        #expect(
            NSImage(
                systemSymbolName: "arrow.backward.to.line",
                accessibilityDescription: nil
            ) != nil
        )
        #expect(
            NSImage(
                systemSymbolName: "arrow.forward.to.line",
                accessibilityDescription: nil
            ) != nil
        )
    }
}
