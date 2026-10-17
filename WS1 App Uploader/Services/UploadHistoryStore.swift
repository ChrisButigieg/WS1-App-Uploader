//
//  UploadHistoryStore.swift
//  WS1 App Uploader
//

import Foundation
import Observation

/// Persists upload activity to JSON inside Application Support so the
/// dashboard and history views survive relaunches.  Thread-confined to
/// the main actor — history operations are infrequent and small.
@MainActor
@Observable
final class UploadHistoryStore {

    static let shared = UploadHistoryStore()

    private(set) var activities: [UploadActivity] = []

    @ObservationIgnored
    private let fileURL: URL

    init() {
        let baseDir = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let appDir = baseDir.appendingPathComponent("WS1AppUploader", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("upload_history.json")
        load()
    }

    func record(_ activity: UploadActivity) {
        activities.insert(activity, at: 0)
        // Keep last 200 entries to avoid unbounded growth.
        if activities.count > 200 {
            activities = Array(activities.prefix(200))
        }
        persist()
    }

    func clear() {
        activities.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([UploadActivity].self, from: data) {
            activities = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(activities) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
