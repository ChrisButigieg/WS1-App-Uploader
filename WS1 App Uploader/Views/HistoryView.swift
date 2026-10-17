//
//  HistoryView.swift
//  WS1 App Uploader
//

import SwiftUI

struct HistoryView: View {

    @State private var store = UploadHistoryStore.shared
    @State private var showClearConfirm = false

    var body: some View {
        Group {
            if store.activities.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(store.activities) { ActivityRow(activity: $0) }
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(store.activities.isEmpty)
            }
        }
        .confirmationDialog("Clear all upload history?",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("Clear all", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No upload history yet").font(.title3.weight(.semibold))
            Text("Uploads performed from this device will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
