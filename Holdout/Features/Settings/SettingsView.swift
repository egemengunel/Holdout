//
//  SettingsView.swift
//  Holdout
//

import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AgentSettings()
                .tabItem { Label("Agents", systemImage: "terminal") }
            AlertSettings()
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 520)
    }
}

private struct GeneralSettings: View {
    @State private var opensAtLogin = HoldoutSettings.opensAtLogin

    var body: some View {
        Form {
            Section {
                TouchBarPreview()
                    .padding(.vertical, 8)
            } footer: {
                Text("The Control Strip icon is Holdout's status light. Tap it to open the strip.")
            }
            Section {
                Toggle("Open Holdout at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, value in
                        HoldoutSettings.opensAtLogin = value
                        opensAtLogin = HoldoutSettings.opensAtLogin
                    }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AgentSettings: View {
    @State private var statuses: [AgentInstaller.Agent: AgentInstaller.Status] = [:]
    @State private var busy: Set<AgentInstaller.Agent> = []
    @State private var problem: String?

    private var connectable: [AgentInstaller.Agent] {
        AgentInstaller.Agent.allCases.filter { $0.isPresent && (statuses[$0] ?? .notConnected) == .notConnected }
    }

    var body: some View {
        Form {
            Section {
                ForEach(AgentInstaller.Agent.allCases) { agent in
                    row(agent)
                }
            } header: {
                HStack {
                    Text("Coding agents")
                    Spacer()
                    if !connectable.isEmpty {
                        Button("Connect all found (\(connectable.count))") {
                            for agent in connectable { change(agent, install: true) }
                        }
                        .controlSize(.small)
                    }
                }
            } footer: {
                Text("Connecting adds a small hook to the agent's config; nothing leaves your Mac. Restart the agent afterwards.")
            }

            if let problem {
                Section { Text(problem).foregroundStyle(.red) }
            }

            Section {
                LabeledContent {
                    Button("Copy folder path") {
                        Task {
                            await AgentInstaller.syncRuntime()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AgentInstaller.bridge.path, forType: .string)
                        }
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text("holdout-bridge plugin")
                        Text("Add its folder to CLAUDE_CODE_PLUGIN_DIRS.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Project tab")
            } footer: {
                Text("Optional. Holdout reads Xcode builds and git on its own. If you use Claude Code plugins that report build or lint state, this one forwards it to the Project tab.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    private func row(_ agent: AgentInstaller.Agent) -> some View {
        HStack(spacing: 12) {
            AgentIcon(agent: agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                Text(statuses[agent] == .needsReview
                     ? "Connected, but Codex skips it until you trust it: /hooks in the CLI, or approve it in the ChatGPT app"
                     : agent.coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if busy.contains(agent) {
                ProgressView().controlSize(.small)
            } else if statuses[agent] == .needsReview {
                Label("Approve in Codex", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Codex runs new hooks only after you trust them: type /hooks in the Codex CLI, or approve them when the ChatGPT app asks. Then come back here.")
                Button("Recheck", action: reload)
            } else if statuses[agent] == .connected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Remove") { change(agent, install: false) }
            } else if agent.isPresent {
                Button("Connect") { change(agent, install: true) }
            } else {
                Text("Not found").foregroundStyle(.tertiary)
            }
        }
    }

    private func reload() {
        Task {
            for agent in AgentInstaller.Agent.allCases {
                statuses[agent] = await AgentInstaller.status(of: agent)
            }
        }
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
            } else if let logo = agent.logoAsset {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.1)))
                    .overlay(Image(logo).resizable().scaledToFit().padding(6))
            } else {
                RoundedRectangle(cornerRadius: 8)
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
        Form {
            Section {
                alert("A session finishes", preview: .done(at: 0), isOn: $sessionDone)
                alert("An Xcode build succeeds or fails", preview: .done(at: 0, symbol: "hammer.fill"), isOn: $buildResult)
                alert("A process hogs the CPU for minutes", preview: .headsUp(at: 0, symbol: "cpu"), isOn: $cpuHeadsUp)
            } header: {
                Text("Quick flashes")
            } footer: {
                Text("The icon flashes once, then goes back to the hand.")
            }
            Section {
                alert("Memory pressure turns critical", preview: .alert, isOn: $macDistress)
            } header: {
                Text("Stays on until you look")
            } footer: {
                Text("Red appears only when Activity Monitor's memory graph turns red. A session waiting on you always shows amber.")
            }
            Section {
                LabeledContent {
                    IconPreview(pulse: .waiting)
                } label: {
                    Text("A session needs you")
                }
            } footer: {
                Text("Always on.")
            }
        }
        .formStyle(.grouped)
    }

    private func alert(_ title: String, preview: IconPulse, isOn: Binding<Bool>) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
            Spacer()
            IconPreview(pulse: preview)
                .opacity(isOn.wrappedValue ? 1 : 0.35)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
