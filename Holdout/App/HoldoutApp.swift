//
//  HoldoutApp.swift
//  Holdout
//
//  Created by Egemen Günel on 4.10.2026.
//

import SwiftUI

@main
struct HoldoutApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // Holdout is a background app (LSUIElement): no Dock icon and no window, so it's
        // almost never frontmost and the system always draws the strip's native ✕.
        MenuBarExtra {
            SettingsButton()
            Divider()
            Button("Quit Holdout") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            MenuBarLabel(icon: Self.menuBarIcon)
        }
        Settings { SettingsView() }
    }

    /// `systemImage:` draws the symbol smaller than other menu bar items; this matches their size.
    private static let menuBarIcon: NSImage = {
        let image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Holdout")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))!
        image.isTemplate = true
        return image
    }()
}

private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") { SettingsWindow.bringForward(openSettings) }
            .keyboardShortcut(",")
    }
}

/// A background (accessory) app's activation is only a request on macOS 14+, so its Settings
/// window opens behind whatever is frontmost. While Settings is open Holdout becomes a regular
/// app (Dock icon, frontmost), and goes back to the background when the window closes, so the
/// strip's native ✕ keeps working.
enum SettingsWindow {
    private static var closeObserver: NSObjectProtocol?

    static func bringForward(_ openSettings: OpenSettingsAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        // The window exists only after SwiftUI handles the action.
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" || $0.title.hasSuffix("Settings") }) else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            guard closeObserver == nil else { return }
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    NSApp.setActivationPolicy(.accessory)
                    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                    closeObserver = nil
                }
            }
        }
    }
}

/// The menu bar icon. It's built at launch, which makes it the place to open Settings on first run.
private struct MenuBarLabel: View {
    let icon: NSImage
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: icon)
            .onAppear {
                // Debug aid: `-HoldoutOpenSettings YES` opens Settings at launch, for screenshots.
                if UserDefaults.standard.bool(forKey: "HoldoutOpenSettings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsWindow.bringForward(openSettings) }
                    return
                }
                guard !UserDefaults.standard.bool(forKey: "didOnboard") else { return }
                UserDefaults.standard.set(true, forKey: "didOnboard")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    SettingsWindow.bringForward(openSettings)
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let touchBar = TouchBarController()
    /// Holdout is a windowless background app, which macOS's App Nap throttles hard: its timers
    /// slip to many seconds, so the strip and icon stalled until a restart. This opts out.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HoldoutSettings.registerDefaults()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Keeping the Touch Bar status current")
        Task { await AgentInstaller.refreshIfInstalled() }
        if touchBar.install() {
            print("Holdout: Control Strip item installed")
        } else {
            print("Holdout: private Touch Bar API unavailable on this macOS")
        }

        // Debug aid: `-HoldoutSnapshot <dir>` writes PNGs of every strip tab and Settings tab
        // from the views themselves, for when the display is off.
        if let path = UserDefaults.standard.string(forKey: "HoldoutSnapshot") {
            let directory = URL(fileURLWithPath: path)
            Task {
                try? await Task.sleep(for: .seconds(3))
                await touchBar.snapshotTouchBar(to: directory)
                await SettingsSnapshot.run(to: directory)
            }
        }

        // Debug aid: `-HoldoutOpenOnLaunch YES` opens the strip so it can be inspected with `screencapture -b`.
        if UserDefaults.standard.bool(forKey: "HoldoutOpenOnLaunch") {
            touchBar.openStrip()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [touchBar] in
                NSLog("Holdout layout:\n%@", touchBar.dumpLayout())
            }
        }
    }
}

/// Renders the open Settings window, tab by tab, into PNGs (see `-HoldoutSnapshot`).
@MainActor
enum SettingsSnapshot {
    static func run(to directory: URL) async {
        for tab in ["General", "Agents", "Project", "Alerts", "About"] {
            NotificationCenter.default.post(name: .holdoutSelectSettingsTab, object: tab)
            try? await Task.sleep(for: .seconds(1))
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" || $0.title.hasSuffix("Settings") || $0.title == tab }),
                  let frame = window.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "settings-\(tab).png"))
        }
    }
}

extension Notification.Name {
    static let holdoutSelectSettingsTab = Notification.Name("holdoutSelectSettingsTab")
}
