// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import CoreGraphics
import OSLog

@MainActor
final class DragTargetController: ObservableObject {
    private enum TrackingState {
        case idle
        case candidate(WindowDragSnapshot)
        case dragging(WindowDragSnapshot, currentFrame: CGRect)
    }

    private struct CatalogEntry {
        let definition: DragTargetDefinition
        let action: WindowAction
    }

    private let settingsStore: SettingsStore
    private let windowController: WindowLayoutsController
    private let renderer: DragTargetOverlayRenderer
    private var library: LayoutLibrary
    private var settingsObservation: AnyCancellable?
    private var globalEventMonitor: Any?
    private var buttonStateTimer: Timer?
    private var trackingState: TrackingState = .idle
    private var enabled = false
    private var generation: UInt = 0
    private var sampleInFlight = false
    private var samplePending = false
    private var revealedGroupKey: String?
    private var topStripRevealed = false
    private var hoveredDefinitionID: String?
    private var currentScreenID: String?
    private var actionsByDefinitionID: [String: WindowAction] = [:]

    init(
        settingsStore: SettingsStore,
        windowController: WindowLayoutsController,
        renderer: DragTargetOverlayRenderer? = nil
    ) {
        self.settingsStore = settingsStore
        self.windowController = windowController
        self.renderer = renderer ?? DragTargetOverlayRenderer()
        self.library = settingsStore.library

        settingsObservation = settingsStore.$library.sink { [weak self] library in
            self?.apply(library: library)
        }
    }

    private func apply(library: LayoutLibrary) {
        self.library = library
        if library.dragTargetsEnabled {
            startIfNeeded()
            if case .dragging(_, let frame) = trackingState {
                updatePresentation(draggedWindowFrame: frame)
            }
        } else {
            stopIfNeeded()
        }
    }

    private func startIfNeeded() {
        guard !enabled else { return }
        enabled = true
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in
                self?.receive(event)
            }
        }
        installEnvironmentObservers()
        if globalEventMonitor == nil {
            AppDiagnostics.overlays.error(
                "The global drag event monitor could not be installed"
            )
        }
    }

    private func stopIfNeeded() {
        guard enabled else {
            renderer.hideAll()
            return
        }
        enabled = false
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        globalEventMonitor = nil
        removeEnvironmentObservers()
        finishTracking(applyHoveredLayout: false)
    }

    private func receive(_ event: NSEvent) {
        guard enabled else { return }
        switch event.type {
        case .leftMouseDragged:
            requestSample()
        case .leftMouseUp:
            finishTracking(applyHoveredLayout: true)
        default:
            break
        }
    }

    private func requestSample() {
        guard enabled else { return }
        guard !sampleInFlight else {
            samplePending = true
            return
        }

        let screens = ScreenService.snapshots()
        guard !screens.isEmpty else {
            finishTracking(applyHoveredLayout: false)
            return
        }
        sampleInFlight = true
        let sampleGeneration = generation

        Task { [weak self] in
            guard let self else { return }
            do {
                switch trackingState {
                case .idle:
                    let snapshot = try await windowController.beginDragSession(
                        screens: screens
                    )
                    guard generation == sampleGeneration, enabled else {
                        windowController.cancelDragSession(snapshot.session)
                        completeSample()
                        return
                    }
                    trackingState = .candidate(snapshot)
                    startButtonStateFallback()

                case .candidate(let snapshot):
                    let currentFrame = try await windowController.frame(
                        for: snapshot.session
                    )
                    guard generation == sampleGeneration, enabled else {
                        completeSample()
                        return
                    }
                    switch DragMotionClassifier.classify(
                        from: snapshot.frame,
                        to: currentFrame
                    ) {
                    case .unchanged:
                        break
                    case .resizing:
                        finishTracking(applyHoveredLayout: false)
                    case .moving:
                        trackingState = .dragging(
                            snapshot,
                            currentFrame: currentFrame
                        )
                        updatePresentation(draggedWindowFrame: currentFrame)
                    }

                case .dragging(let snapshot, _):
                    let currentFrame = try await windowController.frame(
                        for: snapshot.session
                    )
                    guard generation == sampleGeneration, enabled else {
                        completeSample()
                        return
                    }
                    trackingState = .dragging(
                        snapshot,
                        currentFrame: currentFrame
                    )
                    updatePresentation(draggedWindowFrame: currentFrame)
                }
            } catch {
                guard generation == sampleGeneration else {
                    completeSample()
                    return
                }
                finishTracking(applyHoveredLayout: false)
            }
            completeSample()
        }
    }

    private func completeSample() {
        sampleInFlight = false
        if samplePending {
            samplePending = false
            requestSample()
        }
    }

    private func updatePresentation(draggedWindowFrame: CGRect) {
        let screens = ScreenService.snapshots()
        guard let pointer = ScreenService.accessibilityPoint(
            fromAppKit: NSEvent.mouseLocation
        ),
        let screen = ScreenGeometryResolver.screen(
            containingPoint: pointer,
            among: screens
        ) else {
            finishTracking(applyHoveredLayout: false)
            return
        }

        if currentScreenID != screen.id {
            currentScreenID = screen.id
            revealedGroupKey = nil
            topStripRevealed = false
        }

        let catalog = targetCatalog(for: library)
        actionsByDefinitionID = Dictionary(
            uniqueKeysWithValues: catalog.map { ($0.definition.id, $0.action) }
        )
        let placements = DragTargetLayoutEngine.placements(
            for: catalog.map(\.definition),
            style: library.dragTargetPlacement,
            in: screen.visibleFrame
        )

        let immediate: Bool
        switch library.dragTargetPlacement {
        case .zones:
            immediate = library.showAllDragTargets
            if immediate {
                revealedGroupKey = nil
            } else {
                revealedGroupKey = DragTargetLayoutEngine.revealedZoneGroup(
                    at: pointer,
                    placements: placements,
                    in: screen.visibleFrame,
                    retaining: revealedGroupKey
                )
            }
            topStripRevealed = false
        case .top:
            immediate = library.showAllTopDragTargets
            topStripRevealed = immediate || DragTargetLayoutEngine.shouldRevealTopStrip(
                at: pointer,
                placements: placements,
                in: screen.visibleFrame,
                currentlyRevealed: topStripRevealed
            )
            revealedGroupKey = nil
        }

        let visible = DragTargetLayoutEngine.visiblePlacements(
            among: placements,
            style: library.dragTargetPlacement,
            immediate: immediate,
            revealedGroupKey: revealedGroupKey,
            topStripRevealed: topStripRevealed
        )
        let hovered = DragTargetLayoutEngine.hoveredPlacement(
            at: pointer,
            among: visible
        )
        hoveredDefinitionID = hovered?.definition.id
        let preview = hovered.map {
            DragTargetLayoutEngine.previewFrame(
                for: $0.definition,
                draggedWindowFrame: draggedWindowFrame,
                in: screen.visibleFrame,
                padding: CGFloat(library.layoutPadding)
            )
        }
        renderer.render(
            visibleTargets: visible,
            allTargets: placements,
            hoveredDefinitionID: hoveredDefinitionID,
            previewFrame: preview,
            showTopStripBackground: library.dragTargetPlacement == .top
                && !visible.isEmpty
        )
    }

    private func finishTracking(applyHoveredLayout: Bool) {
        generation &+= 1
        samplePending = false
        stopButtonStateFallback()

        let state = trackingState
        let session: WindowDragSession?
        switch state {
        case .idle:
            session = nil
        case .candidate(let snapshot), .dragging(let snapshot, _):
            session = snapshot.session
        }
        let action = applyHoveredLayout
            ? hoveredDefinitionID.flatMap { actionsByDefinitionID[$0] }
            : nil
        let destinationScreenID = action == nil ? nil : currentScreenID

        // Every panel stops drawing before the mouse-up can trigger an AX write.
        renderer.hideAll()
        trackingState = .idle
        revealedGroupKey = nil
        topStripRevealed = false
        hoveredDefinitionID = nil
        currentScreenID = nil
        actionsByDefinitionID = [:]

        guard let session else { return }
        guard let action else {
            windowController.cancelDragSession(session)
            return
        }
        Task { [weak windowController] in
            try? await Task.sleep(for: .milliseconds(35))
            windowController?.perform(
                action,
                dragSession: session,
                destinationScreenID: destinationScreenID
            )
        }
    }

    private func startButtonStateFallback() {
        guard buttonStateTimer == nil else { return }
        let timer = Timer(
            timeInterval: 0.05,
            target: self,
            selector: #selector(buttonStateTimerFired),
            userInfo: nil,
            repeats: true
        )
        buttonStateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func buttonStateTimerFired() {
        if !CGEventSource.buttonState(
            .combinedSessionState,
            button: .left
        ) {
            finishTracking(applyHoveredLayout: true)
        }
    }

    private func stopButtonStateFallback() {
        buttonStateTimer?.invalidate()
        buttonStateTimer = nil
    }

    private func installEnvironmentObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        finishTracking(applyHoveredLayout: false)
    }

    @objc private func workspaceApplicationTerminated(_ notification: NSNotification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication,
        trackedProcessIdentifier == application.processIdentifier else { return }
        finishTracking(applyHoveredLayout: false)
    }

    private func removeEnvironmentObservers() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private var trackedProcessIdentifier: pid_t? {
        switch trackingState {
        case .idle:
            nil
        case .candidate(let snapshot), .dragging(let snapshot, _):
            snapshot.processIdentifier
        }
    }

    private func targetCatalog(for library: LayoutLibrary) -> [CatalogEntry] {
        var result: [CatalogEntry] = []
        for group in library.orderedMenuGroups {
            switch group {
            case .halves, .quarters, .thirds, .twoThirds:
                result.append(contentsOf: group.fixedLayouts.map { layout in
                    CatalogEntry(
                        definition: DragTargetDefinition(
                            id: "fixed.\(layout.rawValue)",
                            name: layout.name,
                            kind: .layout(layout.normalizedRect)
                        ),
                        action: .fixed(layout)
                    )
                })
            case .custom:
                let ordered = library.customGroups.flatMap { group in
                    library.customLayouts.filter { $0.groupID == group.id }
                } + library.customLayouts.filter { $0.groupID == nil }
                result.append(contentsOf: ordered.map { layout in
                    CatalogEntry(
                        definition: DragTargetDefinition(
                            id: "custom.\(layout.id.uuidString)",
                            name: layout.name,
                            kind: .layout(layout.normalizedRect)
                        ),
                        action: .custom(layout)
                    )
                })
            case .window:
                result.append(
                    CatalogEntry(
                        definition: DragTargetDefinition(
                            id: "window.maximize",
                            name: "Maximize",
                            kind: .maximize
                        ),
                        action: .maximize
                    )
                )
                result.append(
                    CatalogEntry(
                        definition: DragTargetDefinition(
                            id: "window.center",
                            name: "Center",
                            kind: .center
                        ),
                        action: .center
                    )
                )
            }
        }
        return result
    }
}

@MainActor
final class DragTargetOverlayRenderer {
    private struct TargetPanelRecord {
        let panel: InputTransparentOverlayPanel
        var definition: DragTargetDefinition
        var hovered: Bool
    }

    private var targetPanels: [String: TargetPanelRecord] = [:]
    private let previewPanel = InputTransparentOverlayPanel()
    private let stripPanel = InputTransparentOverlayPanel()

    init() {
        previewPanel.installContentView(DragPreviewView(frame: .zero))
        stripPanel.installContentView(DragTopStripView(frame: .zero))
    }

    func render(
        visibleTargets: [DragTargetPlacement],
        allTargets: [DragTargetPlacement],
        hoveredDefinitionID: String?,
        previewFrame: CGRect?,
        showTopStripBackground: Bool
    ) {
        let visibleIDs = Set(visibleTargets.map(\.definition.id))
        for (id, record) in targetPanels where !visibleIDs.contains(id) {
            record.panel.conceal()
        }

        if let previewFrame,
           let appKitFrame = ScreenService.appKitRect(
               fromAccessibility: previewFrame
           ) {
            previewPanel.present(frame: appKitFrame)
        } else {
            previewPanel.conceal()
        }

        if showTopStripBackground,
           let stripFrame = DragTargetLayoutEngine.stripFrame(for: allTargets),
           let appKitFrame = ScreenService.appKitRect(fromAccessibility: stripFrame) {
            stripPanel.present(frame: appKitFrame)
        } else {
            stripPanel.conceal()
        }

        for placement in visibleTargets {
            guard let appKitFrame = ScreenService.appKitRect(
                fromAccessibility: placement.frame
            ) else { continue }
            let isHovered = placement.definition.id == hoveredDefinitionID
            var record = targetPanels[placement.definition.id] ?? TargetPanelRecord(
                panel: InputTransparentOverlayPanel(),
                definition: placement.definition,
                hovered: !isHovered
            )
            if record.definition != placement.definition || record.hovered != isHovered {
                record.panel.installContentView(
                    DragTargetCardView(
                        frame: .zero,
                        definition: placement.definition,
                        hovered: isHovered
                    )
                )
                record.definition = placement.definition
                record.hovered = isHovered
            }
            targetPanels[placement.definition.id] = record
            record.panel.present(frame: appKitFrame)
        }
    }

    func hideAll() {
        for record in targetPanels.values {
            record.panel.conceal()
        }
        previewPanel.conceal()
        stripPanel.conceal()
    }
}

@MainActor
final class InputTransparentOverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func installContentView(_ view: NSView) {
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    func present(frame: CGRect) {
        // This invariant is deliberately repeated before every map operation.
        ignoresMouseEvents = true
        setFrame(frame, display: false)
        contentView?.frame = CGRect(origin: .zero, size: frame.size)
        alphaValue = 1
        orderFrontRegardless()
    }

    func conceal() {
        ignoresMouseEvents = true
        orderOut(nil)
    }
}

private final class DragTargetCardView: NSView {
    private let definition: DragTargetDefinition
    private let hovered: Bool

    init(frame: CGRect, definition: DragTargetDefinition, hovered: Bool) {
        self.definition = definition
        self.hovered = hovered
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let accent = NSColor.systemBlue
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 9, yRadius: 9)
        (hovered
            ? NSColor(calibratedWhite: 0.13, alpha: 0.98)
            : NSColor(calibratedWhite: 0.13, alpha: 0.90)
        ).setFill()
        card.fill()
        (hovered ? NSColor.white : accent).setStroke()
        card.lineWidth = hovered ? 3 : 2
        card.stroke()

        let miniature = CGRect(x: 23, y: 7, width: 70, height: 43)
        NSColor(calibratedWhite: 0.08, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: miniature, xRadius: 2, yRadius: 2).fill()
        NSColor(calibratedWhite: 0.82, alpha: 0.9).setStroke()
        let miniatureBorder = NSBezierPath(roundedRect: miniature, xRadius: 2, yRadius: 2)
        miniatureBorder.lineWidth = 1
        miniatureBorder.stroke()

        let normalized = definition.kind.thumbnailRect
        let layoutFrame = CGRect(
            x: miniature.minX + miniature.width * normalized.x,
            y: miniature.minY + miniature.height * normalized.y,
            width: max(2, miniature.width * normalized.width),
            height: max(2, miniature.height * normalized.height)
        )
        accent.setFill()
        NSBezierPath(roundedRect: layoutFrame, xRadius: 1, yRadius: 1).fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let layoutBorder = NSBezierPath(roundedRect: layoutFrame, xRadius: 1, yRadius: 1)
        layoutBorder.lineWidth = 1
        layoutBorder.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        (definition.name as NSString).draw(
            in: CGRect(x: 6, y: 57, width: bounds.width - 12, height: 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
        )
    }
}

private final class DragPreviewView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 3
        layer?.cornerRadius = 6
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private final class DragTopStripView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.94)
            .cgColor
        layer?.borderColor = NSColor.systemBlue.cgColor
        layer?.borderWidth = 2
        layer?.cornerRadius = 12
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
