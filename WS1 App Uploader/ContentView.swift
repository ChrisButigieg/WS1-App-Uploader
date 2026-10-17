//
//  ContentView.swift
//  WS1 App Uploader
//
//  Preview-only thin wrapper. The real root is `RootView`.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
            .environment(AppState())
    }
}

#Preview {
    ContentView()
}
