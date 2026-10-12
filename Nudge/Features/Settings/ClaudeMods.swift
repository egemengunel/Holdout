//
//  ClaudeMods.swift
//  Nudge
//

import Foundation

/// The Claude Code mods on this Mac and the slash commands they add, which can become Touch Bar
/// buttons. Any mod works: a command is run as if typed, so Nudge needn't know what it does.
///
/// Mods are found where Claude Code loads them from (`~/.claude/mods` and the folders in
/// `CLAUDE_CODE_PLUGIN_DIRS`). Their commands come from the nudge-bridge mod, which asks Claude
/// Code for the live list (`mods.json`), or before any session has run, from the `name` and
/// `description` each mod passes to `$.command.register` in its source.
enum ClaudeMods {
    struct Mod: Identifiable, Hashable {
        let name: String
        let path: String
        let summary: String?
        var id: String { path }
    }

    struct Command: Identifiable, Hashable {
        let mod: String
        let name: String
        let description: String
        var id: String { mod + "/" + name }
    }

    static var installed: [Mod] {
        var seen = Set<String>()
        return folders.compactMap { url -> Mod? in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted,
                  FileManager.default.fileExists(atPath: path + "/hooks/hooks.json"),
                  !path.hasSuffix("/nudge-bridge")
            else { return nil }
            let manifest = (try? Data(contentsOf: url.appending(path: ".claude-plugin/plugin.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return Mod(name: manifest?["name"] as? String ?? url.lastPathComponent, path: path, summary: manifest?["description"] as? String)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every installed mod's commands: the bridge's live list where it has one, else read from source.
    static var commands: [Command] {
        let live = liveCommands
        return installed.flatMap { mod in
            live[mod.name] ?? declaredCommands(in: URL(fileURLWithPath: mod.path), mod: mod.name)
        }
    }

    /// The prompt a mod command's button sends: the command, as typed.
    static func prompt(for command: Command) -> String { "/" + command.name }

    // MARK: Where mods live

    private static var folders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modsFolder = home.appending(path: ".claude/mods")
        let inMods = ((try? FileManager.default.contentsOfDirectory(atPath: modsFolder.path)) ?? []).sorted()
            .map { modsFolder.appending(path: $0) }
        let settings = (try? Data(contentsOf: home.appending(path: ".claude/settings.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let listed = [(settings?["env"] as? [String: Any])?["CLAUDE_CODE_PLUGIN_DIRS"] as? String,
                      ProcessInfo.processInfo.environment["CLAUDE_CODE_PLUGIN_DIRS"]]
            .compactMap { $0 }
            .flatMap { $0.split(separator: ":").map(String.init) }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return inMods + listed
    }

    // MARK: Commands

    /// What the bridge last reported, by mod name: `mods.json` holds `{ "<mod>": [{ name, description }] }`.
    private static var liveCommands: [String: [Command]] {
        guard let data = try? Data(contentsOf: AgentInstaller.support.appending(path: "mods.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]]
        else { return [:] }
        return object.reduce(into: [:]) { result, item in
            result[item.key] = item.value.compactMap { entry in
                entry["name"].map { Command(mod: item.key, name: $0, description: entry["description"] ?? "") }
            }
        }
    }

    /// `$.command.register({ name: 'ship', description: '…' })` calls in a mod's source.
    private static func declaredCommands(in folder: URL, mod: String) -> [Command] {
        let hooks = folder.appending(path: "hooks")
        let files = (try? FileManager.default.contentsOfDirectory(at: hooks, includingPropertiesForKeys: nil)) ?? []
        var seen = Set<String>()
        return files
            .filter { ["ts", "tsx", "js", "mjs", "jsx"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { source in
                source.matches(of: #/command\.register\(\s*\{([^}]*)\}/#).compactMap { call -> Command? in
                    let body = String(call.1)
                    guard let name = body.firstMatch(of: #/name\s*:\s*['"`]([^'"`]+)['"`]/#)?.1 else { return nil }
                    let description = body.firstMatch(of: #/description\s*:\s*['"`]([^'"`]*)['"`]/#)?.1
                    return Command(mod: mod, name: String(name), description: description.map(String.init) ?? "")
                }
            }
            .filter { seen.insert($0.name).inserted }
    }

    // MARK: Reporting

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
