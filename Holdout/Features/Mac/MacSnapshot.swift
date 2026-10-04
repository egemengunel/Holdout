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
    case pressure(MemoryPressure, since: TimeInterval)
    case swapSurge(bytes: UInt64)
    case hog(ProcessUsage, since: TimeInterval)

    /// Identifies an alert across samples, so its start time survives changing numbers.
    var key: String {
        switch self {
        case let .pressure(level, _): "pressure-\(level.rawValue)"
        case .swapSurge: "swap"
        case let .hog(usage, _): "hog-\(usage.name)"
        }
    }

    var isMemory: Bool {
        switch self {
        case .pressure, .swapSurge: true
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
    /// Percent of all cores.
    let cpu: Double
    /// Biggest memory users, largest first.
    let topMemory: [ProcessUsage]
    let alerts: [MacAlert]
}
