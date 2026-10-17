//
//  WS1_App_UploaderApp.swift
//  WS1 App Uploader
//

import SwiftUI

@main
struct WS1_App_UploaderApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 640)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        #endif
    }
}
