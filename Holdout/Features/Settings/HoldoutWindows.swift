//
//  HoldoutWindows.swift
//  Holdout
//

import AppKit
import SwiftUI

/// Holdout's two windows, Settings and the welcome guide, hosted in AppKit windows so Settings
/// can be resized and remembers its frame (SwiftUI's `Settings` scene is fixed-size).
///
/// A background (accessory) app's activation is only a request on macOS 14+, so its windows open
/// behind whatever is frontmost. While one is open Holdout becomes a regular app (Dock icon,
/// frontmost), and goes back to the background when the last one closes, so the strip's native ✕
/// keeps working.
@MainActor
enum HoldoutWindows {
    private static var settings: NSWindow?
    private static var welcome: NSWindow?
    private static let delegate = Delegate()

    static func showSettings(_ pane: SettingsPane? = nil) {
        let window = settings ?? makeSettings()
        settings = window
        if let pane { NotificationCenter.default.post(name: .holdoutSelectSettingsTab, object: pane.rawValue) }
        bringForward(window)
    }

    static func showWelcome() {
        let window = welcome ?? makeWelcome()
        welcome = window
        bringForward(window)
    }

    static func closeWelcome() {
        welcome?.close()
    }

    /// The open Settings window, for `SettingsSnapshot`.
    static var settingsWindow: NSWindow? { settings }

    private static func makeSettings() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        hosting.sizingOptions = [.minSize]
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = SettingsPane.general.title
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.setContentSize(NSSize(width: 780, height: 580))
        window.center()
        window.setFrameAutosaveName("HoldoutSettings")
        return window
    }

    private static func makeWelcome() -> NSWindow {
        let hosting = NSHostingController(rootView: WelcomeView())
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Holdout"
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.center()
        return window
    }

    private static func bringForward(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private final class Delegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated {
                let closing = notification.object as? NSWindow
                if closing === HoldoutWindows.welcome {
                    UserDefaults.standard.set(true, forKey: HoldoutSettings.Key.didOnboard)
                }
                let others = [HoldoutWindows.settings, HoldoutWindows.welcome].compactMap { $0 }
                    .filter { $0 !== closing && $0.isVisible }
                if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}

extension Notification.Name {
    /// Object: a `SettingsPane` raw value.
    static let holdoutSelectSettingsTab = Notification.Name("holdoutSelectSettingsTab")
}
