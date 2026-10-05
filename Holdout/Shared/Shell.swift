//
//  Shell.swift
//  Holdout
//

import Foundation

enum Shell {
    nonisolated static func xcrun(_ arguments: [String]) async -> (status: Int32, output: String) {
        await run("/usr/bin/xcrun", arguments)
    }

    nonisolated static func git(_ arguments: [String], in directory: String) async -> (status: Int32, output: String) {
        await run("/usr/bin/git", ["-C", directory] + arguments, mergingErrors: false)
    }

    nonisolated static func run(_ executable: String, _ arguments: [String], mergingErrors: Bool = true) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = mergingErrors ? pipe : FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
                return
            }
            // Read while it runs: output larger than the pipe's buffer would block it from exiting.
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
