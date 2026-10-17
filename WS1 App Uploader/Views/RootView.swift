//
//  RootView.swift
//  WS1 App Uploader
//
//  Three-column NavigationSplitView container with a branded sidebar.
//

import SwiftUI

enum AppSection: Hashable, Identifiable, CaseIterable {
    case dashboard
    case batchUpload
    case upload
    case library
    case history
    case help
    case debug
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard:   return "Dashboard"
        case .batchUpload: return "Batch Upload"
        case .upload:      return "Upload Application"
        case .library:     return "App Library"
        case .history:     return "History"
        case .help:        return "Help"
        case .debug:       return "Debug Log"
        case .settings:    return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:   return "square.grid.2x2"
        case .batchUpload: return "square.stack.3d.up.fill"
        case .upload:      return "square.and.arrow.up.on.square"
        case .library:     return "books.vertical"
        case .history:     return "clock.arrow.circlepath"
        case .help:        return "questionmark.circle"
        case .debug:       return "terminal"
        case .settings:    return "gearshape"
        }
    }
}

struct RootView: View {

    @State private var selection: AppSection = .dashboard
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.brandAccent)
    }

    @ViewBuilder private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader()
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)

            List(AppSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.body.weight(.medium))
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Divider()
                HStack(spacing: 6) {
                    Circle().fill(appState.isConfigured ? Theme.success : Theme.warning).frame(width: 8, height: 8)
                    Text(appState.isConfigured ? "Connected" : "Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, Theme.Spacing.md)
            }
        }
        .navigationTitle("Mission Mobile")
        #if os(macOS)
        .frame(minWidth: 240)
        #endif
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .dashboard:   DashboardView(navigate: { selection = $0 })
        case .batchUpload: BatchUploadView()
        case .upload:      UploadView()
        case .library:     AppLibraryView()
        case .history:     HistoryView()
        case .help:        HelpView()
        case .debug:       DebugLogView()
        case .settings:    SettingsView()
        }
    }
}
