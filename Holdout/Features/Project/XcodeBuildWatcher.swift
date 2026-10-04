//
//  XcodeBuildWatcher.swift
//  Holdout
//

import Foundation

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
