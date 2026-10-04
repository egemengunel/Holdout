//
//  ProjectFeed.swift
//  Holdout
//

import Foundation

/// What the holdout-bridge mod mirrors from ios-dock and swift-design-lint for one session.
struct ProjectFeed: Decodable {
    struct Repo: Decodable {
        let name: String
        let branch: String?
    }

    struct Project: Decodable {
        let name: String
        let architecture: String
        let deploymentTarget: String?
        let isSynced: Bool
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

    struct Lint: Decodable {
        let issues: Int
        let checkedEdits: Int
    }

    let session: String
    let cwd: String?
    let updatedAt: TimeInterval
    let repo: Repo?
    let project: Project?
    let build: Build?
    let ship: Ship?
    let lint: Lint?

    /// A session whose mods haven't detected anything yet has nothing to show.
    var hasContent: Bool { repo != nil || project != nil || build != nil || lint != nil || (ship.map { $0.phase != "idle" } ?? false) }
}
