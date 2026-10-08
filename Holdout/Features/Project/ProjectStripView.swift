//
//  ProjectStripView.swift
//  Holdout
//

import AppKit

/// The Project tab: which project and branch you're in, news only when there is some
/// (a build result, a TestFlight ship), and the Build and Commit actions.
final class ProjectStripView: NSView {
    enum Action: String {
        case build, commit

        /// The built-in wording as one template, shown in Settings; {project}, {root} and {repo}
        /// stand for the current project.
        var defaultTemplate: String {
            switch self {
            case .build: "Build the Xcode project in {root} (through the Xcode MCP if you have it, otherwise xcodebuild), then list its warnings. If it fails, fix the errors and build again until it is clean. Report the warnings at the end."
            case .commit: "In {root}, review the uncommitted changes for bugs and leftovers, then propose an atomic commit grouping with messages. Do not commit yet: wait for my approval in my next message."
            }
        }

        var title: String {
            switch self {
            case .build: "Build"
            case .commit: "Commit"
            }
        }

        var symbol: String {
            switch self {
            case .build: "hammer"
            case .commit: "checkmark.circle"
            }
        }

        /// The prompt a button sends.
        func prompt(project: ProjectFeed.Project?, repo: ProjectFeed.Repo?) -> String? {
            if let custom = HoldoutSettings.promptOverride(for: rawValue) {
                let name = project?.name ?? repo?.name
                guard let name else { return nil }
                return custom
                    .replacingOccurrences(of: "{project}", with: name)
                    .replacingOccurrences(of: "{root}", with: project?.root ?? repo?.root ?? name)
                    .replacingOccurrences(of: "{repo}", with: repo?.name ?? name)
            }
            let lines: [String]? = switch self {
            case .build: project.map { p in [
                "holdout: the user pressed Build on the Touch Bar for \(p.name).",
                "Build the Xcode project in \(p.root ?? p.name) (through the Xcode MCP if you have it, otherwise xcodebuild), then list its warnings.",
                "If it fails, fix the errors and build again until it is clean. Report the warnings at the end.",
            ] }
            case .commit: repo.map { r in [
                "holdout: the user pressed Review & commit on the Touch Bar for \(r.name).",
                "In \(r.root ?? r.name), review the uncommitted changes for bugs and leftovers, then propose an atomic commit grouping with messages.",
                "Do not commit yet: wait for the user to approve the grouping in their next message.",
            ] }
            }
            return lines?.joined(separator: "\n\n")
        }
    }

    var onCommand: ((Action) -> Void)?

    private static let failedBezel = NSColor(srgbRed: 0.42, green: 0.08, blue: 0.08, alpha: 1)

    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No builds yet")
    /// Says where a button's prompt went when it couldn't go straight into the session.
    private let noteLabel = NSTextField(labelWithString: "")
    private var noteResetTask: Task<Void, Never>?
    private var build: XcodeBuild?
    private var actions: [Action] = []
    /// [ Build | Commit ] as one control, like the tabs and the Sim stepper.
    private lazy var actionControl = NSSegmentedControl(labels: [], trackingMode: .momentary, target: self, action: #selector(runAction))

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
        noteLabel.textColor = .secondaryLabelColor

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

    func update(xcodeBuild: XcodeBuild?, feed: ProjectFeed?, now: Date = .now) {
        build = xcodeBuild
        var views: [NSView] = []

        if let feed, let name = feed.project?.name ?? feed.repo?.name {
            let ahead = feed.ship.flatMap { $0.ahead > 0 ? "\($0.ahead) ahead" : nil }
            let detail = [feed.project?.branch ?? feed.repo?.branch, ahead].compactMap { $0 }.joined(separator: " · ")
            views.append(pill(symbol: "arrow.triangle.branch", tint: .systemPurple, title: name, detail: detail))
            views += news(xcodeBuild: xcodeBuild, feed: feed, now: now)
            if let control = actionsControl(feed) {
                views.append(control)
            }
            if !noteLabel.stringValue.isEmpty {
                views.append(noteLabel)
            }
        } else if let xcodeBuild {
            // No Claude session in a project: just Xcode's latest build, named.
            views.append(buildPill(xcodeBuild, named: true, now: now))
        }

        emptyLabel.isHidden = !views.isEmpty
        stack.setViews(views, in: .leading)
    }

    /// Only what's worth a glance: the newer of Xcode's and Claude's build, a ship in flight.
    private func news(xcodeBuild: XcodeBuild?, feed: ProjectFeed, now: Date) -> [NSView] {
        var views: [NSView] = []
        let claudeBuildIsNewer = feed.build != nil
            && (feed.buildAt ?? 0) > (xcodeBuild?.finishedAt.timeIntervalSince1970 ?? 0)

        if claudeBuildIsNewer, let claude = feed.build {
            let pill = claude.isOk
                ? pill(symbol: "checkmark.circle.fill", tint: .systemGreen, mark: .white, title: Self.ago(Date(timeIntervalSince1970: feed.buildAt ?? 0), now: now), detail: "")
                : pill(symbol: "xmark.octagon.fill", tint: .systemRed, mark: .white, title: Self.plural(claude.errorCount, "error"), detail: claude.firstError.map { Self.shorten($0) } ?? "")
            pill.bezelColor = claude.isOk ? nil : Self.failedBezel
            views.append(pill)
        } else if let xcodeBuild {
            views.append(buildPill(xcodeBuild, named: false, now: now))
        }

        if let ship = feed.ship, ship.phase != "idle" {
            let failed = ship.phase == "failed" || ship.phase == "conflict"
            views.append(pill(symbol: "arrow.up.circle", tint: failed ? .systemRed : .systemBlue, title: "TestFlight", detail: ship.note.map { Self.shorten($0) } ?? ship.phase))
        }

        // Problems first, right after the project chip.
        return views.sorted { ($0 as? NSButton)?.bezelColor == Self.failedBezel && ($1 as? NSButton)?.bezelColor != Self.failedBezel }
    }

    private func buildPill(_ build: XcodeBuild, named: Bool, now: Date) -> NSButton {
        let warnings = build.warnings > 0 ? "\(build.warnings) ⚠︎" : nil
        let pill = build.succeeded
            ? pill(
                symbol: "checkmark.circle.fill", tint: .systemGreen, mark: .white,
                title: named ? build.project : Self.ago(build.finishedAt, now: now),
                detail: [named ? "built \(Self.ago(build.finishedAt, now: now))" : nil, warnings].compactMap { $0 }.joined(separator: " · "),
                action: #selector(openBuild)
            )
            : pill(
                symbol: "xmark.octagon.fill", tint: .systemRed, mark: .white,
                title: named ? build.project : Self.plural(build.errors, "error"),
                detail: [named ? Self.plural(build.errors, "error") : nil, warnings].compactMap { $0 }.joined(separator: " · "),
                action: #selector(openBuild)
            )
        pill.bezelColor = build.succeeded ? nil : Self.failedBezel
        return pill
    }

    private func actionsControl(_ feed: ProjectFeed) -> NSSegmentedControl? {
        actions = (feed.project != nil ? [.build] : []) + (feed.repo != nil ? [.commit] : [])
        guard !actions.isEmpty else { return nil }
        actionControl.segmentCount = actions.count
        for (segment, action) in actions.enumerated() {
            actionControl.setLabel(action.title, forSegment: segment)
            actionControl.setImage(NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil), forSegment: segment)
            actionControl.setWidth(0, forSegment: segment)
        }
        return actionControl
    }

    /// Shown after the actions for a few seconds; the owner's next update draws it.
    func note(_ text: String, for seconds: Double = 4) {
        noteLabel.stringValue = text
        noteResetTask?.cancel()
        noteResetTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            noteLabel.stringValue = ""
        }
    }

    @objc private func runAction() {
        guard actions.indices.contains(actionControl.selectedSegment) else { return }
        onCommand?(actions[actionControl.selectedSegment])
    }

    @objc private func openBuild() {
        guard let build else { return }
        if let workspace = build.workspace, FileManager.default.fileExists(atPath: workspace.path) {
            NSWorkspace.shared.open(workspace)
        } else if let xcode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
            NSWorkspace.shared.openApplication(at: xcode, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// `mark` colors the inner glyph of two-layer symbols like `checkmark.circle.fill`.
    private func pill(symbol: String, tint: NSColor, mark: NSColor? = nil, title: String, detail: String, action: Selector? = nil) -> NSButton {
        let font = NSFont.systemFont(ofSize: 14)
        let text = NSMutableAttributedString(string: title, attributes: [.foregroundColor: NSColor.labelColor, .font: font])
        if !detail.isEmpty {
            text.append(NSAttributedString(string: "  " + detail, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        }

        let button = NSButton(title: "", target: action == nil ? nil : self, action: action)
        button.attributedTitle = text
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: mark.map { [$0, tint] } ?? [tint]))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        return button
    }

    private static func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return switch seconds {
        case ..<60: "just now"
        case ..<3600: "\(seconds / 60)m ago"
        case ..<86_400: "\(seconds / 3600)h ago"
        default: "\(seconds / 86_400)d ago"
        }
    }

    private static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count == 1 ? "" : "s")"
    }

    private static func shorten(_ text: String) -> String {
        let line = text.prefix { $0 != "\n" }
        return line.count > 32 ? line.prefix(31) + "…" : String(line)
    }
}
