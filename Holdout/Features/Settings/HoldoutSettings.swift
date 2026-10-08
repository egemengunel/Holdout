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
