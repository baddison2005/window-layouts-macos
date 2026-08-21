// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing
@testable import WindowLayouts

@MainActor
struct InputTransparentOverlayPanelTests {
    @Test func remainsInputTransparentWhenVisibleAndHidden() {
        let panel = InputTransparentOverlayPanel()

        #expect(panel.ignoresMouseEvents)
        #expect(!panel.isVisible)

        panel.present(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(panel.isVisible)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)

        panel.conceal()
        #expect(!panel.isVisible)
        #expect(panel.ignoresMouseEvents)
    }

    @Test func evenAScreenSizedPreviewCannotAcceptMouseInput() {
        let panel = InputTransparentOverlayPanel()
        panel.present(frame: CGRect(x: 0, y: 0, width: 3_840, height: 2_160))

        #expect(panel.ignoresMouseEvents)

        panel.conceal()
    }
}
