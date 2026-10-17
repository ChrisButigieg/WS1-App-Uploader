//
//  AppLibraryView.swift
//  WS1 App Uploader
//

import SwiftUI

struct AppLibraryView: View {

    @Environment(AppState.self) private var appState
    @State private var vm: AppLibraryViewModel?

    var body: some View {
        Group {
            if let vm { content(vm: vm) }
            else { ProgressView() }
        }
        .navigationTitle("App Library")
        .onAppear {
            if vm == nil {
                let v = AppLibraryViewModel(appState: appState)
                vm = v
                Task { await v.reload() }
            }
        }
    }

    @ViewBuilder
    private func content(vm: AppLibraryViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by application name…", text: Bindable(vm).query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await vm.reload() } }
                Button("Refresh") { Task { await vm.reload() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.lg)

            if vm.isLoading {
                ProgressView("Loading apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.error {
                errorView(err)
            } else if vm.apps.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(vm.apps) { app in
                            LibraryRow(app: app)
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
        }
    }

    private func errorView(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble").font(.title).foregroundStyle(Theme.actionRed)
            Text("Failed to load apps").font(.headline)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical").font(.title).foregroundStyle(.secondary)
            Text("No applications found").font(.headline)
            Text("Try adjusting your search.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LibraryRow: View {
    let app: WS1Application

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            topRow
            metaRow
            if !app.smartGroups.isEmpty {
                assignmentsRow
            }
        }
        .cardSurface()
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: app.platformType.sfSymbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.brandAccent)
                .background(Theme.brandAccent.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.applicationName)
                    .font(.body.weight(.semibold))
                Text(app.bundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(app.appVersion).font(.body.monospaced())
                HStack(spacing: 4) {
                    if let status = app.status, !status.isEmpty {
                        StatusBadge(text: status,
                                    kind: status.lowercased() == "active" ? .success : .neutral)
                    }
                    if let assignment = app.assignmentStatus, !assignment.isEmpty {
                        StatusBadge(text: assignment,
                                    kind: assignment.lowercased() == "assigned" ? .info : .neutral)
                    }
                }
            }
        }
    }

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.lg) {
            if let og = app.organizationGroupName, !og.isEmpty {
                metaItem(icon: "building.2",
                         label: "Managed by",
                         value: og)
            }
            metaItem(icon: "ipad.and.iphone",
                     label: "Devices",
                     value: deviceCountSummary)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private var deviceCountSummary: String {
        // Always show assigned / installed; surface "not installed" if non-zero.
        let assigned  = app.assignedDeviceCount
        let installed = app.installedDeviceCount
        let notInst   = app.notInstalledDeviceCount
        if notInst > 0 {
            return "\(installed) installed · \(notInst) pending · \(assigned) assigned"
        }
        return "\(installed) installed · \(assigned) assigned"
    }

    private func metaItem(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brandAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var assignmentsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.crop.square.stack")
                    .foregroundStyle(Theme.brandAccent)
                Text("Smart Group Assignments")
                    .font(.caption2)
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.tertiary)
            }
            FlowingTagList(tags: app.smartGroups.map(\.name))
        }
    }
}

/// Tag-style row that wraps onto multiple lines.  Renders the smart
/// group names as full-width pills (no truncation) using a custom
/// wrapping `Layout`.
struct FlowingTagList: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 6, runSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.brandAccent.opacity(0.15),
                                in: Capsule())
                    .foregroundStyle(Theme.brandAccent)
            }
        }
    }
}

/// Wrapping layout: lays subviews out left-to-right and breaks to a
/// new row whenever the next subview's intrinsic width would overflow
/// the proposed container width.  Each subview keeps its natural
/// width, so tag pills can be as wide as their text demands without
/// being truncated.
struct FlowLayout: Layout {
    var spacing: CGFloat   = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } +
                     CGFloat(max(0, rows.count - 1)) * runSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout Void) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = row.sizes[index]
                subviews[row.indices[index]].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + runSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes:   [CGSize] = []
        var width:   CGFloat = 0
        var height:  CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let projected = current.width
                          + (current.indices.isEmpty ? 0 : spacing)
                          + size.width
            if projected > maxWidth && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            if !current.indices.isEmpty { current.width += spacing }
            current.indices.append(index)
            current.sizes.append(size)
            current.width  += size.width
            current.height  = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
