//
//  DebugLog.swift
//  WS1 App Uploader
//
//  In-memory diagnostic log that surfaces API requests, responses, and
//  upload-pipeline events to a dedicated view.  Designed to be safe to
//  call from any actor — non-main writes hop to MainActor internally
//  so the @Observable mutations are isolated correctly.
//

import Foundation
import Observation

@MainActor
@Observable
final class DebugLog {

    static let shared = DebugLog()

    enum Level: String, Sendable {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
        case api   = "API"
    }

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
    }

    private(set) var entries: [Entry] = []

    /// Append a single entry — public API for view-models that are
    /// already on the main actor.
    func log(_ message: String, level: Level = .info) {
        entries.append(Entry(timestamp: .now, level: level, message: message))
        // Keep memory bounded.
        if entries.count > 2_000 {
            entries.removeFirst(entries.count - 2_000)
        }
    }

    func clear() { entries.removeAll() }

    /// Plain-text export suitable for the clipboard.
    func exportAsText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return entries.map { e in
            "[\(formatter.string(from: e.timestamp))] [\(e.level.rawValue)] \(e.message)"
        }.joined(separator: "\n")
    }
}

extension DebugLog {
    /// Nonisolated entry point — safe to call from any thread / actor.
    /// Mutations hop to the main actor so observation is consistent.
    nonisolated static func write(_ message: String,
                                  level: Level = .info) {
        Task { @MainActor in
            DebugLog.shared.log(message, level: level)
        }
    }
}
