//
//  WS1Error.swift
//  WS1 App Uploader
//

import Foundation

/// Top-level error surface for everything reachable from the API
/// client.  Maps to user-facing messages in the UI.
enum WS1Error: Error, LocalizedError {
    case notConfigured
    case invalidURL(String)
    case authenticationFailed(String)
    case missingCertificate
    case certificateImportFailed(String)
    case httpStatus(Int, String?)
    case decoding(String)
    case transport(URLError)
    case fileUnreadable(URL)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Workspace ONE connection is not configured.  Open Settings to provide credentials."
        case .invalidURL(let s):
            return "The URL \"\(s)\" is not valid."
        case .authenticationFailed(let m):
            return "Authentication failed: \(m)"
        case .missingCertificate:
            return "A p12 certificate is required for this authentication method."
        case .certificateImportFailed(let m):
            return "Could not import p12 certificate: \(m)"
        case .httpStatus(let code, let body):
            return "WS1 responded with HTTP \(code).\n\(body ?? "")"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .decoding(let m):
            return "Failed to parse WS1 response: \(m)"
        case .transport(let e):
            return "Network error: \(e.localizedDescription)"
        case .fileUnreadable(let u):
            return "The file at \"\(u.lastPathComponent)\" could not be read."
        case .generic(let m):
            return m
        }
    }
}
