//
//  NudgeApp.swift
//  Nudge
//
//  Created by Egemen Günel on 4.10.2026.
//

import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // Nudge is a background app (LSUIElement): no Dock icon and no window, so it's
        // almost never frontmost and the system always draws the strip's native ✕.
        MenuBarExtra {
            Button("Settings…") { NudgeWindows.showSettings() }
                .keyboardShortcut(",")
            Button("Welcome Guide…") { NudgeWindows.showWelcome() }
            Divider()
            Button("Quit Nudge") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            MenuBarLabel(icon: Self.menuBarIcon)
        }

        // A `Window` rather than a `Settings` scene, which can't be resized. Opened through
        // `NudgeWindows.showSettings`, which also makes Nudge a regular app meanwhile.
        settings
    }

    private var settings: some Scene {
        Window("Settings", id: NudgeWindows.settingsID) {
            SettingsView()
        }
        .defaultSize(width: 780, height: 580)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { NudgeWindows.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }

    /// `systemImage:` draws the symbol smaller than other menu bar items; this matches their size.
    private static let menuBarIcon: NSImage = {
        let image = NSImage(systemSymbolName: "rectangle.and.hand.point.up.left.fill", accessibilityDescription: "Nudge")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))!
        image.isTemplate = true
        return image
    }()
}

/// The menu bar icon. It exists from launch, so it hands SwiftUI's window opener to `NudgeWindows`.
private struct MenuBarLabel: View {
    let icon: NSImage
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: icon)
            .onAppear { NudgeWindows.openWindow = openWindow }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let touchBar = TouchBarController()
    /// Nudge is a windowless background app, which macOS's App Nap throttles hard: its timers
    /// slip to many seconds, so the strip and icon stalled until a restart. This opts out.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NudgeSettings.registerDefaults()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Keeping the Touch Bar status current")
        Task { await AgentInstaller.refreshIfInstalled() }
        // Debug aid: `-NudgeNoTouchBar YES` leaves the Control Strip alone, so a second copy
        // can show its windows without taking the slot from the running one.
        if UserDefaults.standard.bool(forKey: "NudgeNoTouchBar") {
            print("Nudge: Touch Bar skipped")
        } else if touchBar.install() {
            print("Nudge: Control Strip item installed")
        } else {
            print("Nudge: private Touch Bar API unavailable on this macOS")
        }

        // First run opens the welcome guide. Debug aids: `-NudgeOpenSettings YES` and
        // `-NudgeOpenWelcome YES` open those windows at launch, for screenshots.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "NudgeOpenSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NudgeWindows.showSettings() }
        } else if defaults.bool(forKey: "NudgeOpenWelcome") || !defaults.bool(forKey: NudgeSettings.Key.didOnboard) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NudgeWindows.showWelcome() }
        }

        // Debug aid: `-NudgeSnapshot <dir>` writes PNGs of every strip tab and Settings tab
        // from the views themselves, for when the display is off.
        if let path = UserDefaults.standard.string(forKey: "NudgeSnapshot") {
            let directory = URL(fileURLWithPath: path)
            Task {
                try? await Task.sleep(for: .seconds(3))
                await touchBar.snapshotTouchBar(to: directory)
                await SettingsSnapshot.run(to: directory)
            }
        }

        // Debug aid: `-NudgeOpenOnLaunch YES` opens the strip so it can be inspected with `screencapture -b`.
        if UserDefaults.standard.bool(forKey: "NudgeOpenOnLaunch") {
            touchBar.openStrip()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [touchBar] in
                NSLog("Nudge layout:\n%@", touchBar.dumpLayout())
            }
        }
    }
}

/// Renders the open Settings window, pane by pane, into PNGs (see `-NudgeSnapshot`).
@MainActor
enum SettingsSnapshot {
    static func run(to directory: URL) async {
        NudgeWindows.showSettings()
        for pane in SettingsPane.allCases {
            NotificationCenter.default.post(name: .nudgeSelectSettingsTab, object: pane.rawValue)
            try? await Task.sleep(for: .seconds(1))
            guard let frame = NudgeWindows.settingsWindow?.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "settings-\(pane.rawValue).png"))
        }
    }
}
