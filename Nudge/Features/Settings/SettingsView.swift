//
//  SettingsView.swift
//  Nudge
//

import AppKit
import SwiftUI

/// The sidebar's panes, in order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case agents = "Agents"
    case buttons = "Buttons"
    case statusLight = "StatusLight"
    case about = "About"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statusLight: "Status Light"
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .agents: "terminal.fill"
        case .buttons: "square.grid.2x2.fill"
        case .statusLight: "light.beacon.max.fill"
        case .about: "info"
        }
    }

    /// The color of the pane's icon tile, like System Settings' sidebar.
    var tint: Color {
        switch self {
        case .general: .gray
        case .agents: .indigo
        case .buttons: .blue
        case .statusLight: .orange
        case .about: .teal
        }
    }

    /// Extra words the sidebar's search matches.
    var keywords: [String] {
        switch self {
        case .general: ["login", "startup", "welcome", "strip"]
        case .agents: ["claude", "cursor", "codex", "chatgpt", "antigravity", "opencode", "hooks", "connect", "mods"]
        case .buttons: ["project", "prompt", "build", "commit", "custom"]
        case .statusLight: ["alerts", "flash", "icon", "memory", "cpu", "notifications"]
        case .about: ["version", "github"]
        }
    }
}

struct SettingsView: View {
    /// `-NudgeSettingsTab Agents` opens on that pane, for screenshots.
    @State private var pane: SettingsPane? = UserDefaults.standard.string(forKey: "NudgeSettingsTab").flatMap(SettingsPane.init) ?? .general
    @State private var path = NavigationPath()
    @State private var search = ""

    private var panes: [SettingsPane] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter { pane in
            ([pane.title] + pane.keywords).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(panes, selection: $pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(pane: pane)
                }
                .tag(pane)
            }
            .searchable(text: $search, placement: .sidebar)
            // The sidebar toggle stays: a toolbar item is what lets the sidebar run the full
            // height with the traffic lights in it.
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            NavigationStack(path: $path) {
                detail(pane ?? .general)
                    .navigationTitle((pane ?? .general).title)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .onChange(of: pane) { path = NavigationPath() }
        .onAppear { DispatchQueue.main.async { NudgeWindows.closeIfUnrequested() } }
        .onReceive(NotificationCenter.default.publisher(for: .nudgeSelectSettingsTab)) { note in
            if let name = note.object as? String, let selected = SettingsPane(rawValue: name) { pane = selected }
        }
    }

    @ViewBuilder
    private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane()
        case .agents: AgentsPane()
        case .buttons: ButtonsPane()
        case .statusLight: StatusLightPane()
        case .about: AboutPane()
        }
    }
}

private struct GeneralPane: View {
    @State private var opensAtLogin = NudgeSettings.opensAtLogin
    @State private var connected = 0

    private static let tabs: [(symbol: String, title: String, text: String)] = [
        ("terminal", "Agents", "Every coding agent session: working, waiting on you, or done."),
        ("iphone", "Sim", "Boot, switch and screenshot iOS Simulators."),
        ("hammer", "Project", "The project you're in, its last build, and your buttons."),
        ("memorychip", "Mac", "Memory pressure and the processes eating your CPU."),
    ]

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .general, text: "Nudge puts your coding agents, builds and Mac on the Touch Bar. Tap the hand in the Control Strip to open it.") {
                    TouchBarPreview(pulse: .idle)
                }
            }

            Section("On the strip") {
                ForEach(Self.tabs, id: \.title) { tab in
                    Label {
                        Text(tab.title)
                        Text(tab.text)
                    } icon: {
                        Image(systemName: tab.symbol)
                            .frame(width: 22)
                    }
                }
            }

            Section {
                Toggle("Open Nudge at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, value in
                        NudgeSettings.opensAtLogin = value
                        opensAtLogin = NudgeSettings.opensAtLogin
                    }
                LabeledContent("Agents") {
                    HStack {
                        Text(connected == 0 ? "None connected" : "\(connected) connected")
                            .foregroundStyle(.secondary)
                        Button("Manage…") { NudgeWindows.showSettings(.agents) }
                    }
                }
                LabeledContent("Setup") {
                    Button("Show Welcome Guide…") { NudgeWindows.showWelcome() }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            connected = AgentInstaller.Agent.allCases.filter(\.isInstalled).count
        }
    }
}

private struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Text("Nudge").font(.largeTitle.weight(.semibold))
            Text(version).foregroundStyle(.secondary)
            Text("Your coding agents, simulator, builds and Mac, on the Touch Bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/egemengunel/Nudge")!) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/egemengunel/Nudge/issues")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
