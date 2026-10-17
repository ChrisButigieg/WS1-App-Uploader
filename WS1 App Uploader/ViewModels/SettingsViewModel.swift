//
//  SettingsViewModel.swift
//  WS1 App Uploader
//

import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {

    enum TestResult: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    /// Mutable copy that the form binds to.  Persisted to AppState
    /// only when the user taps Save.
    var draft: WS1Connection
    var result: TestResult = .idle
    var certificateStagedFilename: String?
    var certificateStagedData: Data?
    var certificateExistsInKeychain: Bool

    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self.draft = appState.connection
        self.certificateExistsInKeychain = (KeychainStore.shared.loadCertificate() != nil)
    }

    func revert() {
        draft = appState.connection
        result = .idle
    }

    func save() throws {
        if let data = certificateStagedData {
            try KeychainStore.shared.saveCertificate(data)
            draft.certificateFilename = certificateStagedFilename ?? draft.certificateFilename
            certificateStagedData = nil
            certificateStagedFilename = nil
            certificateExistsInKeychain = true
        }
        appState.connection = draft
        try appState.persist()
    }

    func clearCertificate() {
        try? KeychainStore.shared.clearCertificate()
        draft.certificateFilename = ""
        certificateExistsInKeychain = false
    }

    func stageCertificate(_ data: Data, filename: String) {
        certificateStagedData = data
        certificateStagedFilename = filename
        draft.certificateFilename = filename
    }

    func testConnection() async {
        result = .testing
        do {
            // Use the *draft* connection rather than the persisted one
            // so the user can verify before saving.
            let tempState = AppState()
            tempState.connection = draft
            // Stage the certificate in memory too if just selected.
            if let staged = certificateStagedData {
                try KeychainStore.shared.saveCertificate(staged)
            }
            let client = try tempState.makeClient()
            try await client.testConnection()
            result = .success("Connection successful — credentials accepted.")
        } catch let e as WS1Error {
            result = .failure(e.localizedDescription)
        } catch {
            result = .failure(error.localizedDescription)
        }
    }
}
