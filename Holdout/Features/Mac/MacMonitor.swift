//
//  MacMonitor.swift
//  Holdout
//

import Foundation

/// Samples the Mac every few seconds and raises alerts only for sustained trouble.
/// Every threshold is generic, so it behaves the same on any Mac; nothing is tuned
/// to one machine's usual swap or to particular processes.
final class MacMonitor {
    private static let interval: TimeInterval = 5
    /// Warning pressure must last this long; macOS hits it briefly all the time on 8 GB.
    private static let warningSustain: TimeInterval = 120
    private static let criticalSustain: TimeInterval = 30
    private static let swapWindow: TimeInterval = 5 * 60
    private static let swapSurge: UInt64 = 1536 * 1024 * 1024
    /// Percent of one core, held for `hogSustain`.
    private static let hogCPU: Double = 80
    private static let hogSustain: TimeInterval = 3 * 60

    var onChange: (() -> Void)?
    private(set) var snapshot: MacSnapshot?
    /// When the newest active alert started; nil while all is well.
    private(set) var newestAlert: TimeInterval?

    private var timer: Timer?
    private var names: [pid_t: String] = [:]
    private var lastCPU: [pid_t: UInt64] = [:]
    private var lastSampleAt: TimeInterval?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var swapHistory: [(at: TimeInterval, used: UInt64)] = []
    private var elevatedSince: TimeInterval?
    private var hotSince: [String: TimeInterval] = [:]
    private var alertStarts: [String: TimeInterval] = [:]

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    private func sample() {
        let now = Date.now.timeIntervalSince1970
        let pressure = SystemSampler.pressure()
        let swap = SystemSampler.swapUsed()
        let ticks = SystemSampler.cpuTicks()
        let usages = processUsages(now: now)

        let cpu = lastTicks.map { last in
            let total = ticks.total &- last.total
            return total > 0 ? Double(ticks.busy &- last.busy) / Double(total) * 100 : 0
        } ?? 0
        lastTicks = ticks

        swapHistory.append((now, swap))
        swapHistory.removeAll { now - $0.at > Self.swapWindow * 2 }
        let windowStart = swapHistory.last { now - $0.at >= Self.swapWindow } ?? swapHistory[0]
        let swapGrowth = Int64(swap) - Int64(windowStart.used)

        elevatedSince = pressure == .normal ? nil : (elevatedSince ?? now)
        for usage in usages {
            if usage.cpu >= Self.hogCPU {
                hotSince[usage.name] = hotSince[usage.name] ?? now
            } else {
                hotSince[usage.name] = nil
            }
        }
        hotSince = hotSince.filter { name, _ in usages.contains { $0.name == name } }

        var alerts: [MacAlert] = []
        if let since = elevatedSince {
            let sustain = pressure == .critical ? Self.criticalSustain : Self.warningSustain
            if now - since >= sustain {
                alerts.append(.pressure(pressure, since: since))
            }
        }
        if swapGrowth > 0, UInt64(swapGrowth) >= Self.swapSurge {
            alerts.append(.swapSurge(bytes: UInt64(swapGrowth)))
        }
        for usage in usages.sorted(by: { $0.cpu > $1.cpu }) {
            if let since = hotSince[usage.name], now - since >= Self.hogSustain {
                alerts.append(.hog(usage, since: since))
            }
        }

        // An alert keeps the time it first appeared, so a new one can be told from an old one.
        alertStarts = alerts.reduce(into: [:]) { starts, alert in
            starts[alert.key] = alertStarts[alert.key] ?? now
        }
        newestAlert = alertStarts.values.max()

        snapshot = MacSnapshot(
            pressure: pressure,
            memoryUsed: SystemSampler.memoryUsed(),
            memoryTotal: ProcessInfo.processInfo.physicalMemory,
            swapUsed: swap,
            swapGrowth: swapGrowth,
            cpu: cpu,
            topMemory: Array(usages.sorted { $0.footprint > $1.footprint }.prefix(3)),
            alerts: alerts
        )
        onChange?()
    }

    /// Per-name totals, with CPU as the share of one core since the last sample.
    private func processUsages(now: TimeInterval) -> [ProcessUsage] {
        let readings = SystemSampler.processes(names: &names)
        let elapsed = lastSampleAt.map { now - $0 } ?? 0
        lastSampleAt = now
        defer { lastCPU = readings.mapValues(\.cpuNanoseconds) }

        var totals: [String: (footprint: UInt64, cpu: Double, pids: [pid_t])] = [:]
        for (pid, reading) in readings {
            let cpu = elapsed > 0 ? lastCPU[pid].map { Double(reading.cpuNanoseconds &- $0) / (elapsed * 1e9) * 100 } ?? 0 : 0
            var total = totals[reading.name] ?? (0, 0, [])
            total.footprint += reading.footprint
            total.cpu += cpu
            total.pids.append(pid)
            totals[reading.name] = total
        }
        return totals.map { ProcessUsage(name: $0.key, footprint: $0.value.footprint, cpu: $0.value.cpu, pids: $0.value.pids) }
    }
}
