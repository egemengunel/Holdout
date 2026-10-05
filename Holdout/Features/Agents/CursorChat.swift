//
//  CursorChat.swift
//  Holdout
//

import AppKit
import ApplicationServices
import OSLog

/// Types a prompt into Cursor's current chat. An idle Cursor chat has no hook or URL that
/// takes a message, so this brings Cursor forward, checks through Accessibility that the
/// focused field is the chat input, pastes and presses Return. The check is an allow-list:
/// a paste plus Return in Find, Rename or the editor would be destructive, so anything not
/// positively recognized falls back to the clipboard.
enum CursorChat {
    enum Outcome {
        case sent
        case needsAccessibility
        /// Focus isn't in a field that looks like the chat input; nothing was typed.
        case focusNotInChat
    }

    private static let log = Logger(subsystem: "com.egemen.Holdout", category: "cursor-chat")

    /// Web class names or ids (on the field or its ancestors) that mark Cursor's chat input.
    private static let chatMarkers = ["aislash", "composer", "aichat", "chat-input"]
    /// Placeholder or label text of the chat input.
    private static let chatPhrases = ["follow-up", "follow up", "plan, search", "build anything", "ask anything"]
    /// Anything inside the code editor (Find, Rename, the text itself) is never the chat.
    private static let editorMarkers = ["monaco", "editor-container", "find-widget", "rename"]
    /// How many ancestors to look through for markers.
    private static let ancestorDepth = 10

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

        // Borrow the clipboard, then give back everything on it (images and files too).
        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        let borrowed = pasteboard.changeCount
        press(key: 9, flags: .maskCommand) // V
        try? await Task.sleep(for: .milliseconds(250))
        press(key: 36, flags: []) // Return
        try? await Task.sleep(for: .milliseconds(400))
        // Only if nothing else copied in the meantime; that newer content is the user's.
        if pasteboard.changeCount == borrowed {
            pasteboard.clearContents()
            if !saved.isEmpty {
                pasteboard.writeObjects(saved)
            }
        }
        return .sent
    }

    /// A copy of every item on the pasteboard with all of its representations.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
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
        /// Web class names and ids of the element and its ancestors, nearest first.
        let markup: String

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
            markup = Self.markup(from: element)
        }

        /// Chromium exposes each node's DOM classes and id to Accessibility.
        private static func markup(from element: AXUIElement) -> String {
            var parts: [String] = []
            var current: AXUIElement? = element
            for _ in 0..<CursorChat.ancestorDepth {
                guard let node = current else { break }
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, "AXDOMClassList" as CFString, &value) == .success,
                   let classes = value as? [String] {
                    parts += classes
                }
                if AXUIElementCopyAttributeValue(node, "AXDOMIdentifier" as CFString, &value) == .success,
                   let id = value as? String, !id.isEmpty {
                    parts.append("#" + id)
                }
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent) == .success,
                      let parent, CFGetTypeID(parent) == AXUIElementGetTypeID()
                else { break }
                current = (parent as! AXUIElement)
            }
            return parts.joined(separator: " ")
        }

        var summary: String { "\(role ?? "?") [\(labels.prefix(120))] {\(markup.prefix(300))}" }

        /// A text input recognized as the chat, and not inside the code editor.
        var isChatLike: Bool {
            guard role == kAXTextAreaRole || role == kAXTextFieldRole else { return false }
            let markup = markup.lowercased()
            if CursorChat.editorMarkers.contains(where: markup.contains) { return false }
            return CursorChat.chatMarkers.contains(where: markup.contains)
                || CursorChat.chatPhrases.contains { labels.localizedCaseInsensitiveContains($0) }
        }
    }
}
