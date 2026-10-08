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
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
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

/// The menu bar icon. It's built at launch, which makes it the place to open Settings on first run.
private struct MenuBarLabel: View {
    let icon: NSImage
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: icon)
            .onAppear {
                guard !UserDefaults.standard.bool(forKey: "didOnboard") else { return }
                UserDefaults.standard.set(true, forKey: "didOnboard")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApp.activate()
                    openSettings()
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let touchBar = TouchBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        HoldoutSettings.registerDefaults()
        Task { await AgentInstaller.refreshIfInstalled() }
        if touchBar.install() {
            print("Holdout: Control Strip item installed")
        } else {
            print("Holdout: private Touch Bar API unavailable on this macOS")
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
