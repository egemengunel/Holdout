//
//  SettingsView.swift
//  Holdout
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
        case .about: "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .agents: .indigo
        case .buttons: .blue
        case .statusLight: .orange
        case .about: .pink
        }
    }
}

struct SettingsView: View {
    /// `-HoldoutSettingsTab Agents` opens on that pane, for screenshots.
    @State private var pane: SettingsPane? = UserDefaults.standard.string(forKey: "HoldoutSettingsTab").flatMap(SettingsPane.init) ?? .general

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        SymbolTile(symbol: pane.symbol, tint: pane.tint)
                    }
                    .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(pane ?? .general)
                .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: 640, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: .holdoutSelectSettingsTab)) { note in
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
    @State private var opensAtLogin = HoldoutSettings.opensAtLogin
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
                PaneHeader(pane: .general, text: "Holdout puts your coding agents, builds and Mac on the Touch Bar. Tap the hand in the Control Strip to open it.") {
                    TouchBarPreview(pulse: .idle)
                }
            }

            Section("On the strip") {
                ForEach(Self.tabs, id: \.title) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 24)
                            .background(.black, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title)
                            Text(tab.text).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Toggle("Open Holdout at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, value in
                        HoldoutSettings.opensAtLogin = value
                        opensAtLogin = HoldoutSettings.opensAtLogin
                    }
                LabeledContent("Agents") {
                    HStack {
                        Text(connected == 0 ? "None connected" : "\(connected) connected")
                            .foregroundStyle(.secondary)
                        Button("Manage…") { HoldoutWindows.showSettings(.agents) }
                    }
                }
                LabeledContent("Setup") {
                    Button("Show Welcome Guide…") { HoldoutWindows.showWelcome() }
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
            Text("Holdout").font(.largeTitle.weight(.semibold))
            Text(version).foregroundStyle(.secondary)
            Text("Your coding agents, simulator, builds and Mac, on the Touch Bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/egemengunel/Holdout")!) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/egemengunel/Holdout/issues")!) {
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
