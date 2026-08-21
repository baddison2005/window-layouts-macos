// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

nonisolated enum DragTargetKind: Equatable, Sendable {
    case layout(NormalizedRect)
    case center
    case maximize

    var thumbnailRect: NormalizedRect {
        switch self {
        case .layout(let rect): rect
        case .center:
            try! NormalizedRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
        case .maximize:
            try! NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        }
    }
}

nonisolated struct DragTargetDefinition: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: DragTargetKind

    var center: CGPoint {
        let rect = kind.thumbnailRect
        return CGPoint(
            x: rect.x + rect.width / 2,
            y: rect.y + rect.height / 2
        )
    }
}

nonisolated struct DragTargetPlacement: Equatable, Identifiable, Sendable {
    let definition: DragTargetDefinition
    let frame: CGRect
    let groupKey: String

    var id: String { definition.id }
}

nonisolated enum DragTargetLayoutEngine {
    static let targetSize = CGSize(width: 116, height: 80)
    static let targetGap: CGFloat = 12
    static let screenMargin: CGFloat = 12
    static let revealedGroupPadding: CGFloat = 18
    static let stripPadding: CGFloat = 10
    static let maximumTopColumns = 10

    /// Inputs and output use Accessibility's top-left global coordinates.
    static func placements(
        for definitions: [DragTargetDefinition],
        style: DragTargetPlacementStyle,
        in usableFrame: CGRect
    ) -> [DragTargetPlacement] {
        guard valid(usableFrame), !definitions.isEmpty else { return [] }
        return switch style {
        case .zones:
            zonePlacements(for: definitions, in: usableFrame)
        case .top:
            topPlacements(for: definitions, in: usableFrame)
        }
    }

    static func visiblePlacements(
        among placements: [DragTargetPlacement],
        style: DragTargetPlacementStyle,
        immediate: Bool,
        revealedGroupKey: String?,
        topStripRevealed: Bool
    ) -> [DragTargetPlacement] {
        switch style {
        case .zones:
            guard !immediate else { return placements }
            guard let revealedGroupKey else { return [] }
            return placements.filter { $0.groupKey == revealedGroupKey }
        case .top:
            return immediate || topStripRevealed ? placements : []
        }
    }

    static func revealedZoneGroup(
        at point: CGPoint,
        placements: [DragTargetPlacement],
        in usableFrame: CGRect,
        retaining currentGroupKey: String?
    ) -> String? {
        if let currentGroupKey,
           let bounds = groupBounds(currentGroupKey, placements: placements),
           bounds.insetBy(
               dx: -revealedGroupPadding,
               dy: -revealedGroupPadding
           ).contains(point) {
            return currentGroupKey
        }

        let radius = activationRadius(in: usableFrame)
        let maximumDistance = radius * radius
        var checked: Set<String> = []
        var nearest: (key: String, distance: CGFloat)?
        for placement in placements where checked.insert(placement.groupKey).inserted {
            let center = placement.definition.center
            let zoneCenter = CGPoint(
                x: usableFrame.minX + usableFrame.width * center.x,
                y: usableFrame.minY + usableFrame.height * center.y
            )
            let distance = squaredDistance(point, zoneCenter)
            guard distance <= maximumDistance else { continue }
            if nearest == nil || distance < nearest!.distance {
                nearest = (placement.groupKey, distance)
            }
        }
        return nearest?.key
    }

    static func topTriggerFrame(in usableFrame: CGRect) -> CGRect {
        guard valid(usableFrame) else { return .zero }
        let width = clamp(usableFrame.width * 0.45, minimum: 420, maximum: 1_000)
        let height = clamp(usableFrame.height * 0.10, minimum: 90, maximum: 160)
        return CGRect(
            x: usableFrame.midX - min(width, usableFrame.width) / 2,
            y: usableFrame.minY,
            width: min(width, usableFrame.width),
            height: min(height, usableFrame.height)
        )
    }

    static func shouldRevealTopStrip(
        at point: CGPoint,
        placements: [DragTargetPlacement],
        in usableFrame: CGRect,
        currentlyRevealed: Bool
    ) -> Bool {
        if currentlyRevealed,
           stripFrame(for: placements)?.contains(point) == true {
            return true
        }
        return topTriggerFrame(in: usableFrame).contains(point)
    }

    static func hoveredPlacement(
        at point: CGPoint,
        among visiblePlacements: [DragTargetPlacement]
    ) -> DragTargetPlacement? {
        visiblePlacements
            .filter { $0.frame.contains(point) }
            .min {
                squaredDistance(point, CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                    < squaredDistance(point, CGPoint(x: $1.frame.midX, y: $1.frame.midY))
            }
    }

    static func previewFrame(
        for definition: DragTargetDefinition,
        draggedWindowFrame: CGRect,
        in usableFrame: CGRect,
        padding: CGFloat
    ) -> CGRect {
        switch definition.kind {
        case .layout(let rect):
            LayoutEngine.rectangle(for: rect, in: usableFrame, padding: padding)
        case .maximize:
            usableFrame
        case .center:
            LayoutEngine.centered(frame: draggedWindowFrame, in: usableFrame)
        }
    }

    static func stripFrame(for placements: [DragTargetPlacement]) -> CGRect? {
        guard var bounds = placements.first?.frame else { return nil }
        for placement in placements.dropFirst() {
            bounds = bounds.union(placement.frame)
        }
        return bounds.insetBy(dx: -stripPadding, dy: -stripPadding)
    }

    static func groupBounds(
        _ groupKey: String,
        placements: [DragTargetPlacement]
    ) -> CGRect? {
        let group = placements.filter { $0.groupKey == groupKey }
        guard var bounds = group.first?.frame else { return nil }
        for placement in group.dropFirst() {
            bounds = bounds.union(placement.frame)
        }
        return bounds
    }

    static func activationRadius(in usableFrame: CGRect) -> CGFloat {
        clamp(min(usableFrame.width, usableFrame.height) * 0.14, minimum: 125, maximum: 210)
    }

    private static func zonePlacements(
        for definitions: [DragTargetDefinition],
        in usableFrame: CGRect
    ) -> [DragTargetPlacement] {
        var keys: [String] = []
        var groups: [String: [DragTargetDefinition]] = [:]
        for definition in definitions {
            let key = groupKey(for: definition.center)
            if groups[key] == nil {
                keys.append(key)
                groups[key] = []
            }
            groups[key, default: []].append(definition)
        }

        let maximumRows = max(
            1,
            Int(floor(
                (usableFrame.height - screenMargin * 2 + targetGap)
                    / (targetSize.height + targetGap)
            ))
        )
        var result: [DragTargetPlacement] = []
        for key in keys {
            guard let group = groups[key], let first = group.first else { continue }
            let columnCount = Int(ceil(Double(group.count) / Double(maximumRows)))
            let totalWidth = CGFloat(columnCount) * targetSize.width
                + CGFloat(max(0, columnCount - 1)) * targetGap
            let desiredLeft = usableFrame.minX
                + usableFrame.width * first.center.x
                - totalWidth / 2
            let groupLeft = clamp(
                desiredLeft,
                minimum: usableFrame.minX + screenMargin,
                maximum: max(
                    usableFrame.minX + screenMargin,
                    usableFrame.maxX - screenMargin - totalWidth
                )
            )

            for (index, definition) in group.enumerated() {
                let column = index / maximumRows
                let firstInColumn = column * maximumRows
                let rowsInColumn = min(maximumRows, group.count - firstInColumn)
                let row = index - firstInColumn
                let columnHeight = CGFloat(rowsInColumn) * targetSize.height
                    + CGFloat(max(0, rowsInColumn - 1)) * targetGap
                let desiredTop = usableFrame.minY
                    + usableFrame.height * definition.center.y
                    - columnHeight / 2
                let groupTop = clamp(
                    desiredTop,
                    minimum: usableFrame.minY + screenMargin,
                    maximum: max(
                        usableFrame.minY + screenMargin,
                        usableFrame.maxY - screenMargin - columnHeight
                    )
                )
                result.append(
                    DragTargetPlacement(
                        definition: definition,
                        frame: CGRect(
                            x: groupLeft + CGFloat(column) * (targetSize.width + targetGap),
                            y: groupTop + CGFloat(row) * (targetSize.height + targetGap),
                            width: targetSize.width,
                            height: targetSize.height
                        ).integral,
                        groupKey: key
                    )
                )
            }
        }
        return result
    }

    private static func topPlacements(
        for definitions: [DragTargetDefinition],
        in usableFrame: CGRect
    ) -> [DragTargetPlacement] {
        let availableColumns = max(
            1,
            Int(floor(
                (usableFrame.width - screenMargin * 2 + targetGap)
                    / (targetSize.width + targetGap)
            ))
        )
        let columnCount = max(
            1,
            min(definitions.count, min(maximumTopColumns, availableColumns))
        )

        return definitions.enumerated().map { index, definition in
            let row = index / columnCount
            let firstInRow = row * columnCount
            let columnsInRow = min(columnCount, definitions.count - firstInRow)
            let rowWidth = CGFloat(columnsInRow) * targetSize.width
                + CGFloat(max(0, columnsInRow - 1)) * targetGap
            let column = index - firstInRow
            return DragTargetPlacement(
                definition: definition,
                frame: CGRect(
                    x: usableFrame.midX - rowWidth / 2
                        + CGFloat(column) * (targetSize.width + targetGap),
                    y: usableFrame.minY + screenMargin
                        + CGFloat(row) * (targetSize.height + targetGap),
                    width: targetSize.width,
                    height: targetSize.height
                ).integral,
                groupKey: "top"
            )
        }
    }

    private static func groupKey(for center: CGPoint) -> String {
        "\(Int((center.x * 10_000).rounded())):\(Int((center.y * 10_000).rounded()))"
    }

    private static func valid(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0
            && frame.height > 0
    }

    private static func clamp(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        max(minimum, min(value, maximum))
    }

    private static func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }
}
