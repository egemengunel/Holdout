//
//  TouchBarController.swift
//  Holdout
//

import AppKit
import OSLog

/// Owns the Holdout icon in the Control Strip and the full-width strip it opens.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    enum Tab: Int, CaseIterable {
        case agents, sim, project, mac

        var symbol: String {
            switch self {
            case .agents: "apple.terminal.on.rectangle"
            case .sim: "iphone"
            case .project: "hammer"
            case .mac: "memorychip"
            }
        }

        var label: String {
            switch self {
            case .agents: "Agents"
            case .sim: "Simulator"
            case .project: "Project"
            case .mac: "Mac"
            }
        }
    }

    private static let log = Logger(subsystem: "com.egemen.Holdout", category: "project")
    static let controlStripID = NSTouchBarItem.Identifier("com.egemen.Holdout.controlStrip")
    private static let tabsID = NSTouchBarItem.Identifier("com.egemen.Holdout.tabs")
    private static let contentID = NSTouchBarItem.Identifier("com.egemen.Holdout.content")

    /// The Touch Bar hides (rather than clips) an item that doesn't fit, so the content
    /// asks for little and stretches into the rest.
    private static let contentMinWidth: CGFloat = 200
    /// Standard Touch Bar control height.
    private static let contentHeight: CGFloat = 30
    /// Icon-only tabs; the default segments are about twice as wide.
    private static let tabWidth: CGFloat = 34

    private let sessions = SessionStore()
    private let statusIcon = StatusIconView()
    private let content = FlexibleWidthView(minWidth: contentMinWidth, height: contentHeight)
    private let agentsView = AgentsStripView()
    private let simView = SimulatorStripView()
    private let projectView = ProjectStripView()
    private let builds = XcodeBuildWatcher()
    private let feeds = ProjectFeedStore()
    private let agentProjects = AgentProjectStore()
    private let macView = MacStripView()
    private let mac = MacMonitor()

    private var tab = Tab.agents
    private var isPresented = false
    private var slotTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var ticker: Timer?
    private var visibilityObservation: NSKeyValueObservation?
    /// Failures up to this moment have been seen (in the Project tab), so they stop blinking red.
    /// Starts at launch, so an old failure doesn't alarm when Holdout starts.
    private var failuresSeenUntil = Date.now.timeIntervalSince1970
    /// The newest failure already flashed; starts at launch so old failures don't flash.
    private var lastFailureFlashed = Date.now.timeIntervalSince1970
    private var buildFailedAt: TimeInterval?
    /// The newest Xcode build already accounted for; starts at launch so old builds don't flash.
    private var lastBuildSeen = Date.now
    /// When Holdout noticed a fresh successful build, to flash the hammer from that moment.
    private var buildSucceededAt: TimeInterval?
    /// Same, for the Mac tab's alerts.
    private var macAlertsSeenUntil = Date.now.timeIntervalSince1970

    private lazy var tabs = NSSegmentedControl(
        images: Tab.allCases.map { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.label)! },
        trackingMode: .selectOne,
        target: self,
        action: #selector(tabChanged)
    )

    private lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.tabsID, Self.contentID]
        return bar
    }()

    /// Returns false when the private Touch Bar API isn't available on this macOS.
    func install() -> Bool {
        statusIcon.onPress = { [weak self] in self?.openStrip() }

        let item = NSCustomTouchBarItem(identifier: Self.controlStripID)
        item.view = statusIcon
        guard SystemTouchBar.addToControlStrip(item) else { return false }
        SystemTouchBar.showsSystemCloseBox(true)

        // The system ✕ closes the strip without telling us, and closing drops our
        // Control Strip icon, so notice the strip going away and put the icon back.
        visibilityObservation = touchBar.observe(\.isVisible, options: [.new]) { [weak self] bar, _ in
            let isVisible = bar.isVisible
            DispatchQueue.main.async {
                guard let self, !isVisible, self.isPresented else { return }
                self.isPresented = false
                SystemTouchBar.showInControlStrip(Self.controlStripID)
            }
        }

        for segment in 0..<tabs.segmentCount {
            tabs.setWidth(Self.tabWidth, forSegment: segment)
        }
        agentsView.onSelect = { [weak self] session in self?.focus(session) }
        projectView.onCommand = { [weak self] action in self?.send(action) }
        sessions.onChange = { [weak self] in self?.refresh() }
        sessions.start()
        builds.onChange = { [weak self] in self?.buildsChanged() }
        builds.start()
        mac.onChange = { [weak self] in self?.refresh() }
        mac.start()
        feeds.onChange = { [weak self] in self?.refresh() }
        feeds.isLive = { [weak self] id in self?.sessions.sessions.contains { $0.id == id } ?? true }
        feeds.start()
        agentProjects.onChange = { [weak self] in self?.refresh() }

        // Xcode's debugger puts its own item in the Control Strip's one extra slot whenever it
        // debugs any app. Take the slot back when you switch apps and every few seconds;
        // re-asserting while already holding it is a no-op.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reclaimControlStrip() }
        }
        slotTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reclaimControlStrip() }
        }

        // Elapsed times tick, and finished sessions drop off after a minute.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        return true
    }

    // MARK: - Presenting

    @objc func openStrip() {
        if let macAlert = unseenMacAlert, macAlert >= (latestFailure ?? 0) {
            tab = .mac
        } else if latestFailure != nil {
            tab = .project
        } else if sessions.visible().contains(where: { $0.state == .waiting }) {
            tab = .agents
        }
        tabs.selectedSegment = tab.rawValue
        isPresented = true
        show(tab)
        SystemTouchBar.showsSystemCloseBox(true)
        SystemTouchBar.present(touchBar, from: Self.controlStripID, placement: SystemTouchBar.besideControlStripPlacement)
    }

    private func closeStrip() {
        isPresented = false
        SystemTouchBar.minimize(touchBar)
        SystemTouchBar.showInControlStrip(Self.controlStripID)
    }

    @objc private func tabChanged() {
        tab = Tab(rawValue: tabs.selectedSegment) ?? .agents
        show(tab)
    }

    private func show(_ tab: Tab) {
        let view: NSView = switch tab {
        case .agents: agentsView
        case .sim: simView
        case .project: projectView
        case .mac: macView
        }
        if tab == .sim {
            simView.reload()
        }
        guard view.superview !== content else { return }

        content.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        refresh()
    }

    // MARK: - State

    private func refresh() {
        let visible = sessions.visible()
        let waiting = visible.contains { $0.state == .waiting }
        let working = visible.filter { $0.state.isWorking }.count

        // Only while its flash is still playing; done sessions stay listed far longer.
        let now = Date.now.timeIntervalSince1970
        let sessionDone = !HoldoutSettings.isOn(HoldoutSettings.Key.sessionDone) ? nil : visible.filter { $0.state == .done }.map(\.updatedAt).max()
            .flatMap { now - $0 < IconPulse.doneDuration ? IconPulse.done(at: $0) : nil }
        let buildFlashes = HoldoutSettings.isOn(HoldoutSettings.Key.buildResult)
        let buildDone = (buildFlashes ? buildSucceededAt : nil)
            .flatMap { now - $0 < IconPulse.doneDuration ? IconPulse.done(at: $0, symbol: "hammer.fill") : nil }
        // Whichever finished last gets the flash.
        let celebration = [sessionDone, buildDone].compactMap { $0 }.max { ($0.transient?.startedAt ?? 0) < ($1.transient?.startedAt ?? 0) }
        let failed = unseenMacAlert != nil && HoldoutSettings.isOn(HoldoutSettings.Key.macDistress)
        // A failed build flashes once, from when Holdout notices it, then clears like the rest.
        if let failure = newestFailure, failure > lastFailureFlashed {
            lastFailureFlashed = failure
            buildFailedAt = now
        }
        let buildFailed = (buildFlashes ? buildFailedAt : nil)
            .flatMap { now - $0 < IconPulse.doneDuration ? IconPulse.done(at: $0, symbol: "hammer.fill", isFailure: true) : nil }
        let headsUp = (HoldoutSettings.isOn(HoldoutSettings.Key.cpuHeadsUp) ? mac.headsUp : nil).flatMap { Date.now.timeIntervalSince1970 - $0.at < IconPulse.headsUpDuration ? $0 : nil }
        // Heads-ups and done flashes are brief, so they play over working (a session finishing
        // while another works still gets its check); a session waiting on you still wins.
        let flash = headsUp.map { IconPulse.headsUp(at: $0.at, symbol: $0.symbol) } ?? celebration
        statusIcon.show(
            failed ? .alert
                : buildFailed ?? (waiting ? .waiting
                : flash ?? (working > 0 ? .working : .idle)),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        statusIcon.setCount(!failed && buildFailed == nil && !waiting && flash == nil && working > 0 ? working : nil)

        if isPresented && tab == .agents {
            agentsView.update(visible)
        }
        if isPresented && tab == .project {
            agentProjects.track(Array(sessions.sessions.filter { !self.hasBridge($0) }.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)))
            failuresSeenUntil = Date.now.timeIntervalSince1970
            let feed = currentFeed
            // With a session open, its own project's Xcode build; otherwise the latest of any.
            let xcodeBuild = (feed?.project?.name ?? feed?.repo?.name).map { builds.latest(project: $0) } ?? builds.latest
            projectView.update(xcodeBuild: xcodeBuild, feed: feed)
        }
        if isPresented && tab == .mac {
            macAlertsSeenUntil = Date.now.timeIntervalSince1970
            macView.update(mac.snapshot)
        }
    }

    /// The feed of the session you touched most recently: the mods' for Claude Code, Holdout's
    /// own for other agents. Sessions that have ended (their hook file is gone) don't count,
    /// even if their feed file is still on disk.
    private var currentFeed: ProjectFeed? {
        sessions.sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .lazy
            .compactMap { self.hasBridge($0) ? self.feeds.feeds[$0.id] : self.agentProjects.feeds[$0.id] }
            .first { $0.hasContent }
    }

    /// Hands a Touch Bar button press to the current session as a prompt, the way that agent
    /// takes one: Claude Code through the holdout-bridge mod, OpenCode through its plugin,
    /// and the others (Cursor included) at the end of the turn they're on, in that same
    /// chat, or on the clipboard when they're idle.
    private func send(_ action: ProjectStripView.Action) {
        Self.log.info("pressed \(action.rawValue, privacy: .public)")
        guard let feed = currentFeed,
              let session = sessions.sessions.first(where: { $0.id == feed.session })
        else {
            Self.log.error("\(action.rawValue, privacy: .public): no session with a project feed")
            return
        }
        Self.log.info("\(action.rawValue, privacy: .public) for \(session.agentName, privacy: .public) \(session.id, privacy: .public), \(session.state.isWorking ? "working" : "idle", privacy: .public)")

        if hasBridge(session) {
            write(["id": UUID().uuidString, "action": action.rawValue], for: session)
            focus(session)
            return
        }
        guard let prompt = action.prompt(project: feed.project, repo: feed.repo) else {
            Self.log.error("\(action.rawValue, privacy: .public): no prompt for this project")
            return
        }

        switch session.agent {
        case "opencode":
            write(["id": UUID().uuidString, "prompt": prompt], for: session)
            focus(session)
        default:
            if session.state.isWorking {
                write(["id": UUID().uuidString, "prompt": prompt, "at": Int(Date.now.timeIntervalSince1970)], for: session)
                projectView.note("Queued for when \(session.agentName) finishes")
                refresh()
            } else if session.agent == "cursor", let bundleID = session.app {
                projectView.note("Sending to Cursor…")
                Task {
                    switch await CursorChat.send(prompt, bundleID: bundleID) {
                    case .sent:
                        closeStrip()
                    case .needsAccessibility:
                        copyToClipboard(prompt, note: "Allow Holdout in Privacy > Accessibility, then press again. Copied for now")
                    case .focusNotInChat:
                        copyToClipboard(prompt, note: "Click into the chat and paste: copied")
                    }
                }
            } else {
                copyToClipboard(prompt, note: "Copied: paste it into \(session.agentName)")
                focus(session)
            }
        }
    }

    /// A Claude Code session whose holdout-bridge plugin is feeding it. Without the plugin
    /// (most people), Claude Code is treated like any other agent: git and Xcode for the
    /// Project tab, and prompts by clipboard.
    private func hasBridge(_ session: AgentSession) -> Bool {
        session.usesBridge && feeds.feeds[session.id] != nil
    }

    private func copyToClipboard(_ prompt: String, note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        projectView.note(note)
        refresh()
    }

    private func write(_ command: [String: Any], for session: AgentSession) {
        let url = URL.applicationSupportDirectory.appending(path: "Holdout/commands/\(session.id).json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: command).write(to: url, options: .atomic)
    }

    /// While the strip is open it owns the bar; closing it reclaims the slot itself.
    private func reclaimControlStrip() {
        guard !isPresented else { return }
        SystemTouchBar.showInControlStrip(Self.controlStripID)
    }

    /// A newly finished successful build gets the done flash with a hammer. Builds are polled
    /// every 2 s, so it's timed from when Holdout noticed, or most of the flash would be over.
    private func buildsChanged() {
        if let build = builds.latest, build.finishedAt > lastBuildSeen {
            lastBuildSeen = build.finishedAt
            if build.succeeded {
                buildSucceededAt = Date.now.timeIntervalSince1970
            }
        }
        refresh()
    }

    /// When the newest Mac alert started, if it began after you last looked at the Mac tab.
    private var unseenMacAlert: TimeInterval? {
        mac.newestDistress.flatMap { $0 > macAlertsSeenUntil ? $0 : nil }
    }

    /// When the newest unseen failed build (Xcode's own, or one Claude ran through ios-dock) finished.
    /// When the newest failed build finished: Xcode's own, or one Claude ran through ios-dock.
    /// Timed by the feed's buildAt: its updatedAt moves with any field (branch, lint, commits
    /// ahead), which made one old failure flash red again and again.
    private var newestFailure: TimeInterval? {
        let xcode = builds.latest.flatMap { $0.succeeded ? nil : $0.finishedAt.timeIntervalSince1970 }
        let claude = currentFeed.flatMap { $0.build?.isOk == false ? $0.buildAt : nil }
        return [xcode, claude].compactMap { $0 }.max()
    }

    /// A failure you haven't looked at in the Project tab; opening the strip goes there.
    private var latestFailure: TimeInterval? {
        newestFailure.flatMap { $0 > failuresSeenUntil ? $0 : nil }
    }

    /// Debug aid: the content view tree with frames.
    func dumpLayout() -> String {
        func walk(_ view: NSView, _ depth: Int) -> [String] {
            ["\(String(repeating: "  ", count: depth))\(type(of: view)) \(view.frame) hidden=\(view.isHidden) window=\(view.window != nil)"]
                + view.subviews.flatMap { walk($0, depth + 1) }
        }
        return content.debugDescriptionForLayout + "\n" + walk(content, 0).joined(separator: "\n")
    }

    private func focus(_ session: AgentSession) {
        // A background app's `activate()` is ignored since macOS 14; opening the app through
        // Launch Services brings it forward the way the Dock does.
        if let bundleID = session.app,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if session.agent == "codex", let thread = URL(string: "codex://threads/\(session.id)") {
            // The ChatGPT app's Codex runs hooks from its app-server, which names no host app;
            // its thread id is the session id, and codex:// opens that thread.
            NSWorkspace.shared.open(thread)
        }
        closeStrip()
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.tabsID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = tabs
            return item

        case Self.contentID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = content
            return item

        default:
            return nil
        }
    }
}
