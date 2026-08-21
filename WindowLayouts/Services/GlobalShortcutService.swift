// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon
import Foundation

nonisolated struct ShortcutRegistrationFailure: Equatable, Identifiable, Sendable {
    let actionID: ShortcutActionID
    let status: OSStatus

    var id: ShortcutActionID { actionID }

    var message: String {
        if status == OSStatus(eventHotKeyExistsErr) {
            return String(localized: "macOS reported that this shortcut is unavailable.")
        }
        return String(localized: "macOS could not register this shortcut (error \(status)).")
    }
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    var onAction: ((ShortcutActionID) -> Void)? { get set }

    func replaceRegistrations(
        _ assignments: [ShortcutActionID: KeyboardShortcut]
    ) -> [ShortcutRegistrationFailure]
    func stop()
}

@MainActor
final class CarbonGlobalShortcutService: GlobalShortcutRegistering {
    var onAction: ((ShortcutActionID) -> Void)?

    private static let signature: OSType = 0x574C6179 // "WLay"

    private var eventHandler: EventHandlerRef?
    private var handlerInstallStatus: OSStatus = noErr
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var actionsByNumericID: [UInt32: ShortcutActionID] = [:]

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        handlerInstallStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func replaceRegistrations(
        _ assignments: [ShortcutActionID: KeyboardShortcut]
    ) -> [ShortcutRegistrationFailure] {
        unregisterAll()

        guard handlerInstallStatus == noErr else {
            return assignments.keys.map {
                ShortcutRegistrationFailure(actionID: $0, status: handlerInstallStatus)
            }
        }

        var failures: [ShortcutRegistrationFailure] = []
        var used: Set<KeyboardShortcutIdentity> = []
        let orderedAssignments = assignments.sorted { $0.key.rawValue < $1.key.rawValue }

        for (offset, assignment) in orderedAssignments.enumerated() {
            let actionID = assignment.key
            let shortcut = assignment.value
            guard used.insert(shortcut.identity).inserted else {
                failures.append(
                    ShortcutRegistrationFailure(
                        actionID: actionID,
                        status: OSStatus(eventHotKeyExistsErr)
                    )
                )
                continue
            }

            let numericID = UInt32(offset + 1)
            let hotKeyID = EventHotKeyID(
                signature: Self.signature,
                id: numericID
            )
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                carbonModifiers(for: shortcut.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyNoOptions),
                &reference
            )

            if status == noErr, let reference {
                registrations[numericID] = reference
                actionsByNumericID[numericID] = actionID
            } else {
                failures.append(
                    ShortcutRegistrationFailure(actionID: actionID, status: status)
                )
            }
        }

        return failures
    }

    func stop() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func unregisterAll() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
        actionsByNumericID.removeAll()
    }

    private func receive(numericID: UInt32) {
        guard let actionID = actionsByNumericID[numericID] else { return }
        onAction?(actionID)
    }

    private func carbonModifiers(
        for modifiers: KeyboardShortcutModifiers
    ) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static let eventHandlerCallback: EventHandlerUPP = {
        _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        let service = Unmanaged<CarbonGlobalShortcutService>
            .fromOpaque(userData)
            .takeUnretainedValue()
        Task { @MainActor in
            service.receive(numericID: hotKeyID.id)
        }
        return noErr
    }
}
