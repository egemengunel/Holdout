//
//  TouchBarController.swift
//  Holdout
//

import AppKit

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
    private let macView = MacStripView()
    private let mac = MacMonitor()

    private var tab = Tab.agents
    private var isPresented = false
    private var wasWaiting = false
    private var ticker: Timer?
    private var visibilityObservation: NSKeyValueObservation?
    /// Failures up to this moment have been seen (in the Project tab), so they stop blinking red.
    /// Starts at launch, so an old failure doesn't alarm when Holdout starts.
    private var failuresSeenUntil = Date.now.timeIntervalSince1970
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
        builds.onChange = { [weak self] in self?.refresh() }
        builds.start()
        mac.onChange = { [weak self] in self?.refresh() }
        mac.start()
        feeds.onChange = { [weak self] in self?.refresh() }
        feeds.isLive = { [weak self] id in self?.sessions.sessions.contains { $0.id == id } ?? true }
        feeds.start()

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
        let lastFinished = visible.filter { $0.state == .done }.map(\.updatedAt).max()
            .flatMap { Date.now.timeIntervalSince1970 - $0 < IconPulse.doneDuration ? $0 : nil }
        let failed = latestFailure != nil || unseenMacAlert != nil
        let headsUp = mac.headsUp.flatMap { Date.now.timeIntervalSince1970 - $0.at < IconPulse.headsUpDuration ? $0 : nil }
        // A heads-up is brief, so it plays over working; a session waiting on you still wins.
        statusIcon.show(
            failed ? .alert
                : waiting ? .waiting
                : headsUp.map { .headsUp(at: $0.at, symbol: $0.symbol) }
                ?? (working > 0 ? .working : lastFinished.map { .done(at: $0) } ?? .idle),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        statusIcon.setCount(!failed && !waiting && headsUp == nil && working > 0 ? working : nil)

        // Xcode's debugger can take the Control Strip slot; something needing you takes it back.
        if waiting && !wasWaiting {
            SystemTouchBar.showInControlStrip(Self.controlStripID)
        }
        wasWaiting = waiting

        if isPresented && tab == .agents {
            agentsView.update(visible)
        }
        if isPresented && tab == .project {
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

    /// The mods' view of the session you touched most recently. Sessions that have ended
    /// (their hook file is gone) don't count, even if their feed file is still on disk.
    private var currentFeed: ProjectFeed? {
        sessions.sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .lazy
            .compactMap { self.feeds.feeds[$0.id] }
            .first { $0.hasContent }
    }

    /// Hands a Touch Bar button press to the holdout-bridge mod in the current session,
    /// which submits it as a prompt, then brings that session forward.
    private func send(_ action: ProjectStripView.Action) {
        guard let feed = currentFeed else { return }
        let command = ["id": UUID().uuidString, "action": action.rawValue]
        let url = URL.applicationSupportDirectory.appending(path: "Holdout/commands/\(feed.session).json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(command).write(to: url, options: .atomic)
        if let session = sessions.sessions.first(where: { $0.id == feed.session }) {
            focus(session)
        }
    }

    /// When the newest Mac alert started, if it began after you last looked at the Mac tab.
    private var unseenMacAlert: TimeInterval? {
        mac.newestDistress.flatMap { $0 > macAlertsSeenUntil ? $0 : nil }
    }

    /// When the newest unseen failed build (Xcode's own, or one Claude ran through ios-dock) finished.
    private var latestFailure: TimeInterval? {
        let xcode = builds.latest.flatMap { $0.succeeded ? nil : $0.finishedAt.timeIntervalSince1970 }
        let claude = currentFeed.flatMap { $0.build?.isOk == false ? $0.updatedAt : nil }
        return [xcode, claude].compactMap { $0 }.filter { $0 > failuresSeenUntil }.max()
    }

    /// Debug aid: the content view tree with frames.
    func dumpLayout() -> String {
        func walk(_ view: NSView, _ depth: Int) -> [String] {
            ["\(String(repeating: "  ", count: depth))\(type(of: view)) \(view.frame) hidden=\(view.isHidden) window=\(view.window != nil)"]
                + view.subviews.flatMap { walk($0, depth + 1) }
        }
        return content.debugDescriptionForLayout + "\n" + walk(content, 0).joined(separator: "\n")
    }

    private func focus(_ session: ClaudeSession) {
        // A background app's `activate()` is ignored since macOS 14; opening the app through
        // Launch Services brings it forward the way the Dock does.
        if let bundleID = session.app,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
