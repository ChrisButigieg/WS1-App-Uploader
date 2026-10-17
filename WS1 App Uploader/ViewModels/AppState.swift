//
//  AppState.swift
//  WS1 App Uploader
//
//  Root observable that holds the active connection and produces an
//  API client on demand.  Injected into the view hierarchy as an
//  `@Environment` so every screen can reach the same configuration
//  without singletons.
//

import SwiftUI
import Observation

@Observable
final class AppState {

    /// The latest connection loaded from / saved to the Keychain.
    var connection: WS1Connection

    /// `true` once the user has provided enough information for the
    /// API client to be constructed.
    var isConfigured: Bool { connection.isMinimallyConfigured }

    init() {
        self.connection = KeychainStore.shared.loadConnection() ?? WS1Connection()
    }

    /// Persists the current connection blob (including the password
    /// fields).  Throws KeychainError on failure.
    func persist() throws {
        try KeychainStore.shared.saveConnection(connection)
    }

    /// Produce a configured API client for the current connection, or
    /// throw if anything is missing / malformed.
    func makeClient() throws -> WS1APIClient {
        guard isConfigured else { throw WS1Error.notConfigured }
        let authenticator = try makeAuthenticator()
        return try WS1APIClient(connection: connection, authenticator: authenticator)
    }

    private func makeAuthenticator() throws -> WS1Authenticator {
        switch connection.authMethod {
        case .basicTenantCode:
            return BasicAuthenticator(username: connection.username,
                                      password: connection.password,
                                      tenantCode: connection.tenantCode)
        case .oauth2ClientCredentials:
            guard let url = URL(string: connection.oauthTokenURL) else {
                throw WS1Error.invalidURL(connection.oauthTokenURL)
            }
            return OAuth2Authenticator(tokenURL: url,
                                       clientID: connection.oauthClientID,
                                       clientSecret: connection.oauthClientSecret,
                                       tenantCode: connection.tenantCode)
        case .certificateCMSURL:
            guard let p12 = KeychainStore.shared.loadCertificate() else {
                throw WS1Error.missingCertificate
            }
            return try CertificateCMSURLAuthenticator.make(p12Data: p12,
                                                           password: connection.certificatePassword,
                                                           tenantCode: connection.tenantCode)
        }
    }
}
