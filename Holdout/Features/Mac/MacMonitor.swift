//
//  MacMonitor.swift
//  Holdout
//

import Foundation

/// Samples the Mac every few seconds and raises alerts only for trouble you'd feel.
/// Swap size and growth are shown but never alert: low-RAM Macs run fine with 10+ GB of swap.
/// Every threshold is generic, so it behaves the same on any Mac; nothing is tuned
/// to one machine's usual swap or to particular processes.
final class MacMonitor {
    private static let interval: TimeInterval = 5
    /// "Warning" pressure alone isn't an alert: low-RAM Macs sit there for hours running
    /// fine. Critical has to hold this long.
    private static let criticalSustain: TimeInterval = 60
    /// Swap-in averaged over a minute. A Mac that feels fine reads back well under 1 MB/s.
    private static let thrashRate: UInt64 = 20 * 1024 * 1024
    private static let thrashWindow: TimeInterval = 60
    /// A heads-up of the same kind flashes at most this often.
    private static let headsUpCooldown: TimeInterval = 30 * 60
    private static let swapWindow: TimeInterval = 5 * 60
    /// Percent of one core, held for `hogSustain`.
    private static let hogCPU: Double = 80
    private static let hogSustain: TimeInterval = 3 * 60

    var onChange: (() -> Void)?
    private(set) var snapshot: MacSnapshot?
    /// When the newest active distress alert started; nil while all is well.
    private(set) var newestDistress: TimeInterval?
    /// The latest heads-up to flash: when, and its symbol.
    private(set) var headsUp: (at: TimeInterval, symbol: String)?

    private var timer: Timer?
    private var names: [pid_t: String] = [:]
    private var lastCPU: [pid_t: UInt64] = [:]
    private var lastSampleAt: TimeInterval?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var swapHistory: [(at: TimeInterval, used: UInt64)] = []
    private var elevatedSince: TimeInterval?
    private var hotSince: [String: TimeInterval] = [:]
    private var alertStarts: [String: TimeInterval] = [:]
    private var swapInHistory: [(at: TimeInterval, total: UInt64)] = []
    private var lastAnnounced: [String: TimeInterval] = [:]

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
        swapInHistory.append((now, SystemSampler.swappedIn()))
        swapInHistory.removeAll { now - $0.at > Self.thrashWindow * 2 }
        let thrashStart = swapInHistory.last { now - $0.at >= Self.thrashWindow }
        let swapInRate = thrashStart.map { start in
            UInt64(Double(swapInHistory[swapInHistory.count - 1].total &- start.total) / (now - start.at))
        } ?? 0
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
        if swapInRate >= Self.thrashRate {
            alerts.append(.thrashing(bytesPerSecond: swapInRate))
        }
        if pressure == .critical, let since = elevatedSince, now - since >= Self.criticalSustain {
            alerts.append(.pressure(pressure, since: since))
        }
        for usage in usages.sorted(by: { $0.cpu > $1.cpu }) {
            if let since = hotSince[usage.name], now - since >= Self.hogSustain {
                alerts.append(.hog(usage, since: since))
            }
        }

        // An alert keeps the time it first appeared, so a new one can be told from an old one.
        let started = alerts.filter { alertStarts[$0.key] == nil }
        alertStarts = alerts.reduce(into: [:]) { starts, alert in
            starts[alert.key] = alertStarts[alert.key] ?? now
        }
        newestDistress = alerts.filter { $0.severity == .distress }.compactMap { alertStarts[$0.key] }.max()
        for alert in started where alert.severity == .headsUp && now - (lastAnnounced[alert.key] ?? 0) >= Self.headsUpCooldown {
            lastAnnounced[alert.key] = now
            headsUp = (now, alert.symbol)
        }

        snapshot = MacSnapshot(
            pressure: pressure,
            memoryUsed: SystemSampler.memoryUsed(),
            memoryTotal: ProcessInfo.processInfo.physicalMemory,
            swapUsed: swap,
            swapGrowth: swapGrowth,
            swapInRate: swapInRate,
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
