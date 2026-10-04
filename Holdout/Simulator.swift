//
//  Simulator.swift
//  Holdout
//

import Foundation

/// The bits of `xcrun simctl` the Sim tab uses.
enum Simulator {
    struct Device: Decodable {
        let name: String
        let udid: String
        let state: String
        let lastBootedAt: String?
    }

    /// Dynamic Type sizes, smallest to largest, as `simctl ui content_size` names them.
    static let contentSizes = [
        "extra-small", "small", "medium", "large", "extra-large", "extra-extra-large", "extra-extra-extra-large",
        "accessibility-medium", "accessibility-large", "accessibility-extra-large",
        "accessibility-extra-extra-large", "accessibility-extra-extra-extra-large",
    ]
    static let contentSizeLabels = ["XS", "S", "M", "L", "XL", "XXL", "XXXL", "AX1", "AX2", "AX3", "AX4", "AX5"]

    static let defaultContentSize = contentSizes.firstIndex(of: "large")!

    static func devices() async -> [Device] {
        struct List: Decodable { let devices: [String: [Device]] }
        let result = await Shell.xcrun(["simctl", "list", "devices", "available", "-j"])
        guard result.status == 0,
              let list = try? JSONDecoder().decode(List.self, from: Data(result.output.utf8))
        else { return [] }
        return list.devices.values.flatMap { $0 }
    }

    static func booted() async -> Device? {
        await devices().first { $0.state == "Booted" }
    }

    /// The device to offer booting: the most recently used one, else any iPhone.
    static func lastUsed() async -> Device? {
        let all = await devices()
        return all.filter { $0.lastBootedAt != nil }.max { $0.lastBootedAt! < $1.lastBootedAt! }
            ?? all.first { $0.name.hasPrefix("iPhone") }
    }

    @discardableResult
    static func run(_ arguments: [String]) async -> Bool {
        await Shell.xcrun(["simctl"] + arguments).status == 0
    }

    static func isDark(_ udid: String) async -> Bool {
        await Shell.xcrun(["simctl", "ui", udid, "appearance"]).output.contains("dark")
    }

    static func contentSize(_ udid: String) async -> Int {
        let output = await Shell.xcrun(["simctl", "ui", udid, "content_size"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return contentSizes.firstIndex(of: output) ?? defaultContentSize
    }

    /// Bundle ID of a running, non-Apple app — the one a test push should go to.
    static func runningApp(_ udid: String) async -> String? {
        let output = await Shell.xcrun(["simctl", "spawn", udid, "launchctl", "list"]).output
        return output.split(separator: "\n").lazy
            .compactMap { line -> String? in
                guard let start = line.range(of: "UIKitApplication:")?.upperBound else { return nil }
                return String(line[start...].prefix { $0 != "[" })
            }
            .first { !$0.hasPrefix("com.apple.") }
    }
}
