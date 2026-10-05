//
//  DesignLint.swift
//  Holdout
//

import Foundation

/// swift-design-lint's rules, applied to what agents other than Claude Code (which runs
/// the mod itself) changed: the uncommitted added lines of the Swift files they edited.
enum DesignLint {
    /// The mod's rules; after `export default` it is plain JSON so Holdout can read it too.
    nonisolated static let rulesFile = URL.homeDirectory.appending(path: ".claude/mods/swift-design-lint/hooks/rules.ts")

    private nonisolated struct RuleSource: Decodable {
        let pattern: String
        let onlyIn: String?
        let skipIn: String?
    }

    private nonisolated struct ProjectSource: Decodable {
        let path: String
        let rules: [RuleSource]
    }

    private nonisolated struct Rules: Decodable {
        let common: [RuleSource]
        let projects: [ProjectSource]
    }

    /// How many rule violations the added lines of `files` (absolute, or relative to `cwd`) hold.
    nonisolated static func issues(in files: [String], cwd: String, root: String) async -> Int {
        guard let rules = loadRules() else { return 0 }
        var count = 0
        for file in Set(files) where file.hasSuffix(".swift") {
            let path = file.hasPrefix("/") ? file : URL(fileURLWithPath: cwd).appending(path: file).standardizedFileURL.path
            guard let project = rules.projects.first(where: { matches($0.path, path) }) else { continue }
            let applicable = (rules.common + project.rules).filter { rule in
                (rule.onlyIn.map { matches($0, path) } ?? true) && !(rule.skipIn.map { matches($0, path) } ?? false)
            }
            for line in await addedLines(path, root: root) {
                count += applicable.filter { matches($0.pattern, line) }.count
            }
        }
        return count
    }

    private nonisolated static func loadRules() -> Rules? {
        guard let text = try? String(contentsOf: rulesFile, encoding: .utf8),
              let start = text.range(of: "export default", options: .backwards)?.upperBound
        else { return nil }
        return try? JSONDecoder().decode(Rules.self, from: Data(text[start...].utf8))
    }

    /// Lines added since the last commit, or the whole file when git doesn't track it yet.
    private nonisolated static func addedLines(_ path: String, root: String) async -> [String] {
        let diff = await Shell.git(["diff", "-U0", "HEAD", "--", path], in: root)
        var lines = diff.output.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
            .map { String($0.dropFirst()) }
        if diff.output.isEmpty {
            let untracked = await Shell.git(["ls-files", "--others", "--exclude-standard", "--", path], in: root)
            if !untracked.output.isEmpty, let text = try? String(contentsOfFile: path, encoding: .utf8) {
                lines = text.components(separatedBy: "\n")
            }
        }
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("//")
        }
    }

    private nonisolated static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
