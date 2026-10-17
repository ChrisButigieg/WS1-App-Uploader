//
//  UploadActivity.swift
//  WS1 App Uploader
//

import Foundation

/// An entry in the upload history / activity log.  Persisted to
/// `Application Support/upload_history.json`.
struct UploadActivity: Identifiable, Codable, Hashable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case succeeded
        case failed
        case cancelled
    }

    let id: UUID
    let timestamp: Date
    let applicationName: String
    let version: String
    let bundleIdentifier: String
    let platformRaw: String
    let outcome: Outcome
    let message: String
    /// Versions that were retired as part of this upload, if any.
    let retiredVersionIDs: [Int]

    var platform: PlatformType {
        PlatformType(rawValue: platformRaw) ?? .unknown
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        applicationName: String,
        version: String,
        bundleIdentifier: String,
        platform: PlatformType,
        outcome: Outcome,
        message: String,
        retiredVersionIDs: [Int] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.applicationName = applicationName
        self.version = version
        self.bundleIdentifier = bundleIdentifier
        self.platformRaw = platform.rawValue
        self.outcome = outcome
        self.message = message
        self.retiredVersionIDs = retiredVersionIDs
    }
}

/// Streaming progress reported by the upload service.
struct UploadProgress: Sendable {
    enum Phase: String, Sendable {
        case idle           = "Idle"
        case authenticating = "Authenticating"
        case uploadingBlob  = "Uploading blob"
        case creatingApp    = "Creating application"
        case retiring       = "Retiring previous version"
        case finishing      = "Finalizing"
        case done           = "Done"
        case failed         = "Failed"
    }

    var phase: Phase = .idle
    /// 0.0 ... 1.0 for the current phase.
    var fraction: Double = 0
    var message: String = ""
}
