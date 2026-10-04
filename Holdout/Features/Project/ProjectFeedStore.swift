//
//  ProjectFeedStore.swift
//  Holdout
//

import Foundation

/// Reads the bridge mod's feed files, one per Claude Code session.
final class ProjectFeedStore {
    static let directory = URL.applicationSupportDirectory.appending(path: "Holdout/feeds", directoryHint: .isDirectory)
    private static let pollInterval: TimeInterval = 2
    /// A feed whose session has ended is removed after this; the mod can't delete files itself.
    private static let endedGrace: TimeInterval = 5 * 60

    var onChange: (() -> Void)?
    /// Whether a session is still open; set by the owner from the Agents hook's sessions.
    var isLive: (String) -> Bool = { _ in true }
    private(set) var feeds: [String: ProjectFeed] = [:]
    private var modified: [URL: Date] = [:]
    private var timer: Timer?

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    /// The mod writes files in place, which a directory watch wouldn't see, so this compares dates.
    private func scan() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var changed = false
        var present: Set<URL> = []

        for url in files where url.pathExtension == "json" {
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            let session = url.deletingPathExtension().lastPathComponent
            if !isLive(session) && -date.timeIntervalSinceNow > Self.endedGrace {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            present.insert(url)
            guard date != modified[url] else { continue }
            modified[url] = date
            feeds[session] = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ProjectFeed.self, from: $0) }
            changed = true
        }

        for url in modified.keys where !present.contains(url) {
            modified[url] = nil
            feeds[url.deletingPathExtension().lastPathComponent] = nil
            changed = true
        }
        if changed {
            onChange?()
        }
    }
}
