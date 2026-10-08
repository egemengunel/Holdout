//
//  AgentInstaller.swift
//  Holdout
//

import AppKit
import Foundation

/// Registers Holdout's hook with coding agents. The scripts ship inside the app; they are copied
/// to Application Support first so the paths written into agents' configs survive moving or
/// updating the app.
enum AgentInstaller {
    enum Agent: String, CaseIterable, Identifiable {
        case claude, cursor, codex, gemini, antigravity, opencode

        var id: String { rawValue }

        var name: String {
            switch self {
            case .claude: "Claude Code"
            case .cursor: "Cursor"
            case .codex: "Codex"
            case .gemini: "Gemini CLI"
            case .antigravity: "Antigravity"
            case .opencode: "OpenCode"
            }
        }

        /// What one connection covers, so people don't wonder about CLI versus app.
        var coverage: String {
            switch self {
            case .claude: "CLI, desktop app and IDE extensions"
            case .cursor: "Cursor's agent chat"
            case .codex: "Codex CLI and the ChatGPT app · review the hook once with /hooks"
            case .gemini: "Gemini CLI"
            case .antigravity: "The agy CLI (the IDE doesn't run hooks yet)"
            case .opencode: "OpenCode in the terminal"
            }
        }

        /// The agent's app icon, when its app is installed.
        var appIcon: NSImage? {
            let names: [String] = switch self {
            case .claude: ["Claude"]
            case .cursor: ["Cursor"]
            case .codex: ["Codex"]
            case .antigravity: ["Antigravity"]
            case .gemini, .opencode: []
            }
            for name in names {
                for directory in ["/Applications", NSHomeDirectory() + "/Applications"] {
                    let path = "\(directory)/\(name).app"
                    if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
                }
            }
            return nil
        }

        /// The logo bundled in the asset catalog, used when the agent has no app to take an icon from.
        var logoAsset: String? {
            switch self {
            case .claude, .cursor: nil
            case .codex: "AgentCodex"
            case .gemini: "AgentGemini"
            case .antigravity: "AgentAntigravity"
            case .opencode: "AgentOpenCode"
            }
        }

        /// The file Holdout's entry goes in.
        fileprivate var config: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return switch self {
            case .claude: home.appending(path: ".claude/settings.json")
            case .cursor: home.appending(path: ".cursor/hooks.json")
            case .codex: home.appending(path: ".codex/hooks.json")
            case .gemini: home.appending(path: ".gemini/settings.json")
            case .antigravity: home.appending(path: ".gemini/config/hooks.json")
            case .opencode: home.appending(path: ".config/opencode/plugins/holdout.js")
            }
        }

        /// Whether the agent seems to be on this Mac.
        var isPresent: Bool {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let paths: [String] = switch self {
            case .claude: [".claude"]
            case .cursor: [".cursor"]
            case .codex: [".codex"]
            case .gemini: [".gemini/settings.json"]
            case .antigravity: [".gemini/antigravity"]
            case .opencode: [".config/opencode"]
            }
            return paths.contains { fm.fileExists(atPath: home.appending(path: $0).path) }
                || (self == .antigravity && fm.fileExists(atPath: "/Applications/Antigravity.app"))
        }

        var isInstalled: Bool {
            guard let text = try? String(contentsOf: config, encoding: .utf8) else { return false }
            return self == .opencode || text.contains("holdout-hook.sh")
        }
    }

    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Holdout")
    }

    static var runtime: URL { support.appending(path: "runtime") }

    /// Where the holdout-bridge Claude Code mod lives after `install`.
    static var bridge: URL { runtime.appending(path: "holdout-bridge") }

    private static var bundled: URL? { Bundle.main.resourceURL?.appending(path: "Runtime") }

    /// Copies the bundled scripts into Application Support. Returns false outside a built app.
    @discardableResult
    static func syncRuntime() async -> Bool {
        guard let bundled, FileManager.default.fileExists(atPath: bundled.path) else { return false }
        try? FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        let result = await Shell.run("/usr/bin/rsync", ["-a", "--delete", bundled.path + "/", runtime.path + "/"])
        return result.status == 0
    }

    /// Keeps an existing install current after the app updates.
    static func refreshIfInstalled() async {
        if FileManager.default.fileExists(atPath: runtime.path) { await syncRuntime() }
    }

    static func install(_ agent: Agent) async -> String? {
        guard await syncRuntime() else { return "The bundled hooks weren't found. Run Hooks/install.sh from the repository instead." }
        return await runScript([agent.rawValue])
    }

    static func remove(_ agent: Agent) async -> String? {
        let script = runtime.appending(path: "Hooks/install.sh")
        guard FileManager.default.fileExists(atPath: script.path) else { return nil }
        return await runScript(["--remove", agent.rawValue])
    }

    private static func runScript(_ arguments: [String]) async -> String? {
        let script = runtime.appending(path: "Hooks/install.sh").path
        let result = await Shell.run("/bin/sh", [script] + arguments)
        return result.status == 0 && !result.output.contains("could not parse") ? nil : result.output
    }
}
