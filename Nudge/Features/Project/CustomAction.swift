//
//  CustomAction.swift
//  Nudge
//

import Foundation

/// A Project button the user made in Settings: a title, an SF Symbol and a prompt template sent
/// to the current session. Shown for every project, after the built-in or a mod's buttons.
struct CustomAction: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var symbol: String
    /// {project}, {root}, {repo} and {branch} stand for the current project.
    var prompt: String

    /// The id its Touch Bar button carries, so it can't collide with a mod's ids.
    var actionID: String { Self.prefix + id }

    static let prefix = "custom."

    /// Starting points offered in the welcome flow and the button editor.
    static let presets: [CustomAction] = [
        CustomAction(title: "Test", symbol: "checkmark.diamond", prompt: "Run the tests for {project} in {root}. If any fail, find the cause and fix it, then run them again until they pass. Summarize what you changed."),
        CustomAction(title: "Explain", symbol: "text.magnifyingglass", prompt: "Explain the uncommitted changes in {root} on {branch}: what each change does and why it might have been made. Point out anything that looks unfinished."),
        CustomAction(title: "Tidy", symbol: "wand.and.stars", prompt: "In {root}, look at the files changed on {branch} and clean them up: remove leftovers and debug code, tighten names, and match the surrounding style. Don't change behavior."),
        CustomAction(title: "Continue", symbol: "forward", prompt: "Continue where you left off in {project}. If you were waiting on me, pick the option you'd recommend and go."),
        CustomAction(title: "Push", symbol: "arrow.up.circle", prompt: "In {root}, push {branch} to its remote. If it has no upstream yet, set one. Report the result."),
    ]

    /// Symbols the editor offers; any SF Symbol name can still be typed.
    static let symbols = [
        "hammer", "checkmark.circle", "checkmark.diamond", "play", "forward", "arrow.clockwise",
        "ladybug", "wand.and.stars", "sparkles", "text.magnifyingglass", "doc.text", "text.badge.plus",
        "arrow.up.circle", "arrow.down.circle", "arrow.triangle.branch", "arrow.triangle.pull", "shippingbox", "paperplane",
        "testtube.2", "gauge.with.dots.needle.67percent", "lock.shield", "trash", "scissors", "paintbrush",
        "globe", "iphone", "macbook", "server.rack", "terminal", "bolt",
        "star", "flag", "bookmark", "lightbulb", "questionmark.bubble", "bubble.left.and.text.bubble.right",
    ]

    /// Replaces the placeholders; nil when there's no project to name.
    static func fill(_ template: String, project: ProjectFeed.Project?, repo: ProjectFeed.Repo?) -> String? {
        guard let name = project?.name ?? repo?.name else { return nil }
        return template
            .replacingOccurrences(of: "{project}", with: name)
            .replacingOccurrences(of: "{root}", with: project?.root ?? repo?.root ?? name)
            .replacingOccurrences(of: "{repo}", with: repo?.name ?? name)
            .replacingOccurrences(of: "{branch}", with: project?.branch ?? repo?.branch ?? "the current branch")
    }
}
