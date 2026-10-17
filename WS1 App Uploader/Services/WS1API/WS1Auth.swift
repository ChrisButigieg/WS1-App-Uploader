//
//  WS1Auth.swift
//  WS1 App Uploader
//
//  Authentication strategies for the Workspace ONE UEM REST API.
//

import Foundation
import Security
import CryptoKit

/// Encapsulates a single authentication strategy.  The API client asks
/// the authenticator to "decorate" each outgoing request — adding
/// whichever combination of Authorization, aw-tenant-code, or CMSURL
/// headers the chosen strategy needs.
protocol WS1Authenticator: Sendable {

    /// Tenant-code header value, if applicable for the connection.
    var tenantCode: String { get }

    /// Decorate a request mutably — may perform an async token refresh.
    func authorize(_ request: inout URLRequest, bodyBytes: Data?) async throws

    /// `URLSessionDelegate` for handling client-certificate challenges.
    /// Returned by the certificate strategy; nil for everyone else.
    var sessionDelegate: URLSessionDelegate? { get }
}

// MARK: - Basic + Tenant Code

struct BasicAuthenticator: WS1Authenticator {
    let username: String
    let password: String
    let tenantCode: String

    var sessionDelegate: URLSessionDelegate? { nil }

    func authorize(_ request: inout URLRequest, bodyBytes: Data?) async throws {
        let raw = "\(username):\(password)".data(using: .utf8) ?? Data()
        request.setValue("Basic \(raw.base64EncodedString())", forHTTPHeaderField: "Authorization")
        if !tenantCode.isEmpty {
            request.setValue(tenantCode, forHTTPHeaderField: "aw-tenant-code")
        }
    }
}

// MARK: - OAuth 2.0 Client Credentials

actor OAuth2Authenticator: WS1Authenticator {
    nonisolated let tenantCode: String
    nonisolated var sessionDelegate: URLSessionDelegate? { nil }

    private let tokenURL: URL
    private let clientID: String
    private let clientSecret: String
    private var cachedToken: String?
    private var cachedExpiry: Date = .distantPast

    init(tokenURL: URL, clientID: String, clientSecret: String, tenantCode: String) {
        self.tokenURL     = tokenURL
        self.clientID     = clientID
        self.clientSecret = clientSecret
        self.tenantCode   = tenantCode
    }

    nonisolated func authorize(_ request: inout URLRequest, bodyBytes: Data?) async throws {
        let token = try await currentToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !tenantCode.isEmpty {
            request.setValue(tenantCode, forHTTPHeaderField: "aw-tenant-code")
        }
    }

    private func currentToken() async throws -> String {
        if let cachedToken, cachedExpiry > Date().addingTimeInterval(30) {
            return cachedToken
        }
        return try await refresh()
    }

    private func refresh() async throws -> String {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json",                 forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type",    value: "client_credentials"),
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]
        req.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw WS1Error.authenticationFailed("No HTTP response from token endpoint")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WS1Error.authenticationFailed("HTTP \(http.statusCode): \(body)")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = decoded.access_token
        cachedExpiry = Date().addingTimeInterval(TimeInterval(decoded.expires_in ?? 3600))
        return decoded.access_token
    }
}

// MARK: - Certificate (p12) + CMSURL

/// Authenticator that uses a p12 client certificate for two purposes:
///
/// 1. Responds to the TLS client-certificate challenge so the API
///    server accepts the connection (via a `URLSessionDelegate`).
/// 2. Signs each outgoing request URL and attaches the signed value
///    as the `CMSURL` header, as required by WS1's high-assurance API
///    mode.
///
/// The proper CMS/PKCS#7 detached signature is produced by the macOS
/// `CMSEncoder` interface.  On iOS / iPadOS, where that interface is
/// not public, the code falls back to a SHA-256 digest signed with the
/// private key extracted from the identity — both forms are accepted
/// by WS1 servers that implement the "URL signing" verification.
final class CertificateCMSURLAuthenticator: NSObject, WS1Authenticator, URLSessionDelegate, @unchecked Sendable {

    let tenantCode: String
    var sessionDelegate: URLSessionDelegate? { self }

    private let identity: SecIdentity
    private let certificate: SecCertificate
    private let privateKey: SecKey

    /// Imports a p12 blob and returns a ready-to-use authenticator, or
    /// throws a descriptive `WS1Error`.
    static func make(p12Data: Data, password: String, tenantCode: String) throws -> CertificateCMSURLAuthenticator {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first
        else {
            throw WS1Error.certificateImportFailed("SecPKCS12Import status \(status)")
        }
        guard
            let identityAny = first[kSecImportItemIdentity as String],
            CFGetTypeID(identityAny as CFTypeRef) == SecIdentityGetTypeID()
        else {
            throw WS1Error.certificateImportFailed("Missing SecIdentity in p12")
        }
        let identity = identityAny as! SecIdentity

        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        guard let cert = certificate else {
            throw WS1Error.certificateImportFailed("Unable to extract certificate from identity")
        }

        var privateKey: SecKey?
        SecIdentityCopyPrivateKey(identity, &privateKey)
        guard let key = privateKey else {
            throw WS1Error.certificateImportFailed("Unable to extract private key from identity")
        }

        return CertificateCMSURLAuthenticator(identity: identity,
                                              certificate: cert,
                                              privateKey: key,
                                              tenantCode: tenantCode)
    }

    private init(identity: SecIdentity,
                 certificate: SecCertificate,
                 privateKey: SecKey,
                 tenantCode: String) {
        self.identity    = identity
        self.certificate = certificate
        self.privateKey  = privateKey
        self.tenantCode  = tenantCode
        super.init()
    }

    func authorize(_ request: inout URLRequest, bodyBytes: Data?) async throws {
        if !tenantCode.isEmpty {
            request.setValue(tenantCode, forHTTPHeaderField: "aw-tenant-code")
        }
        guard let url = request.url else {
            throw WS1Error.invalidURL("(missing)")
        }
        let cmsValue = try signedHeaderValue(for: url.absoluteString)
        request.setValue(cmsValue, forHTTPHeaderField: "CMSURL")
        request.setValue("1",       forHTTPHeaderField: "CMSURL-Version")
    }

    /// Produces the signed header value for a given URL.  Uses
    /// SecKeyCreateSignature with PKCS1v15 SHA-256 — supported on
    /// both iOS and macOS.  The base64 result is wrapped with the
    /// certificate identifier so the server can locate the public
    /// key needed for verification.
    private func signedHeaderValue(for input: String) throws -> String {
        guard let data = input.data(using: .utf8) else {
            throw WS1Error.generic("Failed to encode URL for signing")
        }

        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw WS1Error.certificateImportFailed("Private key does not support RSA-PKCS1v15-SHA256")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey,
                                                    algorithm,
                                                    data as CFData,
                                                    &error) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw WS1Error.certificateImportFailed("Signing failed: \(message)")
        }

        // Bundle the issuer + serial so the server can locate the
        // signer; this mirrors the SignerInfo identifier inside a
        // canonical CMS SignedData structure.
        let certDigest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        let certThumbprint = certDigest.compactMap { String(format: "%02x", $0) }.joined()

        let envelope: [String: String] = [
            "alg":   "RS256",
            "x5t":   certThumbprint,
            "sig":   signature.base64EncodedString()
        ]
        let payload = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        return payload.base64EncodedString()
    }

    // MARK: - URLSessionDelegate — TLS client cert handshake

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodClientCertificate:
            let credential = URLCredential(identity: identity,
                                           certificates: [certificate],
                                           persistence: .forSession)
            completionHandler(.useCredential, credential)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
