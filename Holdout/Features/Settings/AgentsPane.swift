//
//  AgentsPane.swift
//  Holdout
//

import SwiftUI

/// Connect agents, then open one for its setup steps and options, like a System Settings list.
struct AgentsPane: View {
    @State private var model = AgentConnections()

    var body: some View {
        Form {
            Section {
                ForEach(AgentInstaller.Agent.allCases) { agent in
                    NavigationLink(value: agent) {
                        AgentRow(agent: agent, model: model)
                    }
                }
            } footer: {
                Text("Holdout listens to each agent through a small hook in its config; nothing leaves your Mac. Restart an agent after connecting it.")
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
        Task {
            let failure = install ? await AgentInstaller.install(agent) : await AgentInstaller.remove(agent)
            if let failure { problem = "\(agent.name): \(failure)" }
            busy.remove(agent)
            statuses[agent] = await AgentInstaller.status(of: agent)
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
        _hidden = AppStorage(wrappedValue: false, HoldoutSettings.hiddenKey(agent.rawValue))
        _delivery = AppStorage(wrappedValue: HoldoutSettings.Delivery.automatic.rawValue, HoldoutSettings.deliveryKey(agent.rawValue))
    }

    var body: some View {
        Form {
            Section {
                AgentRow(agent: agent, model: model)
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
                    Text("Send into the chat").tag(HoldoutSettings.Delivery.automatic.rawValue)
                    Text("Copy to clipboard").tag(HoldoutSettings.Delivery.clipboard.rawValue)
                }
            } header: {
                Text("Options")
            } footer: {
                Text(delivery == HoldoutSettings.Delivery.clipboard.rawValue
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
                    Button("Remove Holdout from \(agent.name)…", role: .destructive) { model.change(agent, install: false) }
                } footer: {
                    Text("Takes Holdout's entry back out of \(agent.name)'s config.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(agent.name)
    }
}

/// The Claude Code mods Holdout found, and whether one is reporting to it.
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
                Text("A mod is reporting to Holdout, so its buttons show on the Project tab.")
            }
        }
        .task {
            mods = ClaudeMods.installed
            reporting = ClaudeMods.isReporting
        }
    }
}
