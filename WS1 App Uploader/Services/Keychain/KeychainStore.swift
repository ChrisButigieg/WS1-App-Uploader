//
//  KeychainStore.swift
//  WS1 App Uploader
//
//  Thin wrapper around the iOS / macOS Security framework for storing
//  the WS1 connection blob and (separately) p12 certificate data.
//

import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case osStatus(OSStatus, String)
    case dataDecodingFailed

    var errorDescription: String? {
        switch self {
        case .osStatus(let s, let op):
            let message = SecCopyErrorMessageString(s, nil) as String? ?? "OSStatus \(s)"
            return "Keychain \(op) failed: \(message)"
        case .dataDecodingFailed:
            return "Stored keychain data could not be decoded."
        }
    }
}

/// Singleton-style entry point for all secure persistence used by the
/// app.  All entries live under a single service identifier so they can
/// be enumerated and reset together.
struct KeychainStore: Sendable {

    static let shared = KeychainStore()

    private let service = "com.afr.missionmobile.ws1uploader"

    // MARK: - Connection blob

    private let connectionAccount  = "ws1.connection"
    private let certificateAccount = "ws1.certificate.p12"

    func saveConnection(_ connection: WS1Connection) throws {
        let data = try JSONEncoder().encode(connection)
        try setData(data, account: connectionAccount)
    }

    func loadConnection() -> WS1Connection? {
        guard let data = try? getData(account: connectionAccount) else { return nil }
        return try? JSONDecoder().decode(WS1Connection.self, from: data)
    }

    func clearConnection() throws {
        try delete(account: connectionAccount)
    }

    // MARK: - Certificate bytes

    func saveCertificate(_ data: Data) throws {
        try setData(data, account: certificateAccount)
    }

    func loadCertificate() -> Data? {
        try? getData(account: certificateAccount)
    }

    func clearCertificate() throws {
        try delete(account: certificateAccount)
    }

    // MARK: - Generic helpers

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func setData(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.osStatus(updateStatus, "update")
            }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus, "add")
            }
        } else {
            throw KeychainError.osStatus(status, "lookup")
        }
    }

    private func getData(account: String) throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.osStatus(status, "read")
        }
        return data
    }

    private func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.osStatus(status, "delete")
        }
    }
}
