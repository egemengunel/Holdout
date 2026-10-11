//
//  ClaudeMods.swift
//  Nudge
//

import Foundation

/// The Claude Code mods on this Mac, and whether any of them reports to Nudge. A mod that
/// writes `feeds/<session>.json` (like the bundled nudge-bridge) gives Claude Code sessions a
/// richer Project tab and can add its own buttons there.
enum ClaudeMods {
    struct Mod: Identifiable, Hashable {
        let name: String
        let path: String
        var id: String { path }
    }

    /// Folders under `~/.claude/mods` that look like mods (they have `hooks/hooks.json`).
    static var installed: [Mod] {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/mods")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            let path = folder.appending(path: name).path
            guard FileManager.default.fileExists(atPath: path + "/hooks/hooks.json") else { return nil }
            return Mod(name: name, path: path)
        }
    }

    /// The nudge-bridge copy that ships inside the app, kept at a stable path.
    static var bridge: URL { AgentInstaller.runtime.appending(path: "Mods/nudge-bridge") }

    static var bridgeIsBundled: Bool { FileManager.default.fileExists(atPath: bridge.path) }

    /// The line that loads the bridge into Claude Code, for a shell profile.
    static var bridgeExport: String {
        #"export CLAUDE_CODE_PLUGIN_DIRS="${CLAUDE_CODE_PLUGIN_DIRS:+$CLAUDE_CODE_PLUGIN_DIRS:}\#(bridge.path)""#
    }

    /// Buttons that mods offered in feeds written in the last week, by title, with no repeats.
    static var reportedButtons: [ProjectFeed.Control] {
        let folder = AgentInstaller.support.appending(path: "feeds")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let recent = files.filter {
            let date = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return Date.now.timeIntervalSince(date) < 7 * 86_400
        }
        var seen = Set<String>()
        return recent
            .compactMap { try? JSONDecoder().decode(ProjectFeed.self, from: Data(contentsOf: $0)) }
            .flatMap { $0.actions ?? [] }
            .filter { seen.insert($0.id).inserted }
    }

    /// Whether a mod has reported to Nudge in the last week.
    static var isReporting: Bool {
        let folder = AgentInstaller.support.appending(path: "feeds")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.contains {
            let date = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return Date.now.timeIntervalSince(date) < 7 * 86_400
        }
    }
}
