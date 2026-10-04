//
//  Shell.swift
//  Holdout
//

import Foundation

enum Shell {
    nonisolated static func xcrun(_ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }
}
