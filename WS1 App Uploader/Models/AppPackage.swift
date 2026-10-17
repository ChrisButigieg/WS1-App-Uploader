//
//  AppPackage.swift
//  WS1 App Uploader
//

import Foundation

/// Metadata extracted (and optionally edited) for an app about to be
/// uploaded.  All fields default to empty so the form can pre-fill any
/// subset it manages to parse.
struct AppPackageMetadata: Equatable, Sendable {
    var applicationName: String = ""
    var bundleIdentifier: String = ""
    var versionShort: String    = ""    // CFBundleShortVersionString
    var versionBuild: String    = ""    // CFBundleVersion
    var minimumOSVersion: String = ""
    var platform: PlatformType  = .unknown

    /// True when we managed to determine *something* useful.
    var hasAnyMetadata: Bool {
        !applicationName.isEmpty
        || !bundleIdentifier.isEmpty
        || !versionShort.isEmpty
        || !versionBuild.isEmpty
    }

    /// User-facing combined version string ("1.4.2 (224)").
    var combinedVersion: String {
        switch (versionShort.isEmpty, versionBuild.isEmpty) {
        case (false, false): return "\(versionShort) (\(versionBuild))"
        case (false, true):  return versionShort
        case (true,  false): return versionBuild
        case (true,  true):  return ""
        }
    }

    /// Returns a copy with the version bumped — used as a smart default
    /// when "this is an upgrade" is checked.
    func bumpingPatchVersion() -> AppPackageMetadata {
        var copy = self
        let parts = versionShort.split(separator: ".").map(String.init)
        guard let last = parts.last, var n = Int(last) else { return copy }
        n += 1
        copy.versionShort = (parts.dropLast() + ["\(n)"]).joined(separator: ".")
        return copy
    }
}

/// A file that the user has selected for upload.  Combines the picked
/// URL with any metadata we've managed to extract from it.
struct PendingUpload: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    /// Original filename before the sandbox-staging copy renamed it
    /// with a UUID prefix.  Used for display and as the `FileName`
    /// value sent to `/begininstall`.
    let originalFilename: String
    let fileSizeBytes: Int64
    var metadata: AppPackageMetadata
    /// Optional separately-selected Info.plist (macOS use case).
    var infoPlistURL: URL?

    var displayFilename: String { originalFilename }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}
