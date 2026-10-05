//
//  CursorChat.swift
//  Holdout
//

import AppKit
import ApplicationServices
import OSLog

/// Types a prompt into Cursor's current chat. An idle Cursor chat has no hook or URL that
/// takes a message, so this brings Cursor forward, checks through Accessibility that the
/// focused field is a chat-like text input (a paste into the editor or terminal would be
/// destructive), pastes and presses Return.
enum CursorChat {
    enum Outcome {
        case sent
        case needsAccessibility
        /// Focus isn't in a field that looks like the chat input; nothing was typed.
        case focusNotInChat
    }

    private static let log = Logger(subsystem: "com.egemen.Holdout", category: "cursor-chat")

    /// Fields whose accessibility labels say they are not the chat input.
    private static let notChat = ["editor content", "terminal", "source control", "commit message", "filter"]

    static func send(_ prompt: String, bundleID: String) async -> Outcome {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            return .needsAccessibility
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let app = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        else { return .focusNotInChat }

        for _ in 0..<30 where NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return .focusNotInChat }

        // Chromium builds its accessibility tree only once asked, which takes a moment.
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var focus: Focus?
        for _ in 0..<30 {
            focus = Focus(in: element)
            if focus?.role != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        log.info("focus: \(focus?.summary ?? "none", privacy: .public)")
        guard let focus, focus.isChatLike else { return .focusNotInChat }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        press(key: 9, flags: .maskCommand) // V
        try? await Task.sleep(for: .milliseconds(250))
        press(key: 36, flags: []) // Return
        try? await Task.sleep(for: .milliseconds(400))
        if let previous {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
        return .sent
    }

    private static func press(key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The element that has keyboard focus in Cursor.
    private struct Focus {
        let role: String?
        let labels: String

        init?(in app: AXUIElement) {
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                  let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
            else { return nil }
            let element = focused as! AXUIElement
            func text(_ attribute: String) -> String? {
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
                return value as? String
            }
            role = text(kAXRoleAttribute)
            labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute, kAXHelpAttribute]
                .compactMap(text).joined(separator: " | ")
        }

        var summary: String { "\(role ?? "?") [\(labels.prefix(120))]" }

        var isChatLike: Bool {
            guard role == kAXTextAreaRole || role == kAXTextFieldRole else { return false }
            return !CursorChat.notChat.contains { labels.localizedCaseInsensitiveContains($0) }
        }
    }
}
