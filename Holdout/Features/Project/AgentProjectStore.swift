//
//  AgentProjectStore.swift
//  Holdout
//

import Foundation

/// The Project tab's feed for sessions no Claude Code plugin feeds: repo, branch and Xcode
/// project from the session's folder. Builds need nothing here: Xcode logs every build.
final class AgentProjectStore {
    /// How often a tracked session's folder is looked at again, for branch switches.
    private static let refreshInterval: TimeInterval = 10

    var onChange: (() -> Void)?
    private(set) var feeds: [String: ProjectFeed] = [:]
    private var checked: [String: (key: String, at: Date)] = [:]
    private var inFlight: Set<String> = []

    /// Refreshes these sessions' feeds when they changed or have aged; cheap to call often.
    func track(_ sessions: [AgentSession]) {
        for session in sessions {
            guard let cwd = session.cwd, !inFlight.contains(session.id) else { continue }
            let key = cwd
            if let last = checked[session.id], last.key == key, -last.at.timeIntervalSinceNow < Self.refreshInterval { continue }

            checked[session.id] = (key, .now)
            inFlight.insert(session.id)
            let id = session.id
            Task {
                let feed = await Self.feed(session: id, cwd: cwd)
                inFlight.remove(id)
                feeds[id] = feed
                onChange?()
            }
        }
        let tracked = Set(sessions.map(\.id))
        feeds = feeds.filter { tracked.contains($0.key) }
        checked = checked.filter { tracked.contains($0.key) }
    }

    private nonisolated static func feed(session: String, cwd: String) async -> ProjectFeed? {
        guard let probe = await ProjectProbe.probe(cwd) else { return nil }
        return ProjectFeed(
            session: session,
            cwd: cwd,
            updatedAt: Date.now.timeIntervalSince1970,
            buildAt: nil,
            repo: ProjectFeed.Repo(name: probe.repoName, root: probe.root, branch: probe.branch),
            project: probe.projectName.map { ProjectFeed.Project(name: $0, root: probe.root, branch: probe.branch) },
            build: nil,
            ship: nil,
            actions: nil,
            badges: nil
        )
    }
}
