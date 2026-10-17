//
//  PlatformType.swift
//  WS1 App Uploader
//

import Foundation

/// Application platform recognized by Workspace ONE UEM.
///
/// Values map (loosely) to the `ApplicationType` and `DeviceType`
/// expectations of the WS1 internal-applications endpoints.  Keep the
/// raw values stable — they are persisted in upload history.
enum PlatformType: String, CaseIterable, Identifiable, Codable, Sendable {
    case iOS
    case macOS
    case android
    case windows
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iOS:     return "iOS / iPadOS"
        case .macOS:   return "macOS"
        case .android: return "Android"
        case .windows: return "Windows"
        case .unknown: return "Unknown"
        }
    }

    /// `DeviceType` value as expected by WS1 v1/v2 internal-applications
    /// endpoints.  Mapping derived from Omnissa public API docs.
    var ws1DeviceType: String {
        switch self {
        case .iOS:     return "Apple"
        case .macOS:   return "AppleOsX"
        case .android: return "Android"
        case .windows: return "WinRT"
        case .unknown: return ""
        }
    }

    var sfSymbol: String {
        switch self {
        case .iOS:     return "iphone"
        case .macOS:   return "laptopcomputer"
        case .android: return "smartphone"
        case .windows: return "pc"
        case .unknown: return "questionmark.square.dashed"
        }
    }

    /// File extensions associated with this platform.
    var fileExtensions: [String] {
        switch self {
        case .iOS:     return ["ipa"]
        case .macOS:   return ["app", "pkg", "dmg", "zip"]
        case .android: return ["apk", "aab"]
        case .windows: return ["msi", "exe", "zip", "appx", "appxbundle"]
        case .unknown: return []
        }
    }

    /// Best-effort detection from a file extension alone.  Note: `.zip`
    /// is ambiguous (macOS vs. Windows) and must be disambiguated by
    /// inspecting contents.
    static func from(fileExtension ext: String) -> PlatformType {
        switch ext.lowercased() {
        case "ipa":                                  return .iOS
        case "app", "pkg", "dmg":                    return .macOS
        case "apk", "aab":                           return .android
        case "msi", "exe", "appx", "appxbundle":     return .windows
        default:                                     return .unknown
        }
    }
}
