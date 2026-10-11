//
//  WelcomeView.swift
//  Nudge
//

import SwiftUI

/// The first-run guide: pick your agents, finish each one's setup, choose some Project buttons.
/// Everything here is also in Settings; this just walks through it in order.
struct WelcomeView: View {
    private enum Page: Int, CaseIterable {
        case hello, agents, setup, buttons, done
    }

    /// `-NudgeWelcomePage 2` opens on that page, for screenshots.
    @State private var page = Page(rawValue: UserDefaults.standard.integer(forKey: "NudgeWelcomePage")) ?? .hello
    @State private var model = AgentConnections()
    @State private var chosenAgents: Set<AgentInstaller.Agent> = []
    @State private var chosenButtons: Set<String> = []
    @State private var opensAtLogin = NudgeSettings.opensAtLogin

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .hello: hello
                case .agents: agents
                case .setup: setup
                case .buttons: buttons
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(page)

            footer
        }
        .frame(width: 640, height: 580)
        .task {
            await model.reload()
            chosenAgents = Set(AgentInstaller.Agent.allCases.filter { $0.isPresent })
        }
    }

    // MARK: Pages

    private var hello: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            VStack(spacing: 8) {
                Text("Welcome to Nudge").font(.largeTitle.weight(.semibold))
                Text("Your coding agents, builds and Mac, on the Touch Bar.\nA status light tells you when an agent needs you, so you can look away.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            CyclingPreview()
                .frame(maxWidth: 460)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
    }

    private var agents: some View {
        page(title: "Which agents do you use?", subtitle: "Nudge adds a small hook to each one's config, so it can see when sessions work, wait and finish. Nothing leaves your Mac.") {
            VStack(spacing: 0) {
                ForEach(AgentInstaller.Agent.allCases) { agent in
                    let status = model.status(agent)
                    HStack(spacing: 12) {
                        AgentIcon(agent: agent, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).font(.headline)
                            Text(agent.isPresent ? agent.coverage : "Not found on this Mac")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if status != .notConnected {
                            AgentStatusLabel(agent: agent, status: status)
                        } else {
                            Toggle(agent.name, isOn: Binding(
                                get: { chosenAgents.contains(agent) },
                                set: { if $0 { chosenAgents.insert(agent) } else { chosenAgents.remove(agent) } }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .disabled(!agent.isPresent)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .opacity(agent.isPresent || status != .notConnected ? 1 : 0.5)
                    if agent != AgentInstaller.Agent.allCases.last { Divider().padding(.leading, 60) }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
        }
    }

    private var setup: some View {
        let agents = AgentInstaller.Agent.allCases.filter { model.status($0) != .notConnected || model.busy.contains($0) }
        return page(title: "Finish setting up", subtitle: agents.isEmpty
                    ? "No agents are connected yet. You can connect them any time in Settings › Agents."
                    : "A few agents need one more thing before Nudge can see them.") {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(agents) { agent in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                AgentIcon(agent: agent, size: 26)
                                Text(agent.name).font(.headline)
                                Spacer()
                                if model.busy.contains(agent) { ProgressView().controlSize(.small) }
                            }
                            VStack(alignment: .leading, spacing: 10) {
                            StepList(steps: AgentGuide.steps(
                                for: agent,
                                status: model.status(agent),
                                connect: { model.change(agent, install: true) },
                                recheck: { model.recheck(agent) }
                            ))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
                    }
                    if let problem = model.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var buttons: some View {
        page(title: "Pick your Project buttons", subtitle: "The Project tab has buttons that send a prompt to the agent you're working with. Build and Commit are built in; add any of these too. You can edit them or make your own in Settings › Buttons.") {
            VStack(spacing: 14) {
                TouchBarButtonsPreview(buttons: [("Build", "hammer"), ("Commit", "checkmark.circle")]
                    + CustomAction.presets.filter { chosenButtons.contains($0.title) }.map { ($0.title, $0.symbol) })
                    .animation(.default, value: chosenButtons)
                // An eager Grid, so the cards slide in with the page (a lazy one only fades in).
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: CustomAction.presets.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(CustomAction.presets[start..<min(start + 2, CustomAction.presets.count)], id: \.title) { preset in
                                PresetCard(preset: preset, isOn: chosenButtons.contains(preset.title)) {
                                    if chosenButtons.contains(preset.title) { chosenButtons.remove(preset.title) } else { chosenButtons.insert(preset.title) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("You're all set").font(.largeTitle.weight(.semibold))
                Text("Tap the hand in the Control Strip, at the right end of the Touch Bar, to open Nudge. Settings live in the menu bar under the same hand.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }
            TouchBarPreview(pulse: .idle)
                .frame(maxWidth: 460)
            Toggle("Open Nudge at login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, value in
                    NudgeSettings.opensAtLogin = value
                    opensAtLogin = NudgeSettings.opensAtLogin
                }
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
    }

    private func page<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(.horizontal, 40)
        .padding(.top, 44)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if page != .hello && page != .done {
                Button("Back") { go(-1) }
            }
            Spacer()
            Button(primaryTitle, action: primary)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .overlay {
            HStack(spacing: 7) {
                ForEach(Page.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == page ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Divider() }
    }

    private var toConnect: [AgentInstaller.Agent] {
        AgentInstaller.Agent.allCases.filter { chosenAgents.contains($0) && model.status($0) == .notConnected }
    }

    private var primaryTitle: String {
        switch page {
        case .hello: "Get Started"
        case .agents: toConnect.isEmpty ? "Continue" : "Connect \(toConnect.count == 1 ? toConnect[0].name : "\(toConnect.count) Agents")"
        case .setup: "Continue"
        case .buttons: chosenButtons.isEmpty ? "Skip" : "Add \(chosenButtons.count == 1 ? "Button" : "\(chosenButtons.count) Buttons")"
        case .done: "Done"
        }
    }

    private func primary() {
        switch page {
        case .agents:
            for agent in toConnect { model.change(agent, install: true) }
            go(1)
        case .buttons:
            var custom = NudgeSettings.customActions
            let existing = Set(custom.map(\.title))
            for preset in CustomAction.presets where chosenButtons.contains(preset.title) && !existing.contains(preset.title) {
                var action = preset
                action.id = UUID().uuidString
                custom.append(action)
            }
            NudgeSettings.customActions = custom
            go(1)
        case .done:
            NudgeWindows.closeWelcome()
        default:
            go(1)
        }
    }

    private func go(_ step: Int) {
        guard let next = Page(rawValue: page.rawValue + step) else { return }
        withAnimation(.snappy) { page = next }
    }
}

private struct PresetCard: View {
    let preset: CustomAction
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: preset.symbol)
                    .font(.title3)
                    .frame(width: 24)
                    .foregroundStyle(isOn ? .white : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title).font(.headline)
                    Text(preset.prompt)
                        .font(.caption)
                        .lineLimit(2)
                        .opacity(0.8)
                }
                .foregroundStyle(isOn ? .white : .primary)
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? .white : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.background.secondary))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator).opacity(isOn ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The strip mock cycling through the status light's states, with a caption.
private struct CyclingPreview: View {
    private static let states: [(pulse: IconPulse, label: String)] = [
        (.working, "Agents are working"),
        (.waiting, "A session needs you"),
        (.done(at: 0), "A session finished"),
        (.done(at: 0, symbol: "hammer.fill"), "Build succeeded"),
        (.alert, "Memory is critical"),
    ]

    @State private var index = 0

    var body: some View {
        VStack(spacing: 10) {
            TouchBarPreview(pulse: Self.states[index].pulse)
            Text(Self.states[index].label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation { index = (index + 1) % Self.states.count }
            }
        }
    }
}
