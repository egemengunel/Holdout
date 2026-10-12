//
//  AgentGuide.swift
//  Nudge
//

import AppKit
import ApplicationServices

/// Step-by-step setup for each agent, shared by Settings and the welcome guide. The steps follow
/// what each agent needs before Nudge sees it (see CLAUDE.md for why each one is there).
enum AgentGuide {
    struct Step {
        struct Button {
            let title: String
            let action: @MainActor () -> Void
        }

        let title: String
        var detail: String?
        /// A line to paste into a terminal.
        var code: String?
        var button: Button?
        var isDone = false
        var buttonStaysWhenDone = false
    }

    /// `connect` and `recheck` come from the view that owns the agent's status.
    static func steps(
        for agent: AgentInstaller.Agent,
        status: AgentInstaller.Status,
        connect: @escaping @MainActor () -> Void,
        recheck: @escaping @MainActor () -> Void
    ) -> [Step] {
        let connected = status != .notConnected
        let seen = connected && hasSession(from: agent)
        let connectStep = Step(
            title: "Connect Nudge",
            detail: connectDetail(agent),
            button: .init(title: "Connect", action: connect),
            isDone: connected
        )

        switch agent {
        case .claude:
            return [
                connectStep,
                Step(
                    title: "Start a new Claude Code session",
                    detail: "Sessions pick up hooks when they start. Works in the CLI, the desktop app and the IDE extensions.",
                    isDone: seen
                ),
                Step(
                    title: "Your Claude Code mods show on the Touch Bar",
                    detail: "Connecting also loads the nudge-bridge mod, so Project buttons run straight in the chat and mods like ios-dock bring their buttons and build status to the Project tab. It appears here once a new session has started.",
                    isDone: ClaudeMods.isReporting
                ),
            ]
        case .cursor:
            return [
                connectStep,
                Step(title: "Restart Cursor", detail: "Cursor reads its hooks at launch.", isDone: seen),
                Step(
                    title: "Allow Nudge in Accessibility",
                    detail: "So Project buttons can type into Cursor's chat while it's idle. Without it, the prompt is copied for you to paste.",
                    button: .init(title: "Open Privacy & Security", action: { openAccessibilitySettings() }),
                    isDone: AXIsProcessTrusted()
                ),
            ]
        case .codex:
            return [
                connectStep,
                Step(
                    title: "Trust the hook in Codex",
                    detail: "Codex skips new hooks until you approve them: type /hooks in the Codex CLI, or approve it when the ChatGPT app asks. Then check again here.",
                    code: "/hooks",
                    button: .init(title: "Check Again", action: recheck),
                    isDone: status == .connected
                ),
                Step(title: "Start a new Codex session", detail: "One connection covers the Codex CLI and the ChatGPT app.", isDone: seen),
            ]
        case .antigravity:
            return [
                connectStep,
                Step(
                    title: "Run your sessions in the agy CLI",
                    detail: "On current builds only the Antigravity CLI runs hooks; the IDE and desktop app don't yet.",
                    isDone: seen
                ),
            ]
        case .opencode:
            return [
                connectStep,
                Step(title: "Restart OpenCode", detail: "OpenCode loads plugins when it starts.", isDone: seen),
            ]
        }
    }

    private static func connectDetail(_ agent: AgentInstaller.Agent) -> String {
        switch agent {
        case .claude: "Adds a hook to ~/.claude/settings.json. Cursor runs these too."
        case .cursor: "Adds hooks to ~/.cursor/hooks.json and ~/.claude/settings.json."
        case .codex: "Adds a hook to ~/.codex/hooks.json."
        case .antigravity: "Adds hooks to ~/.gemini/config/hooks.json."
        case .opencode: "Adds a plugin to ~/.config/opencode/plugins."
        }
    }

    /// Whether a session from this agent has reported, which means its hook runs.
    static func hasSession(from agent: AgentInstaller.Agent) -> Bool {
        let folder = AgentInstaller.support.appending(path: "sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.contains { file in
            guard let session = try? JSONDecoder().decode(AgentSession.self, from: Data(contentsOf: file)) else { return false }
            // Gemini CLI sessions count for Antigravity, which took over its hooks.
            let name = session.agent == "gemini" ? "antigravity" : session.agent ?? "claude"
            return name == agent.rawValue
        }
    }

    static func openAccessibilitySettings() {
        // Asking adds Nudge to the list, so there's something to switch on.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
