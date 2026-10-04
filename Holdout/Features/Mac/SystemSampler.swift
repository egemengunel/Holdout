//
//  SystemSampler.swift
//  Holdout
//

import AppKit
import Darwin

/// Raw readings from the kernel: the same sources Activity Monitor uses.
enum SystemSampler {
    struct ProcessReading {
        let name: String
        let footprint: UInt64
        /// User plus system CPU time so far, in nanoseconds.
        let cpuNanoseconds: UInt64
    }

    private static let host = mach_host_self()

    /// `ri_user_time` and friends are in Mach ticks, which aren't nanoseconds on Apple silicon.
    private static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return MemoryPressure(rawValue: level) ?? .normal
    }

    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        return usage.xsu_used
    }

    /// Activity Monitor's "Memory Used": app memory, wired, and compressed.
    static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        return (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * UInt64(vm_kernel_page_size)
    }

    /// Cumulative CPU ticks across all cores: busy and total.
    static func cpuTicks() -> (busy: UInt64, total: UInt64) {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let ticks = load.cpu_ticks
        let user = UInt64(ticks.0), system = UInt64(ticks.1), idle = UInt64(ticks.2), nice = UInt64(ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Every process this user can read. Others' (root daemons) are skipped by the kernel.
    static func processes(names: inout [pid_t: String]) -> [pid_t: ProcessReading] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))

        var readings: [pid_t: ProcessReading] = [:]
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }

            let name = names[pid] ?? processName(pid)
            names[pid] = name
            readings[pid] = ProcessReading(
                name: name,
                footprint: info.ri_phys_footprint,
                cpuNanoseconds: UInt64(Double(info.ri_user_time + info.ri_system_time) * nanosecondsPerTick)
            )
        }
        names = names.filter { readings[$0.key] != nil }
        return readings
    }

    /// An app's display name when it is one, else the executable name.
    private static func processName(_ pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 64)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }
}
