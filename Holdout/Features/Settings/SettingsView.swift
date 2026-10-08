//
//  SettingsView.swift
//  Holdout
//

import AppKit
import SwiftUI

struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case general = "General", agents = "Agents", alerts = "Alerts", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .agents: "terminal"
            case .alerts: "bell.badge"
            case .about: "info.circle"
            }
        }
    }

    @State private var page: Page = .agents

    var body: some View {
        HStack(spacing: 0) {
            List(Page.allCases, selection: $page) { page in
                Label(page.rawValue, systemImage: page.symbol)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .frame(width: 170)

            Divider()

            ScrollView {
                Group {
                    switch page {
                    case .general: GeneralSettings()
                    case .agents: AgentSettings()
                    case .alerts: AlertSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 700, height: 500)
    }
}

/// A titled group of rows on a rounded card.
private struct Card<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

private struct GeneralSettings: View {
    @State private var opensAtLogin = HoldoutSettings.opensAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "General", subtitle: "Holdout lives in the menu bar and on the Touch Bar's Control Strip.")
            Card(footer: "Tap the ✋ on the Control Strip to open the strip.") {
                Toggle("Open Holdout at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, value in
                        HoldoutSettings.opensAtLogin = value
                        opensAtLogin = HoldoutSettings.opensAtLogin
                    }
            }
        }
    }
}

private struct AgentSettings: View {
    @State private var installed: [AgentInstaller.Agent: Bool] = [:]
    @State private var busy: Set<AgentInstaller.Agent> = []
    @State private var problem: String?

    private var connectable: [AgentInstaller.Agent] {
        AgentInstaller.Agent.allCases.filter { $0.isPresent && installed[$0] != true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageHeader(title: "Agents", subtitle: "Connect the coding agents you use so their sessions show on the Touch Bar.")
                Spacer()
                if !connectable.isEmpty {
                    Button("Connect all found (\(connectable.count))") {
                        for agent in connectable { change(agent, install: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Card(footer: "Connecting adds a small hook to the agent's config; nothing leaves your Mac. Restart the agent afterwards.") {
                ForEach(Array(AgentInstaller.Agent.allCases.enumerated()), id: \.element) { index, agent in
                    if index > 0 { Divider().padding(.vertical, 8) }
                    row(agent)
                }
            }

            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }

            Card(
                title: "Project tab",
                footer: "Optional. Holdout reads Xcode builds and git on its own. If you use Claude Code plugins that report build or lint state, the bundled holdout-bridge plugin forwards it to the Project tab."
            ) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("holdout-bridge plugin")
                        Text("Add its folder to CLAUDE_CODE_PLUGIN_DIRS.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Copy folder path") {
                        Task {
                            await AgentInstaller.syncRuntime()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AgentInstaller.bridge.path, forType: .string)
                        }
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func row(_ agent: AgentInstaller.Agent) -> some View {
        HStack(spacing: 12) {
            AgentIcon(agent: agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                Text(agent.coverage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if busy.contains(agent) {
                ProgressView().controlSize(.small)
            } else if installed[agent] == true {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                Button("Remove") { change(agent, install: false) }
            } else if agent.isPresent {
                Button("Connect") { change(agent, install: true) }
            } else {
                Text("Not found").font(.callout).foregroundStyle(.tertiary)
            }
        }
    }

    private func reload() {
        installed = Dictionary(uniqueKeysWithValues: AgentInstaller.Agent.allCases.map { ($0, $0.isInstalled) })
    }

    private func change(_ agent: AgentInstaller.Agent, install: Bool) {
        busy.insert(agent)
        problem = nil
        Task {
            let failure = install ? await AgentInstaller.install(agent) : await AgentInstaller.remove(agent)
            if let failure { problem = "\(agent.name): \(failure)" }
            busy.remove(agent)
            reload()
        }
    }
}

/// The agent's own app icon when it's installed, otherwise a neutral tile.
private struct AgentIcon: View {
    let agent: AgentInstaller.Agent

    var body: some View {
        Group {
            if let icon = agent.appIcon {
                Image(nsImage: icon).resizable()
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "terminal").foregroundStyle(.secondary))
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct AlertSettings: View {
    @AppStorage(HoldoutSettings.Key.macDistress) private var macDistress = true
    @AppStorage(HoldoutSettings.Key.cpuHeadsUp) private var cpuHeadsUp = true
    @AppStorage(HoldoutSettings.Key.sessionDone) private var sessionDone = true
    @AppStorage(HoldoutSettings.Key.buildResult) private var buildResult = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Alerts", subtitle: "What the Control Strip icon flashes for.")
            Card(title: "Quick flashes") {
                Toggle("A session finishes", isOn: $sessionDone)
                Divider().padding(.vertical, 8)
                Toggle("An Xcode build succeeds or fails", isOn: $buildResult)
                Divider().padding(.vertical, 8)
                Toggle("A process hogs the CPU for minutes", isOn: $cpuHeadsUp)
            }
            Card(
                title: "Stays on until you look",
                footer: "Red appears only when Activity Monitor's memory graph turns red. A session waiting on you always shows amber."
            ) {
                Toggle("Memory pressure turns critical", isOn: $macDistress)
            }
        }
    }
}

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Holdout").font(.title.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Your coding agents, simulator, builds and Mac, on the Touch Bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("github.com/egemengunel/Holdout", destination: URL(string: "https://github.com/egemengunel/Holdout")!)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
