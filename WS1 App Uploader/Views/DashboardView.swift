//
//  DashboardView.swift
//  WS1 App Uploader
//

import SwiftUI

struct DashboardView: View {

    var navigate: (AppSection) -> Void
    @Environment(AppState.self) private var appState
    @State private var history = UploadHistoryStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                quickActions
                recentActivity
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle("Dashboard")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WELCOME")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Mission Mobile")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Air Force Reserve — Workspace ONE Application Uploader")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                BrandHeader(compact: true)
                    .colorScheme(.dark)
            }
            HStack(spacing: Theme.Spacing.md) {
                StatusBadge(text: appState.isConfigured ? "Connected" : "Configure connection",
                            kind: appState.isConfigured ? .success : .warning)
                if !appState.connection.apiBaseURL.isEmpty {
                    Text(appState.connection.apiBaseURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            LinearGradient(
                colors: [Theme.airForceBlue, Theme.skyAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: "Quick Actions", icon: "bolt.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Spacing.md)],
                      alignment: .leading,
                      spacing: Theme.Spacing.md) {
                actionTile("Batch Upload",
                           "Drop a folder full of IPAs / PKGs and ship them in one click.",
                           "square.stack.3d.up.fill",
                           color: Theme.brandAccent) {
                    navigate(.batchUpload)
                }
                actionTile("Upload an App",
                           "Single-file workflow with full per-app configuration.",
                           "square.and.arrow.up.on.square",
                           color: Theme.brandAccent) {
                    navigate(.upload)
                }
                actionTile("Browse App Library",
                           "Look up existing internal applications in the tenant.",
                           "books.vertical",
                           color: Theme.skyAccent) {
                    navigate(.library)
                }
                actionTile("Configure Connection",
                           appState.isConfigured ? "Update tenant URL or credentials." : "First, set up your WS1 tenant credentials.",
                           "gearshape",
                           color: appState.isConfigured ? Theme.silver : Theme.actionRed) {
                    navigate(.settings)
                }
                actionTile("Review History",
                           "See every upload performed from this device.",
                           "clock.arrow.circlepath",
                           color: Theme.success) {
                    navigate(.history)
                }
            }
        }
    }

    private func actionTile(_ title: String,
                            _ subtitle: String,
                            _ symbol: String,
                            color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                SectionTitle(text: "Recent Uploads", icon: "clock")
                Spacer()
                Button("View All") { navigate(.history) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if history.activities.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No uploads yet.").foregroundStyle(.secondary)
                    Text("Get started by uploading your first application.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
                .cardSurface()
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(history.activities.prefix(5)) { activity in
                        ActivityRow(activity: activity)
                    }
                }
            }
        }
    }

    @Environment(\.colorScheme) private var scheme
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color.black, Theme.surfaceDark]
                : [Color.white, Theme.surfaceLight],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct ActivityRow: View {
    let activity: UploadActivity

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Image(systemName: activity.platform.sfSymbol)
                .font(.title3)
                .foregroundStyle(Theme.brandAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.applicationName).font(.body.weight(.semibold))
                Text(activity.bundleIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
            }

            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                StatusBadge(text: activity.outcome.rawValue, kind: statusKind(for: activity.outcome))
                Text(activity.version).font(.caption.weight(.medium))
                Text(activity.timestamp, style: .relative).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.md)
        .cardSurface()
    }

    private func statusKind(for outcome: UploadActivity.Outcome) -> StatusKind {
        switch outcome {
        case .succeeded: return .success
        case .failed:    return .failure
        case .cancelled: return .neutral
        }
    }
}
