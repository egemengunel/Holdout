//
//  AgentSession.swift
//  Holdout
//

import Foundation

/// The latest state of one coding agent session, as written by `Hooks/holdout-hook.sh`,
/// which translates every agent's events to Claude Code's names.
struct AgentSession: Decodable, Identifiable {
    enum State: Equatable {
        case idle
        case thinking
        case tool(name: String, detail: String?)
        case waiting
        case done

        var isWorking: Bool {
            switch self {
            case .thinking, .tool: true
            default: false
            }
        }
    }

    let session: String
    /// Which agent runs the session (`claude`, `cursor`, `codex`…); nil from older hooks.
    let agent: String?
    let event: String
    let cwd: String?
    let tool: String?
    let detail: String?
    let notification: String?
    /// Bundle identifier of the app hosting the session (Claude, Cursor, Terminal, Ghostty…).
    let app: String?
    /// Files the session's edit tools wrote, oldest first, as the agent named them.
    let edited: [String]?
    /// Whether Cursor runs the pending Shell command in its sandbox, which never asks you.
    let sandboxed: Bool?
    let updatedAt: TimeInterval
    let turnStartedAt: TimeInterval

    var id: String { session }

    var agentName: String {
        switch agent ?? "claude" {
        case "claude": "Claude"
        case "cursor": "Cursor"
        case "codex": "Codex"
        case "gemini": "Gemini"
        case "antigravity": "Antigravity"
        case "opencode": "OpenCode"
        case let other: other.capitalized
        }
    }

    /// Whether the holdout-bridge mod, which runs inside Claude Code, covers this session.
    var usesBridge: Bool { agent == nil || agent == "claude" }

    var project: String {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? agentName
    }

    var state: State {
        switch event {
        case "PreToolUse":
            isAwaitingApproval ? .waiting : .tool(name: tool ?? "Tool", detail: detail)
        case "PermissionRequest":
            .waiting
        case "Notification":
            needsAttention ? .waiting : .idle
        case "Stop":
            .done
        case "SessionStart", "Interrupt":
            .idle
        default:
            .thinking
        }
    }

    /// Cursor has no hook for its approval prompt, but `preToolUse` fires before the prompt
    /// and `postToolUse` only after the user answers, so a command that hasn't returned
    /// for a few seconds may be waiting on you. Long builds trip it too.
    private var isAwaitingApproval: Bool {
        guard agent == "cursor", sandboxed != true, let tool, tool == "Shell" || tool.localizedCaseInsensitiveContains("mcp") else { return false }
        return Date.now.timeIntervalSince1970 - updatedAt > 8
    }

    private var needsAttention: Bool {
        switch notification {
        case "permission_prompt", "elicitation_dialog": true
        case nil: detail?.localizedCaseInsensitiveContains("permission") ?? false
        default: false
        }
    }
}
