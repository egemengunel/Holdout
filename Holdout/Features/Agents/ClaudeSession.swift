//
//  ClaudeSession.swift
//  Holdout
//

import Foundation

/// The latest state of one Claude Code session, as written by `Hooks/holdout-hook.sh`.
struct ClaudeSession: Decodable, Identifiable {
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
    let event: String
    let cwd: String?
    let tool: String?
    let detail: String?
    let notification: String?
    /// Bundle identifier of the app hosting the session (Claude, Terminal, Ghostty…).
    let app: String?
    let updatedAt: TimeInterval
    let turnStartedAt: TimeInterval

    var id: String { session }

    var project: String {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude"
    }

    var state: State {
        switch event {
        case "PreToolUse":
            .tool(name: tool ?? "Tool", detail: detail)
        case "PermissionRequest":
            .waiting
        case "Notification":
            needsAttention ? .waiting : .idle
        case "Stop":
            .done
        case "SessionStart":
            .idle
        default:
            .thinking
        }
    }

    private var needsAttention: Bool {
        switch notification {
        case "permission_prompt", "elicitation_dialog": true
        case nil: detail?.localizedCaseInsensitiveContains("permission") ?? false
        default: false
        }
    }
}
