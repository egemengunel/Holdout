//
//  ProjectProbe.swift
//  Holdout
//

import Foundation

/// What Holdout can tell about an agent's folder by itself: the git repo and branch, and
/// the Xcode project in it, found the way ios-dock does (an .xcodeproj within two levels).
struct ProjectProbe {
    let repoName: String
    let root: String
    let branch: String?
    /// Nil when the repo holds no Xcode project.
    let projectName: String?

    nonisolated static func probe(_ directory: String) async -> ProjectProbe? {
        let top = await Shell.git(["rev-parse", "--show-toplevel"], in: directory)
        let root = top.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard top.status == 0, !root.isEmpty else { return nil }

        let head = await Shell.git(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
        let branch = head.status == 0 ? head.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let name = URL(fileURLWithPath: root).lastPathComponent
        return ProjectProbe(repoName: name, root: root, branch: branch, projectName: hasXcodeProject(root) ? name : nil)
    }

    private nonisolated static func hasXcodeProject(_ root: String) -> Bool {
        let manager = FileManager.default
        let top = (try? manager.contentsOfDirectory(atPath: root)) ?? []
        if top.contains(where: { $0.hasSuffix(".xcodeproj") }) { return true }
        return top.contains { entry in
            guard entry != "build", !entry.hasPrefix(".") else { return false }
            let children = (try? manager.contentsOfDirectory(atPath: "\(root)/\(entry)")) ?? []
            return children.contains { $0.hasSuffix(".xcodeproj") }
        }
    }
}
