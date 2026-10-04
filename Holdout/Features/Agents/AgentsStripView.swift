//
//  AgentsStripView.swift
//  Holdout
//

import AppKit

/// The Agents tab: one pill per Claude Code session, scrolling sideways when there are many.
final class AgentsStripView: NSView {
    var onSelect: ((ClaudeSession) -> Void)?

    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No Claude Code sessions active")
    private var shown: [ClaudeSession] = []

    private static let font = NSFont.systemFont(ofSize: 14)
    private static let waitingBezel = NSColor(srgbRed: 0.40, green: 0.24, blue: 0.02, alpha: 1)

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

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(_ sessions: [ClaudeSession], now: Date = .now) {
        shown = sessions
        emptyLabel.isHidden = !sessions.isEmpty
        stack.setViews(sessions.enumerated().map { pill(for: $1, tag: $0, now: now) }, in: .leading)
    }

    private func pill(for session: ClaudeSession, tag: Int, now: Date) -> NSButton {
        let (dotColor, status) = Self.describe(session.state)
        let title = NSMutableAttributedString()
        title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor, .font: Self.font]))
        title.append(NSAttributedString(string: session.project, attributes: [.foregroundColor: NSColor.labelColor, .font: Self.font]))
        title.append(NSAttributedString(string: "  " + status, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: Self.font]))
        if session.state.isWorking {
            let elapsed = Self.elapsed(since: session.turnStartedAt, now: now)
            title.append(NSAttributedString(string: "  " + elapsed, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: Self.font]))
        }

        let button = NSButton(title: "", target: self, action: #selector(select(_:)))
        button.attributedTitle = title
        button.tag = tag
        button.bezelColor = session.state == .waiting ? Self.waitingBezel : nil
        return button
    }

    @objc private func select(_ sender: NSButton) {
        guard shown.indices.contains(sender.tag) else { return }
        onSelect?(shown[sender.tag])
    }

    private static func describe(_ state: ClaudeSession.State) -> (NSColor, String) {
        switch state {
        case .waiting: (.systemOrange, "needs you")
        case .thinking: (.systemBlue, "thinking")
        case let .tool(name, detail): (.systemBlue, detail.map { "\(name) · \(shorten($0))" } ?? name)
        case .done: (.systemGreen, "done")
        case .idle: (.secondaryLabelColor, "idle")
        }
    }

    /// File paths become their file name; anything else is cut to fit a pill.
    private static func shorten(_ detail: String) -> String {
        let text = detail.hasPrefix("/") ? URL(fileURLWithPath: detail).lastPathComponent : detail
        let firstLine = text.prefix { $0 != "\n" }
        return firstLine.count > 26 ? firstLine.prefix(25) + "…" : String(firstLine)
    }

    private static func elapsed(since start: TimeInterval, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970 - start))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
