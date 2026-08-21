// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct VisibleWindowMatchingTests {
    @Test func preservesFrontToBackOrderAndConsumesEachAXWindowOnce() {
        let visible = [
            WindowFrameDescriptor(
                processIdentifier: 20,
                frame: CGRect(x: 400, y: 0, width: 400, height: 600)
            ),
            WindowFrameDescriptor(
                processIdentifier: 10,
                frame: CGRect(x: 0, y: 0, width: 400, height: 600)
            ),
        ]
        let candidates = [
            visible[1],
            visible[0],
            visible[0],
        ]

        #expect(
            VisibleWindowMatching.candidateIndices(
                for: visible,
                among: candidates
            ) == [1, 0]
        )
    }

    @Test func rejectsDifferentProcessesAndFramesOutsideTolerance() {
        let visible = WindowFrameDescriptor(
            processIdentifier: 10,
            frame: CGRect(x: 0, y: 0, width: 400, height: 600)
        )
        let candidates = [
            WindowFrameDescriptor(processIdentifier: 11, frame: visible.frame),
            WindowFrameDescriptor(
                processIdentifier: 10,
                frame: visible.frame.offsetBy(dx: 20, dy: 0)
            ),
        ]

        #expect(
            VisibleWindowMatching.candidateIndices(
                for: [visible],
                among: candidates
            ).isEmpty
        )
    }

    @Test func extraWindowsReuseSlotsDeterministically() {
        #expect(
            VisibleWindowMatching.layoutIndices(windowCount: 5, layoutCount: 2)
                == [0, 1, 0, 1, 0]
        )
        #expect(VisibleWindowMatching.layoutIndices(windowCount: 3, layoutCount: 0).isEmpty)
    }
}
