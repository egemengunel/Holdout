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
            Button("Settings…") { HoldoutWindows.showSettings() }
                .keyboardShortcut(",")
            Button("Welcome Guide…") { HoldoutWindows.showWelcome() }
            Divider()
            Button("Quit Holdout") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .commands {
            // Settings is an AppKit-hosted window (see `HoldoutWindows`), so the App menu's
            // item, shown while Settings makes Holdout a regular app, opens it by hand.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { HoldoutWindows.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }

    /// `systemImage:` draws the symbol smaller than other menu bar items; this matches their size.
    private static let menuBarIcon: NSImage = {
        let image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Holdout")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))!
        image.isTemplate = true
        return image
    }()
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
        // Debug aid: `-HoldoutNoTouchBar YES` leaves the Control Strip alone, so a second copy
        // can show its windows without taking the slot from the running one.
        if UserDefaults.standard.bool(forKey: "HoldoutNoTouchBar") {
            print("Holdout: Touch Bar skipped")
        } else if touchBar.install() {
            print("Holdout: Control Strip item installed")
        } else {
            print("Holdout: private Touch Bar API unavailable on this macOS")
        }

        // First run opens the welcome guide. Debug aids: `-HoldoutOpenSettings YES` and
        // `-HoldoutOpenWelcome YES` open those windows at launch, for screenshots.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "HoldoutOpenSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { HoldoutWindows.showSettings() }
        } else if defaults.bool(forKey: "HoldoutOpenWelcome") || !defaults.bool(forKey: HoldoutSettings.Key.didOnboard) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { HoldoutWindows.showWelcome() }
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

/// Renders the open Settings window, pane by pane, into PNGs (see `-HoldoutSnapshot`).
@MainActor
enum SettingsSnapshot {
    static func run(to directory: URL) async {
        HoldoutWindows.showSettings()
        for pane in SettingsPane.allCases {
            NotificationCenter.default.post(name: .holdoutSelectSettingsTab, object: pane.rawValue)
            try? await Task.sleep(for: .seconds(1))
            guard let frame = HoldoutWindows.settingsWindow?.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "settings-\(pane.rawValue).png"))
        }
    }
}
