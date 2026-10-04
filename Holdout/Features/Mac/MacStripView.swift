//
//  MacStripView.swift
//  Holdout
//

import AppKit

/// The Mac tab: a quiet summary, or what's wrong and who's causing it.
final class MacStripView: NSView {
    private static let warningBezel = NSColor(srgbRed: 0.40, green: 0.24, blue: 0.02, alpha: 1)
    private static let criticalBezel = NSColor(srgbRed: 0.42, green: 0.08, blue: 0.08, alpha: 1)
    private static let confirmWindow: TimeInterval = 4

    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private var processes: [String: ProcessUsage] = [:]
    /// A process name awaiting its second tap, and until when.
    private var pendingQuit: (name: String, until: Date)?

    override init(frame: NSRect) {
        super.init(frame: frame)

        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = stack
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(_ snapshot: MacSnapshot?, now: Date = .now) {
        guard let snapshot else {
            stack.setViews([], in: .leading)
            return
        }
        if let pending = pendingQuit, pending.until < now {
            pendingQuit = nil
        }

        var views: [NSView] = []
        var culprits: [ProcessUsage] = []

        for alert in snapshot.alerts {
            switch alert {
            case let .pressure(level, since):
                let chip = chip(symbol: "memorychip", tint: .white, title: level == .critical ? "Memory critical" : "Memory pressure high", detail: Self.duration(since: since, now: now))
                chip.bezelColor = level == .critical ? Self.criticalBezel : Self.warningBezel
                views.append(chip)
            case let .swapSurge(bytes):
                let chip = chip(symbol: "arrow.up.right", tint: .white, title: "Swap +\(Self.gigabytes(bytes))", detail: "in 5 min")
                chip.bezelColor = Self.warningBezel
                views.append(chip)
            case let .hog(usage, since):
                culprits.append(usage)
                views.append(processChip(usage, detail: "\(Int(usage.cpu))% CPU · \(Self.duration(since: since, now: now))", bezel: Self.criticalBezel, now: now))
            }
        }

        // Memory trouble: name who's using it.
        if snapshot.alerts.contains(where: \.isMemory) {
            for usage in snapshot.topMemory where !culprits.contains(where: { $0.name == usage.name }) {
                culprits.append(usage)
                views.append(processChip(usage, detail: Self.gigabytes(usage.footprint), bezel: nil, now: now))
            }
        }
        processes = Dictionary(culprits.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        views += summary(snapshot, quiet: snapshot.alerts.isEmpty)
        stack.setViews(views, in: .leading)
    }

    /// Memory, swap, and CPU at a glance; after the alerts when there are any.
    private func summary(_ snapshot: MacSnapshot, quiet: Bool) -> [NSView] {
        let (dot, level): (NSColor, String) = switch snapshot.pressure {
        case .normal: (.systemGreen, "Memory normal")
        case .warning: (.systemOrange, "Memory pressure")
        case .critical: (.systemRed, "Memory critical")
        }
        var views: [NSView] = []
        if quiet {
            views.append(chip(symbol: "circle.fill", tint: dot, title: level, detail: "\(Self.gigabytes(snapshot.memoryUsed)) of \(Self.gigabytes(snapshot.memoryTotal, decimals: 0))"))
        }
        let growth = snapshot.swapGrowth > 256 * 1024 * 1024 ? "+\(Self.gigabytes(UInt64(snapshot.swapGrowth))) in 5m" : ""
        views.append(chip(symbol: "externaldrive", tint: .secondaryLabelColor, title: "Swap \(Self.gigabytes(snapshot.swapUsed))", detail: growth))
        views.append(chip(symbol: "cpu", tint: .secondaryLabelColor, title: "CPU \(Int(snapshot.cpu.rounded()))%", detail: ""))
        return views
    }

    private func processChip(_ usage: ProcessUsage, detail: String, bezel: NSColor?, now: Date) -> NSButton {
        let isConfirming = pendingQuit?.name == usage.name
        let button = chip(
            symbol: isConfirming ? "xmark.circle" : (Self.app(for: usage) != nil ? "app" : "gearshape"),
            tint: .white,
            title: isConfirming ? "Quit \(usage.name)?" : usage.name,
            detail: isConfirming ? "tap again" : detail
        )
        button.bezelColor = isConfirming ? Self.criticalBezel : bezel
        button.identifier = NSUserInterfaceItemIdentifier(usage.name)
        button.target = self
        button.action = #selector(tapProcess(_:))
        return button
    }

    /// Apps quit on a second tap (they can still ask to save); anything else opens Activity Monitor.
    @objc private func tapProcess(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue, let usage = processes[name] else { return }
        guard let app = Self.app(for: usage) else {
            if let monitor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                NSWorkspace.shared.openApplication(at: monitor, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        if pendingQuit?.name == name {
            pendingQuit = nil
            app.terminate()
        } else {
            pendingQuit = (name, .now.addingTimeInterval(Self.confirmWindow))
        }
    }

    /// The regular (Dock) app behind a process name, if it is one.
    private static func app(for usage: ProcessUsage) -> NSRunningApplication? {
        usage.pids.lazy
            .compactMap { NSRunningApplication(processIdentifier: $0) }
            .first { $0.activationPolicy == .regular }
    }

    private func chip(symbol: String, tint: NSColor, title: String, detail: String) -> NSButton {
        let font = NSFont.systemFont(ofSize: 14)
        let text = NSMutableAttributedString(string: title, attributes: [.foregroundColor: NSColor.labelColor, .font: font])
        if !detail.isEmpty {
            text.append(NSAttributedString(string: "  " + detail, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        }
        let button = NSButton(title: "", target: nil, action: nil)
        button.attributedTitle = text
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        return button
    }

    private static func gigabytes(_ bytes: UInt64, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f GB", Double(bytes) / 1_073_741_824)
    }

    private static func duration(since: TimeInterval, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince1970 - since) / 60
        return minutes < 1 ? "just now" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
