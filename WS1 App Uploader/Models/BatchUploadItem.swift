//
//  BatchUploadItem.swift
//  WS1 App Uploader
//
//  One file in a batch upload queue.  Each item carries the picked
//  file, metadata extracted from it, a detection result against the
//  tenant (new vs. update), per-item settings, and its live status.
//

import Foundation
import Observation

@Observable
final class BatchUploadItem: Identifiable, Hashable {

    let id: UUID = UUID()

    /// Local sandboxed copy of the source file.
    let fileURL: URL
    /// The filename as the user picked it — without the sandbox UUID
    /// prefix.  Used for display so the operator sees `calculator.ipa`
    /// instead of `<uuid>-calculator.ipa`.
    let originalFilename: String
    let fileSizeBytes: Int64
    var metadata: AppPackageMetadata

    var detection: DetectionState = .undetermined
    var settings: ItemSettings    = .init()
    var status:   RunStatus       = .pending
    var statusMessage: String     = ""
    var progress: Double          = 0
    var createdWS1Id: Int?

    /// Optional staged copy of a PNG / JPG icon the operator chose
    /// for this item.  Uploaded ahead of the binary on save; the
    /// resulting blob UUID is sent as `IconBlobUuid` on
    /// `/begininstall`.  Nil = let WS1 derive an icon from the IPA.
    var iconFileURL: URL?
    var iconFilename: String?

    init(fileURL: URL,
         originalFilename: String,
         fileSizeBytes: Int64,
         metadata: AppPackageMetadata) {
        self.fileURL          = fileURL
        self.originalFilename = originalFilename
        self.fileSizeBytes    = fileSizeBytes
        self.metadata         = metadata
    }

    // MARK: - Display

    /// What we show in the row header — the original filename.
    var displayFilename: String { originalFilename }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    // MARK: - Hashable / Equatable (by identity)

    static func == (lhs: BatchUploadItem, rhs: BatchUploadItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher)                                { hasher.combine(id) }

    // MARK: - Sub-types

    enum DetectionState: Equatable {
        case undetermined
        case detecting
        case newApp
        case updatesExisting([WS1Application])
        case error(String)

        var summary: String {
            switch self {
            case .undetermined:            return "Pending detection"
            case .detecting:               return "Checking tenant…"
            case .newApp:                  return "New application"
            case .updatesExisting(let xs):
                let count = xs.count
                if count == 1, let app = xs.first {
                    return "Updates \(app.applicationName) \(app.appVersion)"
                }
                return "Updates \(count) existing version(s)"
            case .error(let m):            return "Detection error: \(m)"
            }
        }

        var existingApps: [WS1Application] {
            if case .updatesExisting(let apps) = self { return apps }
            return []
        }
    }

    enum RunStatus: Equatable {
        case pending
        case running
        case succeeded
        case failed
        case skipped

        var displayName: String {
            switch self {
            case .pending:   return "Queued"
            case .running:   return "Uploading"
            case .succeeded: return "Done"
            case .failed:    return "Failed"
            case .skipped:   return "Skipped"
            }
        }

        var kind: StatusKind {
            switch self {
            case .pending:   return .neutral
            case .running:   return .warning
            case .succeeded: return .success
            case .failed:    return .failure
            case .skipped:   return .neutral
            }
        }
    }

    /// Per-item settings — sane defaults for the common workflow.
    struct ItemSettings: Hashable {
        /// Retire any matching prior versions automatically.
        var retirePreviousVersion: Bool       = true
        /// Apply the management defaults — only meaningful for new
        /// applications.  Ignored when the item is detected as an
        /// update (existing app's settings are preserved).
        var preventBackup: Bool               = true
        var removeOnMDMRemoval: Bool          = true
        var makeManagedIfUserInstalled: Bool  = true
        /// Brief description copied into the WS1 app record.  Empty
        /// means "no change" on updates, "blank" on creates.
        var description: String               = ""

        var management: CreateApplicationPayload.ManagementSettings {
            CreateApplicationPayload.ManagementSettings(
                preventBackup:                  preventBackup,
                removeOnUnenroll:               removeOnMDMRemoval,
                takeManagementOfUserInstalled:  makeManagedIfUserInstalled
            )
        }
    }
}
