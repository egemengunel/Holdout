//
//  SessionStore.swift
//  Holdout
//

import Foundation

/// Watches the hook's output folder and keeps the current sessions in memory.
final class SessionStore {
    static let directory = URL.applicationSupportDirectory.appending(path: "Holdout/sessions", directoryHint: .isDirectory)

    /// How long a finished session stays on the Touch Bar.
    private static let doneLinger: TimeInterval = 60
    /// A "working" session with no event for this long was probably killed without a SessionEnd.
    private static let staleAfter: TimeInterval = 30 * 60
    private static let deleteAfter: TimeInterval = 24 * 60 * 60

    var onChange: (() -> Void)?
    private(set) var sessions: [AgentSession] = []
    private var watcher: DispatchSourceFileSystemObject?

    func start() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        // The hook writes via rename, which always touches the directory itself.
        let descriptor = open(Self.directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source

        reload()
    }

    func reload() {
        let now = Date.now.timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []

        sessions = files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(AgentSession.self, from: data)
            else { return nil }

            if now - session.updatedAt > Self.deleteAfter {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return session
        }
        onChange?()
    }

    /// Sessions worth showing: waiting on you, working, or finished within the last minute.
    /// Waiting sessions come first, then oldest turn first.
    func visible(at now: Date = .now) -> [AgentSession] {
        let now = now.timeIntervalSince1970
        return sessions
            .filter { !HoldoutSettings.isHidden($0.agent ?? "claude") }
            .filter { session in
                switch session.state {
                case .waiting: true
                case .thinking, .tool: now - session.updatedAt < Self.staleAfter
                case .done: now - session.updatedAt < Self.doneLinger
                case .idle: false
                }
            }
            .sorted { lhs, rhs in
                (lhs.state == .waiting ? 0 : 1, lhs.turnStartedAt) < (rhs.state == .waiting ? 0 : 1, rhs.turnStartedAt)
            }
    }
}
