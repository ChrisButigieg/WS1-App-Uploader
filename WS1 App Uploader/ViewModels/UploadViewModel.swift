//
//  UploadViewModel.swift
//  WS1 App Uploader
//

import Foundation
import Observation

@MainActor
@Observable
final class UploadViewModel {

    var pending: PendingUpload?
    var description: String = ""

    /// Staged copy of an optional icon image the operator provided.
    /// Used when the IPA doesn't carry a recognisable icon.
    var pendingIconURL: URL?
    var pendingIconFilename: String?

    // Organization groups (all loaded up-front, paginated)
    var ogFilter: String = ""
    var allOrganizationGroups: [OrganizationGroup] = []
    var isLoadingOGs: Bool = false
    var ogLoadProgress: Int = 0
    var ogLoadError: String?
    var selectedOrganizationGroup: OrganizationGroup?

    /// Client-side filtered list driven by `ogFilter`.
    var filteredOrganizationGroups: [OrganizationGroup] {
        guard !ogFilter.isEmpty else { return allOrganizationGroups }
        let needle = ogFilter.lowercased()
        return allOrganizationGroups.filter { og in
            og.name.lowercased().contains(needle)
                || (og.groupId?.lowercased().contains(needle) ?? false)
        }
    }

    // Retirement
    var isUpgrade: Bool = false
    var existingVersions: [WS1Application] = []
    var versionsToRetire: Set<Int> = []

    // Progress
    var progress = UploadProgress()
    var log: [String] = []
    var isBusy: Bool { progress.phase != .idle && progress.phase != .done && progress.phase != .failed }

    var lastError: String?

    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - File selection

    /// Called whenever a file is selected (picker, drag-and-drop).
    /// Copies the file into the app's sandbox temp directory so subsequent
    /// reads no longer depend on the security-scoped URL granted by the
    /// system picker — which is released as soon as the picker callback
    /// returns.  Without this copy, large uploads that start *after* the
    /// picker callback returns would fail with "could not be read".
    func ingest(fileURL: URL) {
        let scope = fileURL.startAccessingSecurityScopedResource()
        defer { if scope { fileURL.stopAccessingSecurityScopedResource() } }

        // 1. Verify readability while the security scope is still held.
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            lastError = "The file at \(fileURL.lastPathComponent) cannot be read."
            DebugLog.shared.log("Ingest failed: \(fileURL.path) is not readable.", level: .error)
            return
        }

        // 2. Copy into sandbox.
        let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WS1Uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir,
                                                 withIntermediateDirectories: true)
        let stagedFilename = "\(UUID().uuidString)-\(fileURL.lastPathComponent)"
        let staged = stagingDir.appendingPathComponent(stagedFilename)

        do {
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.copyItem(at: fileURL, to: staged)
            DebugLog.shared.log("Ingested \(fileURL.lastPathComponent) → \(staged.path)", level: .info)
        } catch {
            lastError = "Could not copy \(fileURL.lastPathComponent) into the app sandbox: \(error.localizedDescription)"
            DebugLog.shared.log("Ingest copy failed: \(error.localizedDescription)", level: .error)
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: staged.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let originalName = fileURL.lastPathComponent
        let metadata = AppFileInspector.parseMetadata(
            for: staged,
            originalFilename: originalName
        )
        pending = PendingUpload(fileURL: staged,
                                originalFilename: originalName,
                                fileSizeBytes: size,
                                metadata: metadata)
        lastError = nil
        // Pre-search retirements
        Task { await refreshExistingVersions() }
    }

    func setIcon(url: URL) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }

        let staging = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WS1Uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging,
                                                 withIntermediateDirectories: true)
        let staged = staging
            .appendingPathComponent("\(UUID().uuidString)-icon-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: staged)
        do {
            try FileManager.default.copyItem(at: url, to: staged)
            pendingIconURL      = staged
            pendingIconFilename = url.lastPathComponent
        } catch {
            DebugLog.shared.log("Icon stage failed: \(error.localizedDescription)", level: .error)
        }
    }

    func clearIcon() {
        if let url = pendingIconURL,
           url.path.contains("/WS1Uploads/") {
            try? FileManager.default.removeItem(at: url)
        }
        pendingIconURL      = nil
        pendingIconFilename = nil
    }

    func setInfoPlist(url: URL) {
        guard pending != nil else { return }
        pending?.infoPlistURL = url
        if let parsed = InfoPlistExtractor.metadata(fromPlistAt: url) {
            // Pre-fill metadata, preserving any manual overrides for
            // non-empty fields.
            pending?.metadata.applicationName  =
                pending?.metadata.applicationName.isEmpty == false
                ? pending!.metadata.applicationName
                : parsed.applicationName
            pending?.metadata.bundleIdentifier =
                pending?.metadata.bundleIdentifier.isEmpty == false
                ? pending!.metadata.bundleIdentifier
                : parsed.bundleIdentifier
            pending?.metadata.versionShort     =
                pending?.metadata.versionShort.isEmpty == false
                ? pending!.metadata.versionShort
                : parsed.versionShort
            pending?.metadata.versionBuild     =
                pending?.metadata.versionBuild.isEmpty == false
                ? pending!.metadata.versionBuild
                : parsed.versionBuild
        }
    }

    func resetSelection() {
        if let staged = pending?.fileURL,
           staged.path.contains("/WS1Uploads/") {
            try? FileManager.default.removeItem(at: staged)
        }
        pending = nil
        existingVersions = []
        versionsToRetire = []
        progress = UploadProgress()
        log = []
        lastError = nil
    }

    // MARK: - Organization groups

    /// Loads every Organization Group from the tenant in pages of 500.
    /// Safe to call multiple times — does nothing while a load is in
    /// progress.  Pre-selects the default OG configured in Settings
    /// when present.
    func loadAllOrganizationGroups(force: Bool = false) async {
        if isLoadingOGs { return }
        if !force && !allOrganizationGroups.isEmpty { return }

        isLoadingOGs = true
        ogLoadError = nil
        ogLoadProgress = 0
        defer { isLoadingOGs = false }

        do {
            let client = try appState.makeClient()
            allOrganizationGroups = try await client.fetchAllOrganizationGroups(
                progress: { [weak self] count in
                    Task { @MainActor in self?.ogLoadProgress = count }
                }
            )
            // Pre-select the configured default if it exists in the
            // returned set.
            if selectedOrganizationGroup == nil,
               appState.connection.organizationGroupID > 0,
               let match = allOrganizationGroups.first(where: {
                   $0.id == appState.connection.organizationGroupID
               }) {
                selectedOrganizationGroup = match
            }
        } catch {
            ogLoadError = error.localizedDescription
            allOrganizationGroups = []
        }
    }

    // MARK: - Existing versions (for retirement)

    func refreshExistingVersions() async {
        guard let bundle = pending?.metadata.bundleIdentifier, !bundle.isEmpty else { return }
        do {
            let client = try appState.makeClient()
            let raw = try await client.searchApplicationsByBundleID(bundle)
            // WS1's `bundleid=` search parameter does fuzzy / substring
            // matching on many tenants — apply a strict client-side
            // bundle-ID equality filter so we never surface an
            // unrelated app as a retirement candidate.
            let target = bundle.lowercased()
            existingVersions = raw.filter {
                $0.bundleIdentifier.lowercased() == target
            }
            if raw.count != existingVersions.count {
                DebugLog.shared.log("RefreshExisting \(bundle) — discarded \(raw.count - existingVersions.count) fuzzy result(s)", level: .warn)
            }
        } catch {
            // Quietly ignore — the user may not yet have configured a
            // connection.  This call is opportunistic.
            existingVersions = []
        }
    }

    // MARK: - Upload pipeline

    func performUpload() async {
        guard let pending else { return }
        guard let og = selectedOrganizationGroup
                ?? (appState.connection.organizationGroupID > 0
                    ? OrganizationGroup(id: appState.connection.organizationGroupID,
                                        name: appState.connection.organizationGroupName,
                                        groupId: nil,
                                        locationGroupType: nil)
                    : nil)
        else {
            lastError = "Please choose an organization group."
            return
        }

        log.removeAll()
        lastError = nil

        do {
            DebugLog.shared.log("Upload starting — file=\(pending.fileURL.lastPathComponent) size=\(pending.formattedFileSize) og=\(og.name)(\(og.id))", level: .info)
            let client = try appState.makeClient()

            updateProgress(phase: .authenticating,
                           fraction: 0.05,
                           message: "Authenticating with Workspace ONE …")
            appendLog("Connecting to \(appState.connection.apiBaseURL)")

            // Optional icon upload.
            var iconUUID: String? = nil
            if let iconURL = pendingIconURL {
                appendLog("Uploading custom icon — \(iconURL.lastPathComponent)")
                iconUUID = try await client.uploadIcon(fileURL: iconURL,
                                                       organizationGroupID: og.id)
            }

            updateProgress(phase: .uploadingBlob,
                           fraction: 0.0,
                           message: "Uploading \(pending.displayFilename) (\(pending.formattedFileSize))")
            appendLog("Starting chunked upload — \(pending.formattedFileSize)")

            let transactionID = try await client.uploadChunks(
                fileURL: pending.fileURL,
                progress: { [weak self] f in
                    Task { @MainActor in
                        self?.progress.fraction = f
                    }
                }
            )
            appendLog("Chunks uploaded — transactionId \(transactionID)")

            updateProgress(phase: .creatingApp,
                           fraction: 0.7,
                           message: "Creating application record …")

            let payload = makePayload(transactionID: transactionID,
                                      iconUUID: iconUUID,
                                      locationGroupID: og.id)
            let created = try await client.createInternalApplication(payload: payload)
            appendLog("Application created — id \(created.ws1Id) \(created.applicationName)")

            var retiredIDs: [Int] = []
            if isUpgrade && !versionsToRetire.isEmpty {
                updateProgress(phase: .retiring,
                               fraction: 0.85,
                               message: "Retiring previous version(s) …")
                for id in versionsToRetire {
                    do {
                        try await client.retireApplication(appID: id)
                        appendLog("Retired application id \(id)")
                        retiredIDs.append(id)
                    } catch {
                        appendLog("Could not retire id \(id): \(error.localizedDescription)")
                    }
                }
            }

            updateProgress(phase: .done, fraction: 1.0, message: "Upload complete.")
            appendLog("Done.")

            UploadHistoryStore.shared.record(
                UploadActivity(
                    applicationName: pending.metadata.applicationName,
                    version: pending.metadata.combinedVersion,
                    bundleIdentifier: pending.metadata.bundleIdentifier,
                    platform: pending.metadata.platform,
                    outcome: .succeeded,
                    message: "Uploaded to OG \(og.name).",
                    retiredVersionIDs: retiredIDs
                )
            )

        } catch let e as WS1Error {
            handleFailure(e.localizedDescription)
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func handleFailure(_ message: String) {
        updateProgress(phase: .failed, fraction: 0, message: message)
        appendLog("FAILED: \(message)")
        lastError = message
        if let pending {
            UploadHistoryStore.shared.record(
                UploadActivity(
                    applicationName: pending.metadata.applicationName,
                    version: pending.metadata.combinedVersion,
                    bundleIdentifier: pending.metadata.bundleIdentifier,
                    platform: pending.metadata.platform,
                    outcome: .failed,
                    message: message
                )
            )
        }
    }

    private func makePayload(transactionID: String,
                             iconUUID: String?,
                             locationGroupID: Int) -> CreateApplicationPayload {
        let metadata = pending?.metadata ?? AppPackageMetadata()
        let macosPlist: CreateApplicationPayload.MacOSInfoPlist? = {
            guard metadata.platform == .macOS else { return nil }
            return .init(bundleId: metadata.bundleIdentifier,
                         bundleVersion: metadata.versionBuild,
                         bundleShortVersion: metadata.versionShort,
                         isInstaller: ["pkg", "dmg"].contains(pending?.fileURL.pathExtension.lowercased() ?? ""))
        }()
        // /begininstall derives BundleId, AppVersion and BuildVersion
        // from the uploaded binary itself when UploadViaLink = false.
        // The custom encoder omits these nil fields entirely so the
        // server doesn't reject the call with errorCode 6.
        return CreateApplicationPayload(
            applicationName: metadata.applicationName,
            bundleId: nil,
            appVersion: nil,
            buildVersion: nil,
            deviceType: metadata.platform.ws1DeviceType,
            transactionId: transactionID,
            fileName: pending?.originalFilename,
            locationGroupId: locationGroupID,
            supportedModels: .defaults(for: metadata.platform.ws1DeviceType),
            pushMode: "Auto",
            macOsInfoPlist: macosPlist,
            applicationDescription: description.isEmpty ? nil : description,
            uploadViaLink: false,
            autoUpdateVersion: true,
            enableProvisioning: false,
            isDependencyFile: false,
            isReimbursable: false,
            contentGatewayId: 0,
            iconBlobUuid: iconUUID,
            management: nil
        )
    }

    private func updateProgress(phase: UploadProgress.Phase, fraction: Double, message: String) {
        progress.phase = phase
        progress.fraction = fraction
        progress.message = message
    }

    private func appendLog(_ line: String) {
        let stamp = DateFormatter.localizedString(from: .now, dateStyle: .none, timeStyle: .medium)
        log.append("[\(stamp)] \(line)")
    }

    // MARK: - Version helpers

    func suggestBumpedVersion() {
        guard var pending else { return }
        pending.metadata = pending.metadata.bumpingPatchVersion()
        self.pending = pending
    }
}
