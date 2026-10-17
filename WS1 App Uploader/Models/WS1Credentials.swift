//
//  WS1Credentials.swift
//  WS1 App Uploader
//

import Foundation

/// Selected authentication strategy against the Workspace ONE UEM API.
enum AuthMethod: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Legacy basic auth + `aw-tenant-code` header.
    case basicTenantCode
    /// OAuth 2.0 client-credentials flow (recommended).
    case oauth2ClientCredentials
    /// Certificate-based auth using a p12 cert + CMSURL header signing.
    case certificateCMSURL

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basicTenantCode:         return "Basic + Tenant Code"
        case .oauth2ClientCredentials: return "OAuth 2.0 (Client Credentials)"
        case .certificateCMSURL:       return "Certificate (p12 + CMSURL)"
        }
    }

    var summary: String {
        switch self {
        case .basicTenantCode:
            return "Legacy authentication — username, password, and aw-tenant-code header."
        case .oauth2ClientCredentials:
            return "Recommended.  Uses an OAuth 2.0 client ID + secret and a token endpoint."
        case .certificateCMSURL:
            return "High-assurance.  Signs each request with a p12 client certificate using the CMSURL header."
        }
    }
}

/// Connection configuration for a WS1 UEM tenant.  Persisted in the
/// Keychain as JSON via `KeychainStore`.
struct WS1Connection: Codable, Equatable, Sendable {
    /// Base URL of the API server (eg. `https://as1234.awmdm.com`).
    var apiBaseURL: String       = ""
    /// `aw-tenant-code` header value (required for the v1 APIs).
    var tenantCode: String       = ""
    /// Default OG (organization group) ID — used when creating apps.
    var organizationGroupID: Int = 0
    /// User-friendly OG name (for display only).
    var organizationGroupName: String = ""

    var authMethod: AuthMethod = .oauth2ClientCredentials

    // Basic auth fields
    var username: String = ""
    /// Plain-text password.  Stored only inside the Keychain blob.
    var password: String = ""

    // OAuth 2.0 fields
    var oauthTokenURL: String   = ""
    var oauthClientID: String   = ""
    var oauthClientSecret: String = ""

    // Certificate fields
    /// User-friendly filename of the loaded p12 — actual bytes live in
    /// `KeychainStore` under a separate key.
    var certificateFilename: String = ""
    /// Password protecting the p12 — kept here for convenience.
    var certificatePassword: String = ""

    /// Validation guard — used by the Settings UI to gate the "Test"
    /// button.
    var isMinimallyConfigured: Bool {
        guard !apiBaseURL.isEmpty, URL(string: apiBaseURL) != nil else { return false }
        switch authMethod {
        case .basicTenantCode:
            return !tenantCode.isEmpty && !username.isEmpty && !password.isEmpty
        case .oauth2ClientCredentials:
            return !oauthTokenURL.isEmpty
                && !oauthClientID.isEmpty
                && !oauthClientSecret.isEmpty
        case .certificateCMSURL:
            return !certificateFilename.isEmpty
        }
    }
}
