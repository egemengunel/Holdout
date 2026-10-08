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
        case claude, cursor, codex, antigravity, opencode

        var id: String { rawValue }

        var name: String {
            switch self {
            case .claude: "Claude Code"
            case .cursor: "Cursor"
            case .codex: "Codex"
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
            case .antigravity: "Antigravity CLI (agy), Gemini CLI's successor. The IDE doesn't run hooks yet"
            case .opencode: "OpenCode in the terminal"
            }
        }

        /// What the Project tab's buttons do for this agent, from what each one lets an outside
        /// app do (none takes text into an idle chat except OpenCode's plugin and Cursor's chat).
        var projectButtons: String {
            switch self {
            case .claude: "Run in the chat through the holdout-bridge plugin; without it, copied and the app comes forward."
            case .cursor: "Typed into the Cursor chat (needs Accessibility), or sent when its turn ends."
            case .codex: "Sent when the turn ends. When idle, copied and the chat opens."
            case .antigravity: "Sent when the turn ends. When idle, copied."
            case .opencode: "Submitted into the terminal UI through its plugin."
            }
        }

        /// The agent's app icon, when its app is installed.
        var appIcon: NSImage? {
            let names: [String] = switch self {
            case .claude: ["Claude"]
            case .cursor: ["Cursor"]
            case .codex: ["Codex"]
            case .antigravity: ["Antigravity"]
            case .opencode: []
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

    enum Status {
        case notConnected
        case connected
        /// Registered, but the agent won't run it until the user approves it (Codex's hook trust).
        case needsReview
    }

    static func status(of agent: Agent) async -> Status {
        guard agent.isInstalled else { return .notConnected }
        guard agent == .codex else { return .connected }
        return await codexHooksTrusted() == false ? .needsReview : .connected
    }

    /// Codex runs a hook only once the user has trusted its current hash (`/hooks` in the CLI,
    /// or the ChatGPT app's prompt). Asks a throwaway `codex app-server` for `hooks/list`, the
    /// call the app makes; nil when Codex can't be asked.
    nonisolated static func codexHooksTrusted() async -> Bool? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let daemons = (try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.codex/packages/app-server-daemon/releases")) ?? []
        let candidates = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            + daemons.sorted().reversed().map { "\(home)/.codex/packages/app-server-daemon/releases/\($0)/bin/codex" }
        guard let codex = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }

        let requests = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"holdout","title":"Holdout","version":"1"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"hooks/list","params":{}}"#,
        ].joined(separator: "\n") + "\n"

        return await withCheckedContinuation { continuation in
            let process = Process()
            let input = Pipe(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: codex)
            process.arguments = ["app-server", "--listen", "stdio://"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let lock = NSLock()
            var buffer = Data()
            var finished = false
            func finish(_ result: Bool?) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }
                continuation.resume(returning: result)
            }
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return finish(nil) }
                lock.lock(); buffer.append(chunk); let text = String(decoding: buffer, as: UTF8.self); lock.unlock()
                for line in text.split(separator: "\n") {
                    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          object["id"] as? Int == 2 else { continue }
                    let entries = (object["result"] as? [String: Any])?["data"] as? [[String: Any]] ?? []
                    let ours = entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.filter {
                        (($0["command"] as? String) ?? ($0["handler"] as? [String: Any])?["command"] as? String ?? "").contains("holdout-hook.sh")
                    }
                    return finish(ours.isEmpty ? nil : ours.allSatisfy { ["trusted", "managed"].contains($0["trustStatus"] as? String) })
                }
            }
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(requests.utf8))
            } catch {
                return finish(nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { finish(nil) }
        }
    }

    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Holdout")
    }

    static var runtime: URL { support.appending(path: "runtime") }

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
