//
//  WelcomeView.swift
//  Nudge
//

import SwiftUI

/// The first-run guide: pick your agents, finish each one's setup, choose some Project buttons.
/// Everything here is also in Settings; this just walks through it in order. It's black and
/// cinematic: the first page plays the film of the Touch Bar, the others open on a still from it.
struct WelcomeView: View {
    private enum Page: Int, CaseIterable {
        case hello, agents, setup, buttons, done
    }

    /// `-NudgeWelcomePage 2` opens on that page, for screenshots.
    @State private var page = Page(rawValue: UserDefaults.standard.integer(forKey: "NudgeWelcomePage")) ?? .hello
    @State private var model = AgentConnections()
    @State private var chosenAgents: Set<AgentInstaller.Agent> = []
    @State private var chosenButtons: Set<String> = []
    /// Slash commands of the Claude Code mods found on this Mac, and those picked as buttons.
    @State private var modCommands: [ClaudeMods.Command] = []
    @State private var chosenCommands: Set<String> = []
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
        .frame(width: 720, height: 640)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task {
            await model.reload()
            chosenAgents = Set(AgentInstaller.Agent.allCases.filter { $0.isPresent })
            let added = NudgeSettings.customActions
            modCommands = ClaudeMods.commands.filter { command in !added.contains { $0.runs(command) } }
        }
    }

    // MARK: Pages

    private var hello: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(spacing: 8) {
                    Text("Welcome to Nudge").font(.largeTitle.weight(.semibold))
                    Text("Your coding agents, builds and Mac, on the Touch Bar.\nA status light tells you when an agent needs you, so you can look away.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 44)
            .padding(.horizontal, 48)
            Spacer(minLength: 0)
            CinematicFilm(name: "WelcomeFilm")
            Spacer(minLength: 0)
        }
    }

    private var agents: some View {
        page(header: TouchBarStage(plate: .strip) { AgentsArrivingBar() }, title: "Which agents do you use?", subtitle: "Nudge adds a small hook to each one's config, so it can see when sessions work, wait and finish. Nothing leaves your Mac.") {
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
        return page(header: CinematicStill(name: "WelcomeSetup"), title: "Finish setting up", subtitle: agents.isEmpty
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
        page(header: TouchBarStage(plate: .strip) { ProjectBar(buttons: chosenBarButtons) }, title: "Pick your Project buttons", subtitle: "The Project tab has buttons that send a prompt to the agent you're working with. Build and Commit are built in; add any of these too. You can edit them or make your own in Settings › Buttons.") {
            ScrollViewReader { proxy in
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Color.clear.frame(height: 0).id("top")
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
                if !modCommands.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From your Claude Code mods").font(.headline)
                        Text("Run the command in the chat, in Claude Code sessions.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        ForEach(Array(stride(from: 0, to: modCommands.count, by: 2)), id: \.self) { start in
                            GridRow {
                                ForEach(modCommands[start..<min(start + 2, modCommands.count)]) { command in
                                    PresetCard(preset: CustomAction(command), detail: "\(command.mod) · \(command.description)",
                                               isOn: chosenCommands.contains(command.id)) {
                                        if chosenCommands.contains(command.id) { chosenCommands.remove(command.id) } else { chosenCommands.insert(command.id) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
            // Opens on the presets; something scrolls the last card into view as the page appears.
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                proxy.scrollTo("top", anchor: .top)
            }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 0) {
            // The session's done: the bar flashes its green check.
            TouchBarStage(plate: .wide, clip: "BarSessionDone")
            VStack(spacing: 14) {
                Text("You're all set").font(.largeTitle.weight(.semibold))
                Text("Tap the hand in the Control Strip, at the right end of the Touch Bar, to open Nudge. Settings live in the menu bar under the same hand.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 460)
                Toggle("Open Nudge at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, value in
                        NudgeSettings.opensAtLogin = value
                        opensAtLogin = NudgeSettings.opensAtLogin
                    }
                    .padding(.top, 4)
            }
            .padding(.top, -24)
            .padding(.horizontal, 48)
            Spacer(minLength: 0)
        }
        .padding(.top, 28)
    }

    /// The Project tab's buttons as picked so far, for the bar on the buttons page.
    private var chosenBarButtons: [ProjectBar.Button] {
        [ProjectBar.Button(title: "Build", symbol: "hammer"), ProjectBar.Button(title: "Commit", symbol: "checkmark.circle")]
            + CustomAction.presets.filter { chosenButtons.contains($0.title) }.map { ProjectBar.Button(title: $0.title, symbol: $0.symbol) }
            + modCommands.filter { chosenCommands.contains($0.id) }.map { CustomAction($0) }.map { ProjectBar.Button(title: $0.title, symbol: $0.symbol) }
    }

    /// A step page: a render across the top, dissolving into the title.
    private func page<Header: View, Content: View>(header: Header, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            stepContent(title: title, subtitle: subtitle, content: content)
                .padding(.top, -44)
        }
    }

    private func stepContent<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
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
    }

    private var toConnect: [AgentInstaller.Agent] {
        AgentInstaller.Agent.allCases.filter { chosenAgents.contains($0) && model.status($0) == .notConnected }
    }

    private var primaryTitle: String {
        let buttons = chosenButtons.count + chosenCommands.count
        return switch page {
        case .hello: "Get Started"
        case .agents: toConnect.isEmpty ? "Continue" : "Connect \(toConnect.count == 1 ? toConnect[0].name : "\(toConnect.count) Agents")"
        case .setup: "Continue"
        case .buttons: buttons == 0 ? "Skip" : "Add \(buttons == 1 ? "Button" : "\(buttons) Buttons")"
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
            custom += modCommands.filter { chosenCommands.contains($0.id) }.map { CustomAction($0) }
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
    /// The line under the title; the prompt unless given.
    var detail: String? = nil
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
                    Text(detail ?? preset.prompt)
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
