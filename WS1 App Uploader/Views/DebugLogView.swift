//
//  DebugLogView.swift
//  WS1 App Uploader
//
//  Diagnostic console — shows every API request, response, and upload
//  pipeline event.  Provides Copy-All and Clear actions so engineers
//  can paste the full transcript into a bug report.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct DebugLogView: View {

    @State private var log = DebugLog.shared
    @State private var copied: Bool = false
    @State private var filter: String = ""
    @State private var autoscroll: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            filterBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            row(entry)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .background(Color.black.opacity(0.30),
                            in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: log.entries.count) { _, _ in
                    if autoscroll {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Debug Log")
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            SectionTitle(text: "Debug Log",
                         subtitle: "Every API request and pipeline event made from this session.",
                         icon: "terminal")
            Spacer()
            Toggle("Auto-scroll", isOn: $autoscroll)
                .toggleStyle(.switch)
                .tint(Theme.brandAccent)
                .controlSize(.small)
            Button {
                copyAll()
            } label: {
                Label(copied ? "Copied!" : "Copy All",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(log.entries.isEmpty)
            Button(role: .destructive) {
                log.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(log.entries.isEmpty)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter… (e.g. 'mam/apps', '404', 'AUTH')", text: $filter)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
            Text("\(filteredEntries.count) / \(log.entries.count) entries")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color.gray.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private var filteredEntries: [DebugLog.Entry] {
        guard !filter.isEmpty else { return log.entries }
        let needle = filter.lowercased()
        return log.entries.filter {
            $0.message.lowercased().contains(needle)
                || $0.level.rawValue.lowercased().contains(needle)
        }
    }

    private func row(_ entry: DebugLog.Entry) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(formatter.string(from: entry.timestamp))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(entry.level.rawValue)
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(levelColor(entry.level))
                .fontWeight(.semibold)
            Text(entry.message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 2)
    }

    private func levelColor(_ level: DebugLog.Level) -> Color {
        switch level {
        case .info:  return Theme.silver
        case .warn:  return Theme.warning
        case .error: return Theme.actionRed
        case .api:   return Theme.skyAccent
        }
    }

    // MARK: - Copy

    private func copyAll() {
        let text = log.exportAsText()
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
