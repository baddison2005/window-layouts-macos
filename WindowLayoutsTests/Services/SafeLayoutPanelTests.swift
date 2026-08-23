// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing
@testable import WindowLayouts

@MainActor
struct SafeLayoutPanelTests {
    @Test func hiddenPanelCannotAcceptMouseInput() {
        let panel = SafeLayoutPanel(contentSize: CGSize(width: 310, height: 500))

        #expect(!panel.isVisible)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.frame.size == CGSize(width: 310, height: 500))
        #expect(panel.level == .popUpMenu)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test func concealDisablesInputBeforeLeavingPanelHidden() {
        let panel = SafeLayoutPanel(contentSize: CGSize(width: 260, height: 390))
        panel.present(frame: CGRect(x: 20, y: 20, width: 260, height: 390))
        #expect(panel.isVisible)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.alphaValue == 1)

        panel.conceal()

        #expect(!panel.isVisible)
        #expect(panel.ignoresMouseEvents)
    }
}
