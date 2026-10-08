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
                .tabItem { Label("Alerts", systemImage: "bell") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 340)
    }
}

private struct GeneralSettings: View {
    @State private var opensAtLogin = HoldoutSettings.opensAtLogin

    var body: some View {
        Form {
            Toggle("Open at login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, value in
                    HoldoutSettings.opensAtLogin = value
                    opensAtLogin = HoldoutSettings.opensAtLogin
                }
            Text("Holdout lives in the menu bar and the Touch Bar's Control Strip. Tap its hand to open the strip.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AgentSettings: View {
    @State private var installed: [AgentInstaller.Agent: Bool] = [:]
    @State private var busy: AgentInstaller.Agent?
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                ForEach(AgentInstaller.Agent.allCases) { agent in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(agent.name)
                            Text(agent.isPresent ? (installed[agent] == true ? "Connected" : "Not connected") : "Not found on this Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if busy == agent {
                            ProgressView().controlSize(.small)
                        } else if installed[agent] == true {
                            Button("Remove") { change(agent, install: false) }
                        } else {
                            Button("Connect") { change(agent, install: true) }
                                .disabled(!agent.isPresent)
                        }
                    }
                }
            } footer: {
                Text("Connecting adds a small hook to the agent's config. Restart the agent afterwards; Codex asks you to trust it once with /hooks.")
            }
            if let problem {
                Section { Text(problem).font(.caption).foregroundStyle(.red) }
            }
            Section("Claude Code project tab") {
                Text("For build, lint and commit state from your Claude Code mods, load the holdout-bridge mod by adding its folder to CLAUDE_CODE_PLUGIN_DIRS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Copy bridge folder path") {
                    Task {
                        await AgentInstaller.syncRuntime()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AgentInstaller.bridge.path, forType: .string)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    private func reload() {
        installed = Dictionary(uniqueKeysWithValues: AgentInstaller.Agent.allCases.map { ($0, $0.isInstalled) })
    }

    private func change(_ agent: AgentInstaller.Agent, install: Bool) {
        busy = agent
        problem = nil
        Task {
            let failure = install ? await AgentInstaller.install(agent) : await AgentInstaller.remove(agent)
            problem = failure.map { "\(agent.name): \($0)" }
            busy = nil
            reload()
        }
    }
}

private struct AlertSettings: View {
    @AppStorage(HoldoutSettings.Key.macDistress) private var macDistress = true
    @AppStorage(HoldoutSettings.Key.cpuHeadsUp) private var cpuHeadsUp = true
    @AppStorage(HoldoutSettings.Key.sessionDone) private var sessionDone = true
    @AppStorage(HoldoutSettings.Key.buildResult) private var buildResult = true

    var body: some View {
        Form {
            Section("Flash the Control Strip icon when") {
                Toggle("A session finishes", isOn: $sessionDone)
                Toggle("An Xcode build succeeds or fails", isOn: $buildResult)
                Toggle("A process hogs the CPU for minutes", isOn: $cpuHeadsUp)
            }
            Section {
                Toggle("Memory pressure turns critical", isOn: $macDistress)
            } footer: {
                Text("Red until you open the Mac tab; only when Activity Monitor's memory graph turns red. A session waiting on you always shows amber.")
            }
        }
        .formStyle(.grouped)
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
                .frame(width: 84, height: 84)
            Text("Holdout").font(.title2.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Your coding agents, simulator, builds and Mac, on the Touch Bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("github.com/egemengunel/Holdout", destination: URL(string: "https://github.com/egemengunel/Holdout")!)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
