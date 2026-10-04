//
//  ProjectStripView.swift
//  Holdout
//

import AppKit

/// The Project tab: the last Xcode build, then what your mods know about the current repo.
final class ProjectStripView: NSView {
    /// ios-dock's buttons, sent through the holdout-bridge mod as the same prompts.
    enum Action: String {
        case build, lint, commit

        var title: String {
            switch self {
            case .build: "Build"
            case .lint: "Lint & fix"
            case .commit: "Review & commit"
            }
        }

        var symbol: String {
            switch self {
            case .build: "hammer"
            case .lint: "wand.and.stars"
            case .commit: "checkmark.seal"
            }
        }
    }

    var onCommand: ((Action) -> Void)?

    private static let failedBezel = NSColor(srgbRed: 0.42, green: 0.08, blue: 0.08, alpha: 1)

    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No builds yet")
    private var build: XcodeBuild?

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

    func update(build: XcodeBuild?, feed: ProjectFeed?, now: Date = .now) {
        self.build = build
        var pills: [NSButton] = []

        if let build {
            let detail = build.succeeded
                ? "built \(Self.ago(build.finishedAt, now: now))" + (build.warnings > 0 ? " · \(build.warnings) ⚠︎" : "")
                : Self.plural(build.errors, "error") + (build.warnings > 0 ? " · \(build.warnings) ⚠︎" : "")
            let pill = pill(
                symbol: build.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill",
                tint: build.succeeded ? .systemGreen : .systemRed,
                mark: .white,
                title: build.project,
                detail: detail,
                action: #selector(openBuild)
            )
            pill.bezelColor = build.succeeded ? nil : Self.failedBezel
            pills.append(pill)
        }

        if let feed {
            pills += modPills(feed)
        }

        emptyLabel.isHidden = !pills.isEmpty
        stack.setViews(pills, in: .leading)
    }

    /// Mirrors ios-dock's band: project, branch, build, lint, shipping, then its buttons.
    private func modPills(_ feed: ProjectFeed) -> [NSButton] {
        var pills: [NSButton] = []
        let ahead = feed.ship.flatMap { $0.ahead > 0 ? "\($0.ahead) ahead" : nil }

        if let project = feed.project {
            let traits = [project.architecture, project.deploymentTarget.map { "iOS \($0)" }, project.isSynced ? "synced" : "pbxproj"]
            pills.append(pill(symbol: "diamond.fill", tint: .systemBlue, title: project.name, detail: traits.compactMap { $0 }.joined(separator: " · ")))
            if let branch = project.branch ?? feed.repo?.branch {
                pills.append(pill(symbol: "arrow.triangle.branch", tint: .systemPurple, title: branch, detail: ahead ?? ""))
            }
        } else if let repo = feed.repo {
            let detail = [repo.branch, ahead].compactMap { $0 }.joined(separator: " · ")
            pills.append(pill(symbol: "arrow.triangle.branch", tint: .systemPurple, title: repo.name, detail: detail))
        }

        if let build = feed.build {
            pills.append(pill(
                symbol: build.isOk ? "hammer.fill" : "xmark",
                tint: build.isOk ? .systemGreen : .systemRed,
                title: build.isOk ? "Built in \(Int(build.seconds))s" : "Build failed",
                detail: build.isOk
                    ? build.warningCount.map { $0 > 0 ? Self.plural($0, "warning") : "" } ?? ""
                    : build.firstError.map { Self.shorten($0) } ?? Self.plural(build.errorCount, "error")
            ))
        } else if feed.project != nil {
            pills.append(pill(symbol: "hammer", tint: .secondaryLabelColor, title: "No build yet", detail: ""))
        }

        if feed.project != nil {
            let lintPill = switch feed.lint {
            case let lint? where lint.checkedEdits > 0 && lint.issues > 0:
                pill(symbol: "pencil.line", tint: .systemOrange, title: Self.plural(lint.issues, "lint issue"), detail: "")
            case let lint? where lint.checkedEdits > 0:
                pill(symbol: "pencil.line", tint: .systemGreen, title: "Lint clean", detail: Self.plural(lint.checkedEdits, "edit"))
            default:
                pill(symbol: "pencil.line", tint: .secondaryLabelColor, title: "Design lint idle", detail: "")
            }
            pills.append(lintPill)
        }

        if let ship = feed.ship, ship.phase != "idle" {
            let failed = ship.phase == "failed" || ship.phase == "conflict"
            pills.append(pill(symbol: "arrow.up.circle", tint: failed ? .systemRed : .systemBlue, title: "TestFlight", detail: ship.note.map { Self.shorten($0) } ?? ship.phase))
        }

        if feed.project != nil {
            pills.append(actionButton(.build))
            pills.append(actionButton(.lint))
        }
        if feed.repo != nil {
            pills.append(actionButton(.commit))
        }
        return pills
    }

    private func actionButton(_ action: Action) -> NSButton {
        let button = NSButton(title: action.title, image: NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)!, target: self, action: #selector(runAction(_:)))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
        return button
    }

    @objc private func runAction(_ sender: NSButton) {
        guard let action = sender.identifier.flatMap({ Action(rawValue: $0.rawValue) }) else { return }
        onCommand?(action)
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
