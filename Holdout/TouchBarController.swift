//
//  TouchBarController.swift
//  Holdout
//

import AppKit

/// Owns the Holdout icon in the Control Strip and the full-width strip it opens.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let controlStripID = NSTouchBarItem.Identifier("com.egemen.Holdout.controlStrip")
    private static let closeID = NSTouchBarItem.Identifier("com.egemen.Holdout.close")
    private static let statusID = NSTouchBarItem.Identifier("com.egemen.Holdout.status")
    private static let appearanceID = NSTouchBarItem.Identifier("com.egemen.Holdout.simAppearance")
    private static let pingID = NSTouchBarItem.Identifier("com.egemen.Holdout.ping")

    private let stripButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "Holdout is alive")
    private var isFlagged = false

    private lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.closeID, Self.statusID, .flexibleSpace, Self.appearanceID, Self.pingID]
        return bar
    }()

    /// Returns false when the private Touch Bar API isn't available on this macOS.
    func install() -> Bool {
        stripButton.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Holdout")
        stripButton.bezelStyle = .rounded
        stripButton.target = self
        stripButton.action = #selector(openStrip)

        let item = NSCustomTouchBarItem(identifier: Self.controlStripID)
        item.view = stripButton

        return SystemTouchBar.addToControlStrip(item)
    }

    @objc private func openStrip() {
        SystemTouchBar.present(touchBar, from: Self.controlStripID)
    }

    @objc private func closeStrip() {
        SystemTouchBar.minimize(touchBar)
        SystemTouchBar.showInControlStrip(Self.controlStripID)
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.closeID:
            // The system close box only appears while Holdout is frontmost, which it rarely is.
            return NSButtonTouchBarItem(identifier: identifier, image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Holdout")!, target: self, action: #selector(closeStrip))

        case Self.statusID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = statusLabel
            return item

        case Self.appearanceID:
            let item = NSButtonTouchBarItem(identifier: identifier, title: "Sim", image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Toggle simulator appearance")!, target: self, action: #selector(toggleSimulatorAppearance))
            return item

        case Self.pingID:
            let item = NSButtonTouchBarItem(identifier: identifier, image: NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Flag the Control Strip icon")!, target: self, action: #selector(ping))
            return item

        default:
            return nil
        }
    }

    // MARK: - Actions

    /// Proves the Control Strip icon can change live (later: Claude waiting, build failed).
    @objc private func ping() {
        isFlagged.toggle()
        stripButton.bezelColor = isFlagged ? .systemOrange : nil
        statusLabel.stringValue = isFlagged ? "Icon flagged — check the Control Strip" : "Holdout is alive"
    }

    @objc private func toggleSimulatorAppearance() {
        statusLabel.stringValue = "Asking the simulator…"
        Task {
            let current = await Shell.xcrun(["simctl", "ui", "booted", "appearance"])
            guard current.status == 0 else {
                statusLabel.stringValue = "No booted simulator"
                return
            }
            let next = current.output.contains("dark") ? "light" : "dark"
            let result = await Shell.xcrun(["simctl", "ui", "booted", "appearance", next])
            statusLabel.stringValue = result.status == 0 ? "Simulator → \(next)" : "simctl failed"
        }
    }
}

enum Shell {
    nonisolated static func xcrun(_ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }
}
