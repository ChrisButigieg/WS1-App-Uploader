//
//  AppLibraryViewModel.swift
//  WS1 App Uploader
//

import Foundation
import Observation

@MainActor
@Observable
final class AppLibraryViewModel {

    var query: String = ""
    var apps: [WS1Application] = []
    var isLoading: Bool = false
    var error: String?

    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let client = try appState.makeClient()
            apps = try await client.searchApplications(name: query.isEmpty ? nil : query)
        } catch let e as WS1Error {
            error = e.localizedDescription
            apps = []
        } catch {
            self.error = error.localizedDescription
            apps = []
        }
    }
}
