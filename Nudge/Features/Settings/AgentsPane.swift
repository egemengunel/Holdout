//
//  AgentsPane.swift
//  Nudge
//

import SwiftUI

/// Connect agents, then open one for its setup steps and options, like a System Settings list.
struct AgentsPane: View {
    @State private var model = AgentConnections()

    var body: some View {
        Form {
            Section {} footer: {
                PaneHeader(pane: .agents, text: "Nudge listens to your coding agents through a small hook in each one's config. Nothing leaves your Mac.") {
                    TouchBarStage(plate: .strip) { AgentsArrivingBar() }
                }
            }

            Section {
                ForEach(AgentInstaller.Agent.allCases) { agent in
                    NavigationLink(value: agent) {
                        AgentRow(agent: agent, model: model)
                    }
                }
            } footer: {
                Text("Restart an agent after connecting it.")
            }

            if !model.connectable.isEmpty {
                Section {
                    Button("Connect All Found (\(model.connectable.count))") { model.connectAll() }
                }
            }

            if let problem = model.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationDestination(for: AgentInstaller.Agent.self) { agent in
            AgentDetail(agent: agent, model: model)
        }
        .task { await model.reload() }
    }
}

/// Every agent's connection status, and connecting or removing them. Shared by the Agents pane
/// and the welcome guide.
@Observable
final class AgentConnections {
    var statuses: [AgentInstaller.Agent: AgentInstaller.Status] = [:]
    var busy: Set<AgentInstaller.Agent> = []
    var problem: String?
    /// Installs run one at a time: they share the runtime folder, and Cursor's install reads
    /// Claude Code's config to decide what to register.
    @ObservationIgnored private var last: Task<Void, Never>?

    var connectable: [AgentInstaller.Agent] {
        AgentInstaller.Agent.allCases.filter { $0.isPresent && (statuses[$0] ?? .notConnected) == .notConnected }
    }

    func status(_ agent: AgentInstaller.Agent) -> AgentInstaller.Status { statuses[agent] ?? .notConnected }

    func reload() async {
        for agent in AgentInstaller.Agent.allCases {
            statuses[agent] = await AgentInstaller.status(of: agent)
        }
    }

    func connectAll() {
        for agent in connectable { change(agent, install: true) }
    }

    func change(_ agent: AgentInstaller.Agent, install: Bool) {
        busy.insert(agent)
        problem = nil
        let previous = last
        last = Task {
            await previous?.value
            let failure = install ? await AgentInstaller.install(agent) : await AgentInstaller.remove(agent)
            if let failure { problem = "\(agent.name): \(failure)" }
            busy.remove(agent)
            statuses[agent] = await AgentInstaller.status(of: agent)
            NotificationCenter.default.post(name: .nudgeAgentsChanged, object: nil)
        }
    }

    func recheck(_ agent: AgentInstaller.Agent) {
        busy.insert(agent)
        Task {
            statuses[agent] = await AgentInstaller.status(of: agent)
            busy.remove(agent)
        }
    }
}

struct AgentRow: View {
    let agent: AgentInstaller.Agent
    let model: AgentConnections

    var body: some View {
        LabeledContent {
            if model.busy.contains(agent) {
                ProgressView().controlSize(.small)
            } else {
                AgentStatusLabel(agent: agent, status: model.status(agent))
            }
        } label: {
            HStack(spacing: 10) {
                AgentIcon(agent: agent, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name)
                    Text(agent.coverage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Connected / needs approval / off, the way System Settings states a service's status.
struct AgentStatusLabel: View {
    let agent: AgentInstaller.Agent
    let status: AgentInstaller.Status

    var body: some View {
        switch status {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .labelStyle(StatusLabelStyle(tint: .green))
        case .needsReview:
            Label("Needs Approval", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(StatusLabelStyle(tint: .orange))
        case .notConnected:
            Text(agent.isPresent ? "Off" : "Not Installed").foregroundStyle(.secondary)
        }
    }
}

private struct StatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title.foregroundStyle(.secondary)
        }
    }
}

/// One agent's page: its status, setup steps, options and removal.
private struct AgentDetail: View {
    let agent: AgentInstaller.Agent
    let model: AgentConnections
    @AppStorage private var hidden: Bool
    @AppStorage private var delivery: String

    init(agent: AgentInstaller.Agent, model: AgentConnections) {
        self.agent = agent
        self.model = model
        _hidden = AppStorage(wrappedValue: false, NudgeSettings.hiddenKey(agent.rawValue))
        _delivery = AppStorage(wrappedValue: NudgeSettings.Delivery.automatic.rawValue, NudgeSettings.deliveryKey(agent.rawValue))
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    AgentIcon(agent: agent, size: 64)
                    Text(agent.name).font(.title2.weight(.semibold))
                    Text(agent.coverage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if model.busy.contains(agent) {
                        ProgressView().controlSize(.small)
                    } else {
                        AgentStatusLabel(agent: agent, status: model.status(agent))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Setup") {
                StepList(steps: AgentGuide.steps(
                    for: agent,
                    status: model.status(agent),
                    connect: { model.change(agent, install: true) },
                    recheck: { model.recheck(agent) }
                ))
            }

            if agent == .claude {
                ClaudeModsSection()
            }

            Section {
                Toggle("Show sessions on the Agents tab", isOn: Binding(get: { !hidden }, set: { hidden = !$0 }))
                Picker("Project buttons", selection: $delivery) {
                    Text("Send into the chat").tag(NudgeSettings.Delivery.automatic.rawValue)
                    Text("Copy to clipboard").tag(NudgeSettings.Delivery.clipboard.rawValue)
                }
            } header: {
                Text("Options")
            } footer: {
                Text(delivery == NudgeSettings.Delivery.clipboard.rawValue
                     ? "Buttons always copy their prompt and bring \(agent.name) forward."
                     : agent.projectButtons)
            }

            if let problem = model.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            if model.status(agent) != .notConnected {
                Section {
                    Button("Remove Nudge from \(agent.name)…", role: .destructive) { model.change(agent, install: false) }
                } footer: {
                    Text("Takes Nudge's entry back out of \(agent.name)'s config.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(agent.name)
    }
}

/// The Claude Code mods Nudge found, and whether one is reporting to it.
private struct ClaudeModsSection: View {
    @State private var mods: [ClaudeMods.Mod] = []
    @State private var reporting = false

    var body: some View {
        Section {
            if mods.isEmpty {
                Text("None found in ~/.claude/mods").foregroundStyle(.secondary)
            }
            ForEach(mods) { mod in
                Label(mod.name, systemImage: "puzzlepiece.extension")
            }
        } header: {
            Text("Claude Code Mods")
        } footer: {
            if reporting {
                Text("A mod is reporting to Nudge, so its buttons show on the Project tab.")
            }
        }
        .task {
            mods = ClaudeMods.installed
            reporting = ClaudeMods.isReporting
        }
    }
}
