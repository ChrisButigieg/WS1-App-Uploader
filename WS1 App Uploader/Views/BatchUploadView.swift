//
//  BatchUploadView.swift
//  WS1 App Uploader
//
//  Streamlined multi-file upload workflow.  Drop or pick N files; the
//  app auto-detects new-vs-update against the tenant, groups items by
//  platform, applies management defaults, then runs the queue
//  serially with per-row progress.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct BatchUploadView: View {

    /// Tracks which sub-picker the importer is currently displaying.
    enum PickerMode {
        case packages
        case plist(itemID: UUID)
        case icon(itemID: UUID)
    }

    @Environment(AppState.self) private var appState
    @State private var vm: BatchUploadViewModel?
    @State private var pickerMode: PickerMode = .packages
    @State private var showPicker = false
    @State private var isTargeted = false
    @State private var ogExpanded = false

    var body: some View {
        Group {
            if let vm { content(vm: vm) }
            else { ProgressView() }
        }
        .navigationTitle("Batch Upload")
        .onAppear {
            if vm == nil {
                let v = BatchUploadViewModel(appState: appState)
                vm = v
                Task { await v.loadAllOrganizationGroups() }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(vm: BatchUploadViewModel) -> some View {
        if !appState.isConfigured {
            notConfigured
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    headerCard(vm: vm)
                    dropZone(vm: vm)
                    if !vm.items.isEmpty {
                        ForEach(vm.itemsByPlatform, id: \.0) { platform, items in
                            platformSection(platform: platform, items: items, vm: vm)
                        }
                    }
                    if !vm.items.isEmpty {
                        actionBar(vm: vm)
                    }
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: allowedTypesForCurrentMode,
                allowsMultipleSelection: allowsMultipleForCurrentMode,
                onCompletion: { result in handlePickerResult(result, vm: vm) }
            )
        }
    }

    private var notConfigured: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(Theme.actionRed)
            Text("Connection not configured")
                .font(.title2.weight(.semibold))
            Text("Provide your Workspace ONE UEM API URL and credentials in Settings before uploading.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .cardSurface()
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Header

    private func headerCard(vm: BatchUploadViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                SectionTitle(text: "Default Settings",
                             subtitle: "Applied to every item in the batch — override per row as needed.",
                             icon: "gearshape.2")
                Spacer()
                if !vm.items.isEmpty {
                    summaryPill(text: "\(vm.queuedCount) queued",   kind: .info)
                    summaryPill(text: "\(vm.succeededCount) done",  kind: .success)
                    if vm.failedCount > 0 {
                        summaryPill(text: "\(vm.failedCount) failed", kind: .failure)
                    }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ogPicker(vm: vm)
            }
            .cardSurface()
        }
    }

    private func summaryPill(text: String, kind: StatusKind) -> some View {
        StatusBadge(text: text, kind: kind)
    }

    // MARK: - OG picker (inline)

    private func ogPicker(vm: BatchUploadViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabelledField(title: "Default Organization Group",
                          hint: "All items in this batch publish to this OG.") {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { ogExpanded.toggle() }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(Theme.brandAccent)
                        if let og = vm.selectedOrganizationGroup {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(og.name).font(.body.weight(.medium))
                                if let gid = og.groupId {
                                    Text(gid).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        } else if vm.isLoadingOGs && vm.allOrganizationGroups.isEmpty {
                            ProgressView().scaleEffect(0.6)
                            Text("Loading organization groups…")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Select an organization group…").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: ogExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.silver.opacity(0.5), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if ogExpanded { ogDropdown(vm: vm) }
            if let err = vm.ogLoadError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.actionRed)
            }
        }
    }

    private func ogDropdown(vm: BatchUploadViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter \(vm.allOrganizationGroups.count) groups…",
                          text: Bindable(vm).ogFilter)
                    .textFieldStyle(.plain)
                Button {
                    Task { await vm.loadAllOrganizationGroups(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

            let filtered = vm.filteredOrganizationGroups
            if filtered.isEmpty {
                Text(vm.isLoadingOGs
                     ? "Loading… (\(vm.ogLoadProgress) so far)"
                     : "No matching organization groups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered.prefix(300)) { og in
                            Button {
                                vm.selectedOrganizationGroup = og
                                ogExpanded = false
                                vm.ogFilter = ""
                            } label: {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: vm.selectedOrganizationGroup?.id == og.id
                                                        ? "checkmark.circle.fill"
                                                        : "circle")
                                        .foregroundStyle(vm.selectedOrganizationGroup?.id == og.id
                                                         ? Theme.success : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(og.name).font(.body)
                                        if let gid = og.groupId {
                                            Text(gid).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text("\(og.id)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Drop zone

    private func dropZone(vm: BatchUploadViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                SectionTitle(text: "Files",
                             subtitle: vm.items.isEmpty
                                ? "Drop multiple IPAs/PKGs/APKs/MSIs here, or click Add Files."
                                : "\(vm.items.count) file(s) ready.",
                             icon: "shippingbox.fill")
                Spacer()
                Button {
                    pickerMode = .packages
                    showPicker = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                if !vm.items.isEmpty {
                    Button(role: .destructive) { vm.removeAll() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            if vm.items.isEmpty {
                emptyDropTarget(vm: vm)
            }
        }
    }

    private func emptyDropTarget(vm: BatchUploadViewModel) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brandAccent)
            Text("Drop one or many files here")
            Text("Supported: .ipa  .pkg  .dmg  .app  .zip  .apk  .aab  .msi  .exe")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Theme.brandAccent : Theme.silver)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(isTargeted ? Theme.brandAccent.opacity(0.10) : Color.clear)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers, vm: vm)
        }
    }

    // MARK: - Platform section

    private func platformSection(platform: PlatformType,
                                 items: [BatchUploadItem],
                                 vm: BatchUploadViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: platform.sfSymbol)
                    .font(.title2)
                    .foregroundStyle(Theme.brandAccent)
                Text(platform.displayName)
                    .font(.title3.weight(.semibold))
                StatusBadge(text: "\(items.count)", kind: .info)
                Spacer()
            }
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    BatchItemRow(item: item,
                                 vm: vm,
                                 onSelectPlist: { presentPlistPicker(for: item) },
                                 onSelectIcon:  { presentIconPicker(for: item) })
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers, vm: vm)
        }
    }

    // MARK: - Action bar

    private func actionBar(vm: BatchUploadViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                if let err = vm.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.actionRed)
                }
                if !vm.summary.isEmpty {
                    Label(vm.summary, systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                }
                Spacer()
                Button {
                    Task { await vm.runBatch() }
                } label: {
                    Label(vm.isRunning
                            ? "Uploading…"
                            : "Upload All \(vm.queuedCount) App(s)",
                          systemImage: vm.isRunning ? "hourglass" : "square.and.arrow.up.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(vm.isRunning
                          || vm.queuedCount == 0
                          || vm.selectedOrganizationGroup == nil)
            }
        }
    }

    // MARK: - File handling

    private var packageTypes: [UTType] {
        var types: [UTType] = [.data, .item]
        for ext in ["ipa", "pkg", "dmg", "zip", "apk", "aab", "msi", "exe", "appx", "appxbundle"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        #if os(macOS)
        types.append(.application)
        #endif
        return types
    }

    private var plistTypes: [UTType] {
        var types: [UTType] = [.propertyList, .xml, .data]
        if let t = UTType(filenameExtension: "plist") { types.append(t) }
        return types
    }

    private var iconTypes: [UTType] {
        [.png, .jpeg, .image, .data]
    }

    private var allowedTypesForCurrentMode: [UTType] {
        switch pickerMode {
        case .packages: return packageTypes
        case .plist:    return plistTypes
        case .icon:     return iconTypes
        }
    }

    private var allowsMultipleForCurrentMode: Bool {
        switch pickerMode {
        case .packages: return true
        case .plist:    return false
        case .icon:     return false
        }
    }

    /// Single dispatch for the shared `.fileImporter` — picks the right
    /// handler based on the active mode.
    private func handlePickerResult(_ result: Result<[URL], Error>, vm: BatchUploadViewModel) {
        switch pickerMode {
        case .packages:
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            var accessing: [URL] = []
            for url in urls where url.startAccessingSecurityScopedResource() {
                accessing.append(url)
            }
            vm.add(fileURLs: urls)
            for url in accessing { url.stopAccessingSecurityScopedResource() }
        case .plist(let itemID):
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard let item = vm.items.first(where: { $0.id == itemID }) else { return }
            vm.setInfoPlist(for: item, url: url)
        case .icon(let itemID):
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard let item = vm.items.first(where: { $0.id == itemID }) else { return }
            vm.setIcon(for: item, url: url)
        }
    }

    /// Called by `BatchItemRow` when the user taps "Select Info.plist".
    fileprivate func presentPlistPicker(for item: BatchUploadItem) {
        pickerMode = .plist(itemID: item.id)
        showPicker = true
    }

    /// Called by `BatchItemRow` when the user taps "Select Icon…".
    fileprivate func presentIconPicker(for item: BatchUploadItem) {
        pickerMode = .icon(itemID: item.id)
        showPicker = true
    }

    private func handleDrop(providers: [NSItemProvider], vm: BatchUploadViewModel) -> Bool {
        let group = DispatchGroup()
        var collected: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !collected.isEmpty { vm.add(fileURLs: collected) }
        }
        return true
    }
}

// MARK: - Row

struct BatchItemRow: View {

    let item: BatchUploadItem
    @Bindable var vm: BatchUploadViewModel
    var onSelectPlist: () -> Void
    var onSelectIcon:  () -> Void
    @State private var expanded = false

    /// True when the item is missing the critical bits the upload
    /// pipeline needs and can't continue without operator input.
    private var needsAttention: Bool {
        item.metadata.bundleIdentifier.isEmpty
            || item.metadata.applicationName.isEmpty
            || item.metadata.combinedVersion.isEmpty
    }

    /// True when this is a macOS package format we can't auto-extract
    /// Info.plist from (`.pkg`, `.dmg`).  Used to decide whether the
    /// row should surface a plist picker — IPAs / APKs / MSIs already
    /// carry their metadata in formats we can parse directly.
    private var supportsPlistImport: Bool {
        item.metadata.platform == .macOS
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            mainRow
            if needsAttention {
                attentionBanner
            }
            if item.status == .running || item.progress > 0 {
                progressRow
            }
            if expanded { expandedControls }
        }
        .cardSurface()
        .onAppear {
            // Auto-expand rows that need operator input so the controls
            // are immediately reachable.
            if needsAttention { expanded = true }
        }
    }

    private var mainRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Image(systemName: item.metadata.platform.sfSymbol)
                .font(.title3)
                .foregroundStyle(Theme.brandAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.metadata.applicationName.isEmpty
                        ? item.displayFilename
                        : item.metadata.applicationName)
                    .font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text(item.metadata.bundleIdentifier.isEmpty
                            ? "(no bundle ID)"
                            : item.metadata.bundleIdentifier)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(item.metadata.combinedVersion.isEmpty
                            ? "(no version)"
                            : item.metadata.combinedVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(item.formattedFileSize)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                detectionLabel
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(text: item.status.displayName, kind: item.status.kind)
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Label("Options",
                          systemImage: expanded ? "chevron.up.circle" : "slider.horizontal.3")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button(role: .destructive) {
                    vm.remove(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.actionRed)
            }
        }
    }

    private var detectionLabel: some View {
        HStack(spacing: 4) {
            switch item.detection {
            case .undetermined, .detecting:
                ProgressView().scaleEffect(0.5)
                Text(item.detection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .newApp:
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.success)
                Text(item.detection.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
            case .updatesExisting:
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Theme.brandAccent)
                Text(item.detection.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.brandAccent)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text(item.detection.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(item.status == .failed ? Theme.actionRed : Theme.brandAccent)
            if !item.statusMessage.isEmpty {
                Text(item.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Attention banner

    @ViewBuilder
    private var attentionBanner: some View {
        let missing = missingMetadataMessage
        if !missing.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text(missing)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                Spacer()
                if supportsPlistImport {
                    Button {
                        onSelectPlist()
                    } label: {
                        Label("Select Info.plist…", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.warning.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var missingMetadataMessage: String {
        var missing: [String] = []
        if item.metadata.applicationName.isEmpty  { missing.append("name") }
        if item.metadata.bundleIdentifier.isEmpty { missing.append("bundle ID") }
        if item.metadata.combinedVersion.isEmpty  { missing.append("version") }
        if missing.isEmpty { return "" }
        let action = supportsPlistImport
            ? "Edit below or supply an Info.plist."
            : "Edit below to fill in the required fields."
        return "Missing: \(missing.joined(separator: ", ")). " + action
    }

    // MARK: - Expanded controls

    private var expandedControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Divider()

            // Plist picker — only for macOS packages, since IPA / APK /
            // MSI files carry their metadata inside the archive in a
            // format we already auto-parse.
            if supportsPlistImport {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(Theme.brandAccent)
                    Text("Use Info.plist for metadata")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Select Info.plist…") { onSelectPlist() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

            // Icon picker — available for every platform.  Lets the
            // operator attach a PNG / JPG when the binary doesn't
            // include a usable icon.
            iconSection

            // Editable identity fields — always shown so admins can
            // override anything the auto-detector got wrong.
            metadataEditor

            // Per-item description
            LabelledField(title: "Description (optional)") {
                TextField("",
                          text: Binding(
                            get: { item.settings.description },
                            set: { item.settings.description = $0 }
                          ))
                    .textFieldStyle(.roundedBorder)
            }

            // Update controls
            if case .updatesExisting(let existing) = item.detection {
                Toggle(isOn: Binding(
                    get: { item.settings.retirePreviousVersion },
                    set: { item.settings.retirePreviousVersion = $0 }
                )) {
                    VStack(alignment: .leading) {
                        Text("Retire previous version(s) automatically")
                        Text(existing.map { "\($0.applicationName) \($0.appVersion)" }
                                  .joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.brandAccent)
            } else if case .newApp = item.detection {
                // New-app management defaults
                Text("Management Defaults (new application)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Prevent application backup",
                       isOn: Binding(
                        get: { item.settings.preventBackup },
                        set: { item.settings.preventBackup = $0 }
                       ))
                    .toggleStyle(.switch).tint(Theme.brandAccent)
                Toggle("Remove on MDM removal / un-enroll",
                       isOn: Binding(
                        get: { item.settings.removeOnMDMRemoval },
                        set: { item.settings.removeOnMDMRemoval = $0 }
                       ))
                    .toggleStyle(.switch).tint(Theme.brandAccent)
                Toggle("Make managed if user-installed",
                       isOn: Binding(
                        get: { item.settings.makeManagedIfUserInstalled },
                        set: { item.settings.makeManagedIfUserInstalled = $0 }
                       ))
                    .toggleStyle(.switch).tint(Theme.brandAccent)
            }
        }
    }

    @ViewBuilder
    private var iconSection: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let url = item.iconFileURL,
               let data = try? Data(contentsOf: url) {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    iconPlaceholder
                }
                #elseif canImport(AppKit)
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    iconPlaceholder
                }
                #else
                iconPlaceholder
                #endif
            } else {
                iconPlaceholder
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("App Icon")
                    .font(.caption.weight(.semibold))
                Text(item.iconFilename ?? "Use the bundle's default icon")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(item.iconFileURL == nil ? "Select Icon…" : "Replace") {
                onSelectIcon()
            }
            .buttonStyle(SecondaryButtonStyle())
            if item.iconFileURL != nil {
                Button(role: .destructive) {
                    vm.clearIcon(for: item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.actionRed)
            }
        }
    }

    private var iconPlaceholder: some View {
        Image(systemName: "app.badge")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
            .background(Color.gray.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                LabelledField(title: "Application Name",
                              hint: item.detection.existingApps.isEmpty
                                ? nil
                                : "Locked from WS1 — change only if you intend to rename the application.") {
                    TextField("Application name",
                              text: Binding(
                                get: { item.metadata.applicationName },
                                set: { item.metadata.applicationName = $0 }
                              ))
                        .textFieldStyle(.roundedBorder)
                }
                LabelledField(title: "Bundle ID / Package",
                              hint: "Re-detection runs after you change this.") {
                    TextField("com.example.app",
                              text: Binding(
                                get: { item.metadata.bundleIdentifier },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                    if trimmed != item.metadata.bundleIdentifier {
                                        item.metadata.bundleIdentifier = trimmed
                                        vm.bundleIDDidChange(for: item)
                                    }
                                }
                              ))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
            }
            HStack(spacing: Theme.Spacing.md) {
                LabelledField(title: "Version") {
                    TextField("1.0.0",
                              text: Binding(
                                get: { item.metadata.versionShort },
                                set: { item.metadata.versionShort = $0 }
                              ))
                        .textFieldStyle(.roundedBorder)
                }
                LabelledField(title: "Build") {
                    TextField("Build",
                              text: Binding(
                                get: { item.metadata.versionBuild },
                                set: { item.metadata.versionBuild = $0 }
                              ))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
