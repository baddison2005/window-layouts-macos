// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut?
    let onChange: (KeyboardShortcut?) -> Bool
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: shortcut?.displayName ?? String(localized: "Record Shortcut"),
            target: context.coordinator,
            action: #selector(Coordinator.beginRecording(_:))
        )
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 138).isActive = true
        updateAccessibility(for: button, recording: false)
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.isRecording {
            button.title = shortcut?.displayName ?? String(localized: "Record Shortcut")
            updateAccessibility(for: button, recording: false)
        }
    }

    private func updateAccessibility(for button: NSButton, recording: Bool) {
        button.setAccessibilityLabel(String(localized: "Global keyboard shortcut"))
        button.setAccessibilityValue(shortcut?.displayName)
        button.setAccessibilityHelp(
            recording
                ? String(localized: "Type the shortcut now. Press Escape to cancel or Delete to clear it.")
                : String(localized: "Press to record a global keyboard shortcut.")
        )
    }

    static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ShortcutRecorder
        weak var button: NSButton?
        var isRecording = false
        private var keyMonitor: Any?

        init(parent: ShortcutRecorder) {
            self.parent = parent
        }

        @objc func beginRecording(_ sender: NSButton) {
            stopRecording()
            isRecording = true
            sender.title = String(localized: "Type shortcut…")
            parent.updateAccessibility(for: sender, recording: true)
            sender.window?.makeFirstResponder(sender)

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                self?.handle(event)
                return nil
            }
        }

        func stopRecording() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            isRecording = false
            button?.title = parent.shortcut?.displayName ?? String(localized: "Record Shortcut")
            if let button {
                parent.updateAccessibility(for: button, recording: false)
            }
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return
            }
            if event.keyCode == UInt16(kVK_Delete)
                || event.keyCode == UInt16(kVK_ForwardDelete) {
                _ = parent.onChange(nil)
                stopRecording()
                return
            }

            guard let keyLabel = ShortcutKeyLabel.label(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers
            ) else {
                parent.onError(String(localized: "That key cannot be used as a global shortcut."))
                return
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: KeyboardShortcutModifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }

            let shortcut = KeyboardShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers,
                keyLabel: keyLabel
            )
            do {
                let validated = try shortcut.validated()
                if parent.onChange(validated) {
                    stopRecording()
                }
            } catch {
                parent.onError(error.localizedDescription)
            }
        }
    }
}

nonisolated enum ShortcutKeyLabel {
    static func label(keyCode: UInt16, characters: String?) -> String? {
        switch Int(keyCode) {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            guard let characters, !characters.isEmpty else { return nil }
            return String(characters.uppercased().prefix(4))
        }
    }
}
