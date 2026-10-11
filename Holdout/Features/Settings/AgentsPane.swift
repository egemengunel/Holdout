//
//  AgentsPane.swift
//  Holdout
//

import SwiftUI

/// Connect agents, follow each one's setup steps, and set how Project buttons reach it.
struct AgentsPane: View {
    @State private var model = AgentConnections()
    @State private var expanded: Set<AgentInstaller.Agent> = []

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .agents, text: "Holdout listens to your coding agents through a small hook in each one's config. Nothing leaves your Mac.") {
                    if !model.connectable.isEmpty {
                        Button("Connect All Found (\(model.connectable.count))") { model.connectAll() }
                    }
                }
            }

            Section {
                ForEach(AgentInstaller.Agent.allCases) { agent in
                    DisclosureGroup(isExpanded: binding(for: agent)) {
                        AgentDetail(agent: agent, model: model)
                    } label: {
                        AgentRow(agent: agent, model: model)
                    }
                }
            } footer: {
                Text("Restart an agent after connecting it. Removing takes Holdout's entry back out of its config.")
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
        .task {
            await model.reload()
            // Open the ones that are half set up, so the next step is in view.
            expanded.formUnion(AgentInstaller.Agent.allCases.filter { model.statuses[$0] == .needsReview })
        }
    }

    private func binding(for agent: AgentInstaller.Agent) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(agent) },
            set: { if $0 { expanded.insert(agent) } else { expanded.remove(agent) } }
        )
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
        HStack(spacing: 12) {
            AgentIcon(agent: agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                Text(agent.coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.busy.contains(agent) {
                ProgressView().controlSize(.small)
            } else {
                switch model.status(agent) {
                case .connected:
                    StatusBadge(title: "Connected", color: .green)
                case .needsReview:
                    StatusBadge(title: "Needs approval", color: .orange)
                case .notConnected:
                    if agent.isPresent {
                        Button("Connect") { model.change(agent, install: true) }
                    } else {
                        StatusBadge(title: "Not installed", color: .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// An agent's setup steps and options, under its row.
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
        VStack(alignment: .leading, spacing: 16) {
            StepList(steps: AgentGuide.steps(
                for: agent,
                status: model.status(agent),
                connect: { model.change(agent, install: true) },
                recheck: { model.recheck(agent) }
            ))

            if agent == .claude {
                ClaudeModsSummary()
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show \(agent.name) sessions on the Agents tab", isOn: Binding(get: { !hidden }, set: { hidden = !$0 }))
                Picker("Project buttons", selection: $delivery) {
                    Text("Send into the chat").tag(HoldoutSettings.Delivery.automatic.rawValue)
                    Text("Copy to clipboard").tag(HoldoutSettings.Delivery.clipboard.rawValue)
                }
                .fixedSize()
                Text(delivery == HoldoutSettings.Delivery.clipboard.rawValue
                     ? "Buttons always copy their prompt and bring \(agent.name) forward."
                     : agent.projectButtons)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.status(agent) != .notConnected {
                HStack {
                    Spacer()
                    Button("Remove from \(agent.name)", role: .destructive) { model.change(agent, install: false) }
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 4)
    }
}

/// The Claude Code mods Holdout found, and whether one is reporting to it.
private struct ClaudeModsSummary: View {
    @State private var mods: [ClaudeMods.Mod] = []
    @State private var reporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude Code mods").font(.subheadline.weight(.medium))
            if mods.isEmpty && !reporting {
                Text("None found in ~/.claude/mods.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(mods) { mod in
                    Label(mod.name, systemImage: "puzzlepiece.extension")
                        .font(.callout)
                }
                if reporting {
                    Label("A mod is reporting to Holdout: its buttons show on the Project tab.", systemImage: "dot.radiowaves.left.and.right")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
        }
        .task {
            mods = ClaudeMods.installed
            reporting = ClaudeMods.isReporting
        }
    }
}
