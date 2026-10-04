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
            case .agents: "sparkles"
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
    private let stripButton = NSButton()
    private let content = FlexibleWidthView(minWidth: contentMinWidth, height: contentHeight)
    private let agentsView = AgentsStripView()
    private let simView = SimulatorStripView()
    private let comingSoonLabel = NSTextField(labelWithString: "Coming next")
    /// Stack views center their content vertically; a bare label would sit at the top.
    private lazy var comingSoon = NSStackView(views: [comingSoonLabel])

    private var tab = Tab.agents
    private var isPresented = false
    private var wasWaiting = false
    private var ticker: Timer?
    private var visibilityObservation: NSKeyValueObservation?
    private var pulse = IconPulse.idle
    private var animation: Timer?

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
        stripButton.image = NSImage(systemSymbolName: IconPulse.idleSymbol, accessibilityDescription: "Holdout")
        stripButton.imagePosition = .imageOnly
        // Keeps the working count right next to the hand instead of at the far edge.
        stripButton.imageHugsTitle = true
        stripButton.bezelStyle = .rounded
        stripButton.target = self
        stripButton.action = #selector(openStrip)

        let item = NSCustomTouchBarItem(identifier: Self.controlStripID)
        item.view = stripButton
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
        comingSoonLabel.textColor = .secondaryLabelColor
        sessions.onChange = { [weak self] in self?.refresh() }
        sessions.start()

        // Elapsed times tick, and finished sessions drop off after a minute.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        return true
    }

    // MARK: - Presenting

    @objc func openStrip() {
        if sessions.visible().contains(where: { $0.state == .waiting }) {
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
        case .project, .mac: comingSoon
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

        let lastFinished = visible.filter { $0.state == .done }.map(\.updatedAt).max()
        setPulse(waiting ? .waiting : working > 0 ? .working : lastFinished.map { .done(at: $0) } ?? .idle)
        stripButton.title = !waiting && working > 0 ? "\(working)" : ""
        stripButton.imagePosition = stripButton.title.isEmpty ? .imageOnly : .imageLeading

        // Xcode's debugger can take the Control Strip slot; something needing you takes it back.
        if waiting && !wasWaiting {
            SystemTouchBar.showInControlStrip(Self.controlStripID)
        }
        wasWaiting = waiting

        if isPresented && tab == .agents {
            agentsView.update(visible)
        }
    }

    // MARK: - Icon animation

    private func setPulse(_ next: IconPulse) {
        guard next != pulse else { return }
        pulse = next
        animateIcon()
        guard animation == nil, stripButton.bezelColor != nil else { return }
        animation = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animateIcon() }
        }
    }

    /// Runs only while the icon has something to show; stops once it settles back to plain.
    private func animateIcon() {
        let now = Date.now.timeIntervalSince1970
        let color = pulse.color(at: now, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        stripButton.bezelColor = color
        setSymbol(pulse.symbol(at: now))
        if color == nil {
            animation?.invalidate()
            animation = nil
        }
    }

    private var currentSymbol = IconPulse.idleSymbol

    private func setSymbol(_ name: String) {
        guard name != currentSymbol else { return }
        currentSymbol = name
        stripButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Holdout")
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

/// Touch Bar content that fills whatever space the other items leave.
/// The Touch Bar sizes items purely from `intrinsicContentSize` and hides (rather than
/// clips) one that doesn't fit, so this starts small and grows once it can measure.
final class FlexibleWidthView: NSView {
    private let minWidth: CGFloat
    private let height: CGFloat
    private var width: CGFloat

    init(minWidth: CGFloat, height: CGFloat) {
        self.minWidth = minWidth
        self.height = height
        self.width = minWidth
        super.init(frame: NSRect(x: 0, y: 0, width: minWidth, height: height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: height) }

    override func layout() {
        super.layout()
        fillAvailableWidth()
    }

    private func fillAvailableWidth() {
        guard let window else { return }
        let leading = convert(bounds.origin, to: nil).x
        let available = (window.frame.width - leading - Self.trailingMargin).rounded(.down)
        guard available >= minWidth, abs(available - width) > 1 else { return }
        width = available
        invalidateIntrinsicContentSize()
    }

    private static let trailingMargin: CGFloat = 8

    var debugDescriptionForLayout: String {
        "window=\(window?.frame.width ?? -1) leading=\(window == nil ? -1 : convert(bounds.origin, to: nil).x) width=\(width)"
    }
}
