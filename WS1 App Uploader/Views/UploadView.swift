//
//  UploadView.swift
//  WS1 App Uploader
//
//  Primary workflow.  Pick a file (or drop one on macOS), tweak the
//  metadata, optionally select an Info.plist, choose an OG, and
//  upload — retiring the previous version when requested.
//

import SwiftUI
import UniformTypeIdentifiers

struct UploadView: View {

    /// Tracks which kind of file the importer is currently presenting.
    /// SwiftUI's `.fileImporter` is single-instance per view — using a
    /// state enum on a single modifier is the recommended way to allow
    /// multiple "kinds" of file pickers from the same screen.
    enum PickerMode {
        case package, plist, icon
    }

    @Environment(AppState.self) private var appState
    @State private var vm: UploadViewModel?
    @State private var pickerMode: PickerMode = .package
    @State private var showPicker = false

    var body: some View {
        Group {
            if let vm { uploadContent(vm: vm) }
            else { ProgressView() }
        }
        .navigationTitle("Upload Application")
        .onAppear {
            if vm == nil {
                let v = UploadViewModel(appState: appState)
                vm = v
                Task { await v.loadAllOrganizationGroups() }
            }
        }
    }

    @ViewBuilder
    private func uploadContent(vm: UploadViewModel) -> some View {
        if !appState.isConfigured {
            notConfiguredBanner
                .padding(Theme.Spacing.xl)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    FileDropZone(
                        pending: vm.pending,
                        onSelect: { presentPicker(.package) },
                        onDrop:   { vm.ingest(fileURL: $0) },
                        onClear:  { vm.resetSelection() }
                    )

                    if vm.pending != nil {
                        PlistImportSection(
                            pending: Binding(
                                get: { vm.pending },
                                set: { vm.pending = $0 }
                            ),
                            onPickPlist: { presentPicker(.plist) }
                        )

                        UploadFormView(vm: vm)

                        RetirementSection(vm: vm)

                        UploadActionBar(vm: vm)
                    }
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: allowedTypesForCurrentMode,
                allowsMultipleSelection: false,
                onCompletion: { result in handlePicker(result, mode: pickerMode) }
            )
        }
    }

    private func presentPicker(_ mode: PickerMode) {
        pickerMode = mode
        showPicker = true
    }

    private var packageTypes: [UTType] {
        // `.data` is intentionally first — without it, the system file
        // picker on iPadOS sometimes refuses to display .ipa / .pkg
        // files because no installed UTI claims them.
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
        case .package: return packageTypes
        case .plist:   return plistTypes
        case .icon:    return iconTypes
        }
    }

    private func handlePicker(_ result: Result<[URL], Error>, mode: PickerMode) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        switch mode {
        case .package: vm?.ingest(fileURL: url)
        case .plist:   vm?.setInfoPlist(url: url)
        case .icon:    vm?.setIcon(url: url)
        }
    }

    private var notConfiguredBanner: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(Theme.actionRed)
            Text("Connection not configured")
                .font(.title2.weight(.semibold))
            Text("Provide your Workspace ONE UEM API URL and credentials in Settings before uploading applications.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

// MARK: - File Drop Zone

struct FileDropZone: View {

    let pending: PendingUpload?
    let onSelect: () -> Void
    let onDrop: (URL) -> Void
    let onClear: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: "Application Package", icon: "shippingbox")
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let pending {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                Image(systemName: pending.metadata.platform.sfSymbol)
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.brandAccent)
                    .frame(width: 56, height: 56)
                    .background(Theme.brandAccent.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.displayFilename).font(.headline)
                    Text(pending.formattedFileSize).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        StatusBadge(text: pending.metadata.platform.displayName, kind: .info)
                        if pending.metadata.hasAnyMetadata {
                            StatusBadge(text: "Metadata detected", kind: .success)
                        } else {
                            StatusBadge(text: "Metadata not detected", kind: .warning)
                        }
                    }
                }
                Spacer()
                Button("Choose Different…") { onSelect() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Remove", role: .destructive) { onClear() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .cardSurface()
        } else {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.brandAccent)
                Text("Drop a file here, or").font(.body)
                Button("Select a File…") { onSelect() }
                    .buttonStyle(PrimaryButtonStyle())
                Text("Supported: .ipa, .app, .pkg, .dmg, .zip, .apk, .aab, .msi, .exe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        DispatchQueue.main.async { onDrop(url) }
                    }
                }
                return true
            }
        }
    }
}

// MARK: - Plist Import Section

struct PlistImportSection: View {

    @Binding var pending: PendingUpload?
    let onPickPlist: () -> Void

    var body: some View {
        guard let p = pending, p.metadata.platform == .macOS else {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionTitle(text: "Use Info.plist",
                             subtitle: "macOS packages — extract Application Name, Bundle ID, and Version from a plist.",
                             icon: "doc.text.magnifyingglass")
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: p.infoPlistURL == nil ? "doc.questionmark" : "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(p.infoPlistURL == nil ? Theme.warning : Theme.success)
                    VStack(alignment: .leading) {
                        Text(p.infoPlistURL?.lastPathComponent ?? "No Info.plist selected")
                            .font(.body.weight(.medium))
                        Text(p.infoPlistURL == nil
                                ? "Select one manually, or rely on auto-extraction from a .app bundle on macOS."
                                : "Loaded. Fields below have been pre-populated.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Select Info.plist…") { onPickPlist() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .cardSurface()
            }
        )
    }
}

// MARK: - Form

struct UploadFormView: View {

    @Bindable var vm: UploadViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: "Application Details", icon: "tag")
            VStack(spacing: Theme.Spacing.md) {
                rowOne
                rowTwo
                LabelledField(title: "Description",
                              hint: "Optional. Free-form notes displayed in the WS1 console.") {
                    TextEditor(text: $vm.description)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .font(.body)
                }
                ogPicker
            }
            .cardSurface()
        }
    }

    private var rowOne: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                LabelledField(title: "Application Name") {
                    TextField("Application Name",
                              text: Binding(
                                get: { vm.pending?.metadata.applicationName ?? "" },
                                set: { vm.pending?.metadata.applicationName = $0 }
                              ))
                        .textFieldStyle(.roundedBorder)
                }
                LabelledField(title: "Bundle ID / Package") {
                    TextField("com.example.app",
                              text: Binding(
                                get: { vm.pending?.metadata.bundleIdentifier ?? "" },
                                set: { vm.pending?.metadata.bundleIdentifier = $0 }
                              ))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
            }
        }
    }

    private var rowTwo: some View {
        HStack(spacing: Theme.Spacing.md) {
            LabelledField(title: "Version") {
                HStack {
                    TextField("1.0.0",
                              text: Binding(
                                get: { vm.pending?.metadata.versionShort ?? "" },
                                set: { vm.pending?.metadata.versionShort = $0 }
                              ))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        vm.suggestBumpedVersion()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .help("Bump patch version")
                    .buttonStyle(.plain)
                }
            }
            LabelledField(title: "Build") {
                TextField("Build",
                          text: Binding(
                            get: { vm.pending?.metadata.versionBuild ?? "" },
                            set: { vm.pending?.metadata.versionBuild = $0 }
                          ))
                    .textFieldStyle(.roundedBorder)
            }
            LabelledField(title: "Platform") {
                Picker("Platform",
                       selection: Binding(
                            get: { vm.pending?.metadata.platform ?? .unknown },
                            set: { vm.pending?.metadata.platform = $0 }
                       )) {
                    ForEach(PlatformType.allCases) { p in
                        Label(p.displayName, systemImage: p.sfSymbol).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var ogPicker: some View {
        OrganizationGroupPicker(vm: vm)
    }
}

// MARK: - Organization Group Picker

/// Dropdown / popover picker driven by the pre-loaded list of OGs.
/// Includes a client-side filter, paged loading progress, and a manual
/// refresh button.
struct OrganizationGroupPicker: View {

    @Bindable var vm: UploadViewModel
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabelledField(title: "Organization Group",
                          hint: "Required for upload.  All OGs are loaded from the tenant.") {
                triggerButton
            }

            if isExpanded { dropdown }

            if let err = vm.ogLoadError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.actionRed)
            }
        }
    }

    private var triggerButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.3.fill").foregroundStyle(Theme.brandAccent)
                if vm.isLoadingOGs && vm.allOrganizationGroups.isEmpty {
                    ProgressView().scaleEffect(0.6)
                    Text("Loading organization groups…").foregroundStyle(.secondary)
                } else if let og = vm.selectedOrganizationGroup {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(og.name).font(.body.weight(.medium))
                        if let gid = og.groupId {
                            Text(gid).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Select an organization group…").foregroundStyle(.secondary)
                }
                Spacer()
                if vm.isLoadingOGs && !vm.allOrganizationGroups.isEmpty {
                    Text("Loaded \(vm.ogLoadProgress)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter \(vm.allOrganizationGroups.count) groups…",
                          text: $vm.ogFilter)
                    .textFieldStyle(.plain)
                Button {
                    Task { await vm.loadAllOrganizationGroups(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload all organization groups")
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
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered.prefix(300)) { og in
                            ogRow(og)
                            Divider()
                        }
                        if filtered.count > 300 {
                            Text("Showing first 300 of \(filtered.count) — type to narrow the list.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func ogRow(_ og: OrganizationGroup) -> some View {
        Button {
            vm.selectedOrganizationGroup = og
            isExpanded = false
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
                    HStack(spacing: 6) {
                        if let gid = og.groupId {
                            Text(gid).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let type = og.locationGroupType {
                            Text(type).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                Text("\(og.id)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Retirement Section

struct RetirementSection: View {

    @Bindable var vm: UploadViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: "Upgrade & Retirement", icon: "arrow.up.arrow.down.square")
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Toggle(isOn: $vm.isUpgrade) {
                    VStack(alignment: .leading) {
                        Text("This is an upgrade — retire previous version(s)").font(.body)
                        Text("If checked, the selected installations below will be retired after the new upload completes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.brandAccent)

                if vm.isUpgrade {
                    if vm.existingVersions.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            Text("Looking up existing versions for \(vm.pending?.metadata.bundleIdentifier ?? "")")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        Button("Search again") { Task { await vm.refreshExistingVersions() } }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        ForEach(vm.existingVersions) { existing in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { vm.versionsToRetire.contains(existing.ws1Id) },
                                    set: { newValue in
                                        if newValue { vm.versionsToRetire.insert(existing.ws1Id) }
                                        else        { vm.versionsToRetire.remove(existing.ws1Id) }
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Image(systemName: existing.platformType.sfSymbol)
                                            .foregroundStyle(Theme.brandAccent)
                                        VStack(alignment: .leading) {
                                            Text(existing.applicationName).font(.body)
                                            Text("\(existing.appVersion) · \(existing.bundleIdentifier)")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox(fallbackTint: Theme.brandAccent))
                                Spacer()
                                if let status = existing.status {
                                    StatusBadge(text: status, kind: .info)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
            }
            .cardSurface()
        }
    }
}

// MARK: - Action Bar / Progress

struct UploadActionBar: View {

    @Bindable var vm: UploadViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Spacer()
                Button {
                    Task { await vm.performUpload() }
                } label: {
                    Label("Upload to Workspace ONE", systemImage: "square.and.arrow.up.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(vm.isBusy || vm.pending == nil)
            }
            if vm.progress.phase != .idle {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text(vm.progress.phase.rawValue).font(.headline)
                        Spacer()
                        if vm.progress.phase == .done { StatusBadge(text: "Complete", kind: .success) }
                        if vm.progress.phase == .failed { StatusBadge(text: "Failed",   kind: .failure) }
                    }
                    ProgressView(value: vm.progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(vm.progress.phase == .failed ? Theme.actionRed : Theme.brandAccent)
                    Text(vm.progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !vm.log.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(vm.log, id: \.self) { line in
                                    Text(line).font(.caption.monospaced())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                        .padding(8)
                        .background(Color.black.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .cardSurface()
            }
        }
    }
}

// MARK: - Toggle "checkbox" cross-platform fallback

private struct CheckboxToggleStyle: ToggleStyle {
    let fallbackTint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(configuration.isOn ? fallbackTint : .secondary)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    static func checkbox(fallbackTint: Color) -> CheckboxToggleStyle { CheckboxToggleStyle(fallbackTint: fallbackTint) }
}
