//
//  MacSnapshot.swift
//  Holdout
//

import Foundation

/// The kernel's memory-pressure level (`kern.memorystatus_vm_pressure_level`).
enum MemoryPressure: Int32 {
    case normal = 1
    case warning = 2
    case critical = 4
}

/// One process name's usage; helpers sharing a name (browser renderers) are summed.
struct ProcessUsage: Equatable {
    let name: String
    let footprint: UInt64
    /// Percent of one core, like Activity Monitor's CPU column.
    let cpu: Double
    let pids: [pid_t]
}

enum MacAlert: Equatable {
    enum Severity {
        /// Real slowdown: flashes red until you look.
        case distress
        /// Worth a glance: one soft orange flash, at most every half hour per kind.
        case headsUp
    }

    case pressure(MemoryPressure, since: TimeInterval)
    case hog(ProcessUsage, since: TimeInterval)

    var severity: Severity {
        switch self {
        case .pressure: .distress
        case .hog: .headsUp
        }
    }

    var symbol: String {
        switch self {
        case .pressure: "memorychip"
        case .hog: "cpu"
        }
    }

    /// Identifies an alert across samples, so its start time survives changing numbers.
    var key: String {
        switch self {
        case let .pressure(level, _): "pressure-\(level.rawValue)"
        case let .hog(usage, _): "hog-\(usage.name)"
        }
    }

    var isMemory: Bool {
        switch self {
        case .pressure: true
        case .hog: false
        }
    }
}

struct MacSnapshot {
    let pressure: MemoryPressure
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let swapUsed: UInt64
    /// Swap growth over the last few minutes; negative when it shrank.
    let swapGrowth: Int64
    /// Swap read back per second over the last minute.
    let swapInRate: UInt64
    /// Percent of all cores.
    let cpu: Double
    /// Biggest memory users, largest first.
    let topMemory: [ProcessUsage]
    let alerts: [MacAlert]
}
