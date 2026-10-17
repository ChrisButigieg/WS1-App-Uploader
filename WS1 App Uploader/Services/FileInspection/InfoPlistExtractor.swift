//
//  InfoPlistExtractor.swift
//  WS1 App Uploader
//
//  Parses Info.plist content into `AppPackageMetadata`.  Provides
//  helpers to locate the plist inside a .app bundle on macOS, and a
//  generic decoder usable on any platform once you have the URL.
//

import Foundation

struct InfoPlistExtractor {

    /// Parse a plist file directly.  Logs the precise reason for any
    /// failure to the Debug Log so operators can see why a particular
    /// plist file couldn't be used.
    static func metadata(fromPlistAt url: URL) -> AppPackageMetadata? {
        let path = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            DebugLog.write("Plist read failed for \(path): \(error.localizedDescription)", level: .error)
            return nil
        }
        if data.isEmpty {
            DebugLog.write("Plist \(path) is empty (0 bytes)", level: .error)
            return nil
        }
        DebugLog.write("Plist read \(path) — \(data.count) bytes", level: .info)
        return decode(data: data, sourceName: path)
    }

    /// On macOS, given an `.app` bundle (a directory), read its
    /// Info.plist.  On iOS this returns nil — sandbox restrictions
    /// prevent reading arbitrary bundle contents.
    static func metadataFromMacOSPackage(at url: URL) -> AppPackageMetadata? {
        #if os(macOS)
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "app":
            let plist = url.appendingPathComponent("Contents/Info.plist")
            return metadata(fromPlistAt: plist)
        case "pkg", "dmg":
            // We don't auto-mount/extract pkg/dmg files — the user can
            // separately point us at the Info.plist via "Use Info.plist".
            return nil
        default:
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Decoding

    static func decode(data: Data, sourceName: String = "(unnamed plist)") -> AppPackageMetadata? {
        let raw: Any
        do {
            raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            DebugLog.write("Plist parse failed for \(sourceName): \(error.localizedDescription)", level: .error)
            return nil
        }
        guard let dict = raw as? [String: Any] else {
            DebugLog.write("Plist \(sourceName): root is not a dictionary (got \(type(of: raw)))", level: .error)
            return nil
        }

        var metadata = AppPackageMetadata()
        metadata.applicationName  = (dict["CFBundleDisplayName"] as? String)
                                  ?? (dict["CFBundleName"] as? String)
                                  ?? (dict["CFBundleExecutable"] as? String)
                                  ?? ""
        metadata.bundleIdentifier = (dict["CFBundleIdentifier"] as? String) ?? ""
        metadata.versionShort     = (dict["CFBundleShortVersionString"] as? String) ?? ""
        metadata.versionBuild     = (dict["CFBundleVersion"] as? String) ?? ""
        metadata.minimumOSVersion = (dict["LSMinimumSystemVersion"] as? String)
                                  ?? (dict["MinimumOSVersion"] as? String)
                                  ?? ""

        if metadata.hasAnyMetadata {
            DebugLog.write("Plist \(sourceName) parsed — name=\(metadata.applicationName) bundle=\(metadata.bundleIdentifier) version=\(metadata.combinedVersion)", level: .info)
            return metadata
        } else {
            let keys = Array(dict.keys.prefix(15))
            DebugLog.write("Plist \(sourceName) parsed but contained no recognized CFBundle* keys. First keys: \(keys.joined(separator: ", "))", level: .warn)
            // Return the empty struct anyway so the caller still gets
            // the platform, fallback name, etc.  Operator can fill
            // remaining fields manually.
            return metadata
        }
    }
}
