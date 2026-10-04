//
//  ProjectStatus.swift
//  Holdout
//

import Foundation

/// The result of the most recent Xcode build, read from DerivedData's build logs.
struct XcodeBuild: Equatable {
    let project: String
    let workspace: URL?
    let finishedAt: Date
    let succeeded: Bool
    let errors: Int
    let warnings: Int
}

/// Watches every project's `Logs/Build/LogStoreManifest.plist` in DerivedData.
/// Xcode rewrites a manifest when a build finishes, so only changed ones are re-read.
final class XcodeBuildWatcher {
    private static let derivedData = URL.homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
    private static let pollInterval: TimeInterval = 2

    var onChange: (() -> Void)?
    private(set) var latest: XcodeBuild?
    private var modified: [URL: Date] = [:]
    private var builds: [URL: XcodeBuild] = [:]
    private var timer: Timer?

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    private func scan() {
        let projects = (try? FileManager.default.contentsOfDirectory(at: Self.derivedData, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let manifest = project.appending(path: "Logs/Build/LogStoreManifest.plist")
            guard let date = (try? manifest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  date != modified[manifest]
            else { continue }
            modified[manifest] = date
            builds[manifest] = Self.lastBuild(manifest: manifest, projectFolder: project)
        }

        let newest = builds.values.max { $0.finishedAt < $1.finishedAt }
        guard newest != latest else { return }
        latest = newest
        onChange?()
    }

    private static func lastBuild(manifest: URL, projectFolder: URL) -> XcodeBuild? {
        guard let data = try? Data(contentsOf: manifest),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let logs = plist["logs"] as? [String: [String: Any]],
              let log = logs.values.max(by: { stopped($0) < stopped($1) }),
              let observable = log["primaryObservable"] as? [String: Any]
        else { return nil }

        let errors = observable["totalNumberOfErrors"] as? Int ?? 0
        let workspace = workspacePath(projectFolder)
        return XcodeBuild(
            project: workspace?.deletingPathExtension().lastPathComponent ?? projectName(projectFolder),
            workspace: workspace,
            finishedAt: Date(timeIntervalSinceReferenceDate: stopped(log)),
            succeeded: observable["highLevelStatus"] as? String != "E" && errors == 0,
            errors: errors,
            warnings: observable["totalNumberOfWarnings"] as? Int ?? 0
        )
    }

    private static func stopped(_ log: [String: Any]) -> TimeInterval {
        log["timeStoppedRecording"] as? TimeInterval ?? 0
    }

    /// DerivedData records which .xcodeproj or .xcworkspace each folder belongs to.
    private static func workspacePath(_ projectFolder: URL) -> URL? {
        guard let info = NSDictionary(contentsOf: projectFolder.appending(path: "info.plist")),
              let path = info["WorkspacePath"] as? String
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// "Holdout-heswrlfryymtmsevxxyrbewtsrlf" → "Holdout"
    private static func projectName(_ projectFolder: URL) -> String {
        let name = projectFolder.lastPathComponent
        return name.range(of: "-", options: .backwards).map { String(name[..<$0.lowerBound]) } ?? name
    }
}

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
