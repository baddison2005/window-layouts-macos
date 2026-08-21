// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

nonisolated struct DisplayGeometry<ID: Hashable & Sendable>: Equatable, Sendable {
    let id: ID
    let frame: CGRect
}

nonisolated enum MonitorTransfer {
    static func destination(
        for windowFrame: CGRect,
        from sourceFrame: CGRect,
        to destinationFrame: CGRect,
        padding: CGFloat,
        layouts: [NormalizedRect] = FixedLayout.allCases.map(\.normalizedRect),
        preferredLayout: NormalizedRect? = nil
    ) -> CGRect {
        if let matchingLayout = preferredLayout ?? recognizedLayout(
            for: windowFrame,
            in: sourceFrame,
            padding: padding,
            layouts: layouts
        ) {
            return LayoutEngine.rectangle(
                for: matchingLayout,
                in: destinationFrame,
                padding: padding
            )
        }

        let normalized = LayoutEngine.normalizedGeometry(
            of: windowFrame,
            in: sourceFrame
        )
        return LayoutEngine.clamped(
            LayoutEngine.rectangle(for: normalized, in: destinationFrame),
            to: destinationFrame
        )
    }

    static func recognizedLayout(
        for windowFrame: CGRect,
        in usableFrame: CGRect,
        padding: CGFloat,
        layouts: [NormalizedRect] = FixedLayout.allCases.map(\.normalizedRect)
    ) -> NormalizedRect? {
        layouts.first {
            LayoutEngine.approximatelyEqual(
                LayoutEngine.rectangle(for: $0, in: usableFrame, padding: padding),
                windowFrame
            )
        }
    }

    static func applicableRememberedLayout(
        _ layout: NormalizedRect?,
        currentFrame: CGRect,
        lastAppliedFrame: CGRect?
    ) -> NormalizedRect? {
        guard let layout,
              let lastAppliedFrame,
              LayoutEngine.approximatelyEqual(currentFrame, lastAppliedFrame) else {
            return nil
        }
        return layout
    }

    /// Stable ordering: left-to-right by midpoint, then top-to-bottom.
    static func orderedDisplays<ID>(_ displays: [DisplayGeometry<ID>]) -> [DisplayGeometry<ID>] {
        displays.sorted {
            if abs($0.frame.midX - $1.frame.midX) > 0.5 {
                return $0.frame.midX < $1.frame.midX
            }
            if abs($0.frame.midY - $1.frame.midY) > 0.5 {
                return $0.frame.midY > $1.frame.midY
            }
            return String(describing: $0.id) < String(describing: $1.id)
        }
    }

    static func adjacentDisplay<ID>(
        to currentID: ID,
        offset: Int,
        in displays: [DisplayGeometry<ID>]
    ) -> DisplayGeometry<ID>? {
        let ordered = orderedDisplays(displays)
        guard ordered.count > 1,
              let currentIndex = ordered.firstIndex(where: { $0.id == currentID }) else {
            return nil
        }
        let wrappedIndex = (currentIndex + offset % ordered.count + ordered.count) % ordered.count
        return ordered[wrappedIndex]
    }
}
