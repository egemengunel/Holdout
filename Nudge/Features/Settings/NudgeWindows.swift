//
//  NudgeWindows.swift
//  Nudge
//

import AppKit
import SwiftUI

/// Nudge's two windows. Settings is a SwiftUI `Window` scene, so the system builds its chrome
/// like Apple's own apps (a floating sidebar holding the traffic lights on macOS 26+); the
/// welcome guide is an AppKit window with a hidden title bar.
///
/// A background (accessory) app's activation is only a request on macOS 14+, so its windows open
/// behind whatever is frontmost. While one is open Nudge becomes a regular app (Dock icon,
/// frontmost), and goes back to the background when the last one closes, so the strip's native ✕
/// keeps working.
@MainActor
enum NudgeWindows {
    static let settingsID = "settings"
    /// SwiftUI's action for opening scenes, captured from the menu bar label, which exists from launch.
    static var openWindow: OpenWindowAction?
    private static var settings: NSWindow?
    private static var welcome: NSWindow?
    private static let delegate = Delegate()
    private static var closeObserver: NSObjectProtocol?
    /// Whether Nudge asked for Settings. SwiftUI also opens a `Window` scene at launch and
    /// restores it after a relaunch (only macOS 15+ can turn that off), so an unasked one closes.
    private(set) static var settingsRequested = false

    static func showSettings(_ pane: SettingsPane? = nil) {
        settingsRequested = true
        // Before activating: an existing window on another desktop would otherwise pull you there.
        existingSettingsWindow?.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow?(id: settingsID)
        if let pane { NotificationCenter.default.post(name: .nudgeSelectSettingsTab, object: pane.rawValue) }
        // The window exists only after SwiftUI handles the action.
        DispatchQueue.main.async {
            guard let window = existingSettingsWindow else { return }
            settings = window
            window.isRestorable = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            guard closeObserver == nil else { return }
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                    closeObserver = nil
                    settings = nil
                    settingsRequested = false
                    if welcome?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }

    private static var existingSettingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(settingsID) == true }
    }

    static func showWelcome() {
        let window = welcome ?? makeWelcome()
        welcome = window
        bringForward(window)
    }

    static func closeWelcome() {
        welcome?.close()
    }

    /// Closes a Settings window SwiftUI opened on its own; called as `SettingsView` appears.
    static func closeIfUnrequested() {
        guard !settingsRequested else { return }
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(settingsID) == true {
            window.close()
        }
    }

    /// The open Settings window, for `SettingsSnapshot`.
    static var settingsWindow: NSWindow? { settings }

    private static func makeWelcome() -> NSWindow {
        let hosting = NSHostingController(rootView: WelcomeView())
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Nudge"
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        return window
    }

    /// Shows the window on the current desktop, centered on the display the pointer is on,
    /// before activating, so activation never switches desktops.
    private static func bringForward(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        // SwiftUI sizes the window only after it shows; size it now so the centering holds.
        if let content = window.contentViewController?.view, content.fittingSize.width > 0 {
            window.setContentSize(content.fittingSize)
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        window.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private final class Delegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated {
                let closing = notification.object as? NSWindow
                if closing === NudgeWindows.welcome {
                    UserDefaults.standard.set(true, forKey: NudgeSettings.Key.didOnboard)
                }
                let others = [NudgeWindows.settings, NudgeWindows.welcome].compactMap { $0 }
                    .filter { $0 !== closing && $0.isVisible }
                if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}

extension Notification.Name {
    /// Object: a `SettingsPane` raw value.
    static let nudgeSelectSettingsTab = Notification.Name("nudgeSelectSettingsTab")
    /// Posted after an agent is connected or removed.
    static let nudgeAgentsChanged = Notification.Name("nudgeAgentsChanged")
}
