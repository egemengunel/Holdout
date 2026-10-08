//
//  ProjectFeed.swift
//  Holdout
//

import Foundation

/// What a Claude Code plugin (see `Mods/holdout-bridge`) or Holdout itself reports for one
/// session, or what `AgentProjectStore` works out for any other agent's session.
struct ProjectFeed: Decodable {
    struct Repo: Decodable {
        let name: String
        let root: String?
        let branch: String?
    }

    struct Project: Decodable {
        let name: String
        let root: String?
        let branch: String?
    }

    struct Build: Decodable {
        let project: String
        let isOk: Bool
        let seconds: Double
        let errorCount: Int
        let firstError: String?
        let warningCount: Int?
    }

    struct Ship: Decodable {
        let phase: String
        let ahead: Int
        let note: String?
    }

    let session: String
    let cwd: String?
    let updatedAt: TimeInterval
    /// When `build` last changed; a Claude Code plugin's build result carries no time of its own.
    let buildAt: TimeInterval?
    let repo: Repo?
    let project: Project?
    let build: Build?
    let ship: Ship?

    /// A session nothing has detected anything yet has nothing to show.
    var hasContent: Bool { repo != nil || project != nil || build != nil || (ship.map { $0.phase != "idle" } ?? false) }
}
