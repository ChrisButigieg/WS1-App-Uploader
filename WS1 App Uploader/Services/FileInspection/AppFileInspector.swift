//
//  AppFileInspector.swift
//  WS1 App Uploader
//
//  Detects platform from a selected file and orchestrates the more
//  specialized inspectors (IPA, Info.plist, etc.).
//

import Foundation
import UniformTypeIdentifiers

struct AppFileInspector {

    /// Detects the platform for a given file URL.  When the result is
    /// ambiguous (.zip can be macOS or Windows), the disambiguator
    /// inspects the archive's top-level entries.
    static func detectPlatform(for url: URL) -> PlatformType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "ipa":                                  return .iOS
        case "app", "pkg", "dmg":                    return .macOS
        case "apk", "aab":                           return .android
        case "msi", "exe", "appx", "appxbundle":     return .windows
        case "zip":                                  return disambiguateZip(url)
        default:                                     return .unknown
        }
    }

    /// Attempt to parse metadata for the file.  Best-effort — the
    /// returned struct may be empty if nothing useful was found.
    ///
    /// `originalFilename` is the filename as it appeared before any
    /// sandbox-staging copy renamed it (e.g. without our `<uuid>-`
    /// prefix).  Used as the human-friendly fallback for the app name
    /// when no `CFBundleName` can be extracted.
    static func parseMetadata(for url: URL,
                              originalFilename: String? = nil) -> AppPackageMetadata {
        var metadata = AppPackageMetadata()
        metadata.platform = detectPlatform(for: url)

        switch metadata.platform {
        case .iOS:
            if let parsed = IPAInspector.metadata(for: url) {
                metadata.applicationName  = parsed.applicationName
                metadata.bundleIdentifier = parsed.bundleIdentifier
                metadata.versionShort     = parsed.versionShort
                metadata.versionBuild     = parsed.versionBuild
                metadata.minimumOSVersion = parsed.minimumOSVersion
            }
        case .macOS:
            if let parsed = InfoPlistExtractor.metadataFromMacOSPackage(at: url) {
                metadata.applicationName  = parsed.applicationName
                metadata.bundleIdentifier = parsed.bundleIdentifier
                metadata.versionShort     = parsed.versionShort
                metadata.versionBuild     = parsed.versionBuild
                metadata.minimumOSVersion = parsed.minimumOSVersion
            }
        case .android, .windows, .unknown:
            // No automatic inspector — fall through to the filename
            // fallback below.
            break
        }

        if metadata.applicationName.isEmpty {
            let baseName: String
            if let originalFilename, !originalFilename.isEmpty {
                baseName = (originalFilename as NSString).deletingPathExtension
            } else {
                baseName = url.deletingPathExtension().lastPathComponent
            }
            metadata.applicationName = baseName
        }
        return metadata
    }

    private static func disambiguateZip(_ url: URL) -> PlatformType {
        // Peek at the archive header — a quick heuristic.  If the
        // archive contains a top-level `.app/`, treat as macOS; if it
        // contains `.exe`/`.msi`, treat as Windows; otherwise leave
        // unknown so the user can override.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 8192) else { return .unknown }
        let text = String(data: chunk, encoding: .ascii) ?? ""
        if text.contains(".app/")                 { return .macOS }
        if text.contains(".exe") || text.contains(".msi") { return .windows }
        return .unknown
    }
}
