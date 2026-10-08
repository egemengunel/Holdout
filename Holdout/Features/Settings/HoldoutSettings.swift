//
//  HoldoutSettings.swift
//  Holdout
//

import Foundation
import ServiceManagement

/// User preferences, in UserDefaults so SwiftUI's `@AppStorage` and the Touch Bar code share them.
enum HoldoutSettings {
    enum Key {
        static let macDistress = "alerts.macDistress"
        static let cpuHeadsUp = "alerts.cpuHeadsUp"
        static let sessionDone = "flash.sessionDone"
        static let buildResult = "flash.buildResult"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.macDistress: true,
            Key.cpuHeadsUp: true,
            Key.sessionDone: true,
            Key.buildResult: true,
        ])
    }

    /// How the Project tab's buttons hand their prompt to an agent.
    enum Delivery: String, CaseIterable, Identifiable {
        /// Into the chat the way that agent allows (see `AgentInstaller.Agent.projectButtons`).
        case automatic
        /// Always copy it and open the agent, never type or queue it.
        case clipboard

        var id: String { rawValue }
    }

    static func deliveryKey(_ agent: String) -> String { "agent.\(agent).delivery" }
    static func hiddenKey(_ agent: String) -> String { "agent.\(agent).hidden" }
    static func promptKey(_ action: String) -> String { "prompt.\(action)" }

    static func delivery(for agent: String) -> Delivery {
        UserDefaults.standard.string(forKey: deliveryKey(agent)).flatMap(Delivery.init) ?? .automatic
    }

    static func isHidden(_ agent: String) -> Bool {
        UserDefaults.standard.bool(forKey: hiddenKey(agent))
    }

    /// The user's own wording for a Project button's prompt, if they set one.
    static func promptOverride(for action: String) -> String? {
        let text = UserDefaults.standard.string(forKey: promptKey(action))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// Open at Login lives in the system's login items, not in UserDefaults.
    static var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Holdout: login item change failed: %@", error.localizedDescription)
            }
        }
    }
}
