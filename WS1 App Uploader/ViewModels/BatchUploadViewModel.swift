//
//  BatchUploadViewModel.swift
//  WS1 App Uploader
//
//  Multi-file upload coordinator.  Ingests N picked/dropped files,
//  runs detection (new vs. update) against the tenant in parallel,
//  then executes the uploads serially with per-item status reporting.
//

import Foundation
import Observation

@MainActor
@Observable
final class BatchUploadViewModel {

    // MARK: - State

    var items: [BatchUploadItem] = []
    /// Single default OG applied to every item in the batch.
    var selectedOrganizationGroup: OrganizationGroup?

    // Organization groups (loaded once, shared)
    var allOrganizationGroups: [OrganizationGroup] = []
    var ogFilter: String = ""
    var isLoadingOGs: Bool = false
    var ogLoadProgress: Int = 0
    var ogLoadError: String?

    var isRunning: Bool = false
    var summary: String = ""
    var lastError: String?

    var filteredOrganizationGroups: [OrganizationGroup] {
        guard !ogFilter.isEmpty else { return allOrganizationGroups }
        let needle = ogFilter.lowercased()
        return allOrganizationGroups.filter {
            $0.name.lowercased().contains(needle)
                || ($0.groupId?.lowercased().contains(needle) ?? false)
        }
    }

    var itemsByPlatform: [(PlatformType, [BatchUploadItem])] {
        let groups = Dictionary(grouping: items, by: \.metadata.platform)
        return PlatformType.allCases.compactMap { p in
            guard let xs = groups[p], !xs.isEmpty else { return nil }
            return (p, xs)
        }
    }

    var queuedCount: Int    { items.filter { $0.status == .pending  }.count }
    var succeededCount: Int { items.filter { $0.status == .succeeded }.count }
    var failedCount: Int    { items.filter { $0.status == .failed   }.count }

    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        if appState.connection.organizationGroupID > 0 {
            self.selectedOrganizationGroup = OrganizationGroup(
                id:   appState.connection.organizationGroupID,
                name: appState.connection.organizationGroupName,
                groupId: nil,
                locationGroupType: nil
            )
        }
    }

    // MARK: - File ingestion

    /// Copies each picked URL into the app sandbox, parses metadata,
    /// then kicks off detection against the tenant.
    func add(fileURLs: [URL]) {
        for url in fileURLs {
            ingest(fileURL: url)
        }
        Task { await detectAllPending() }
    }

    private func ingest(fileURL: URL) {
        let scope = fileURL.startAccessingSecurityScopedResource()
        defer { if scope { fileURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            DebugLog.shared.log("Batch ingest unreadable: \(fileURL.path)", level: .error)
            return
        }

        let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WS1Uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir,
                                                 withIntermediateDirectories: true)
        let staged = stagingDir
            .appendingPathComponent("\(UUID().uuidString)-\(fileURL.lastPathComponent)")
        do {
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.copyItem(at: fileURL, to: staged)
        } catch {
            DebugLog.shared.log("Batch ingest copy failed: \(error.localizedDescription)", level: .error)
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: staged.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let originalFilename = fileURL.lastPathComponent
        let metadata = AppFileInspector.parseMetadata(for: staged,
                                                      originalFilename: originalFilename)
        let item = BatchUploadItem(fileURL: staged,
                                   originalFilename: originalFilename,
                                   fileSizeBytes: size,
                                   metadata: metadata)
        items.append(item)
        DebugLog.shared.log("Batch added \(item.displayFilename) [\(metadata.platform.displayName)]", level: .info)
    }

    func remove(_ item: BatchUploadItem) {
        if item.fileURL.path.contains("/WS1Uploads/") {
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        items.removeAll { $0.id == item.id }
    }

    func removeAll() {
        for item in items { remove(item) }
        items.removeAll()
        summary = ""
        lastError = nil
    }

    // MARK: - Detection

    private func detectAllPending() async {
        // Run detections in parallel — they're independent GETs.
        await withTaskGroup(of: Void.self) { group in
            for item in items where item.detection == .undetermined {
                group.addTask { @MainActor [weak self] in
                    await self?.detect(item: item)
                }
            }
        }
    }

    /// Public re-detection trigger.  Called after the user edits the
    /// bundle ID or supplies an Info.plist for an item that was
    /// previously detected as needing manual review.
    func redetect(item: BatchUploadItem) {
        Task { await self.detect(item: item) }
    }

    private func detect(item: BatchUploadItem) async {
        let bundleID = item.metadata.bundleIdentifier
        guard !bundleID.isEmpty else {
            item.detection = .error("No bundle ID detected — provide one below or select an Info.plist.")
            return
        }
        item.detection = .detecting

        // Snapshot the metadata name before detection so we can detect
        // an inappropriate WS1 rename and back it out if necessary.
        let originalIPAName = item.metadata.applicationName

        do {
            let client = try appState.makeClient()
            let rawMatches = try await client.searchApplicationsByBundleID(bundleID)
            DebugLog.shared.log("Detect \(bundleID) — server returned \(rawMatches.count) result(s)", level: .info)

            // WS1's `bundleid=` query parameter does fuzzy / substring
            // matching on many tenants — it will happily return apps
            // whose bundle ID merely *contains* our string, or worse,
            // unrelated apps when the parameter is ignored entirely.
            // We re-filter client-side so an update is only reported
            // when the bundle ID matches **exactly** (case-insensitive).
            let targetBundle = bundleID.lowercased()
            let strict = rawMatches.filter {
                $0.bundleIdentifier.lowercased() == targetBundle
            }
            if rawMatches.count != strict.count {
                let dropped = rawMatches
                    .filter { $0.bundleIdentifier.lowercased() != targetBundle }
                    .prefix(5)
                    .map { "\($0.applicationName)[\($0.bundleIdentifier)]" }
                    .joined(separator: ", ")
                DebugLog.shared.log("Detect \(bundleID) — discarded \(rawMatches.count - strict.count) fuzzy result(s): \(dropped)", level: .warn)
            }

            let activeMatches = strict.filter {
                $0.status?.lowercased() == "active"
                    && $0.platformType == item.metadata.platform
            }

            if activeMatches.isEmpty {
                item.detection = .newApp
                // Restore the IPA's own name in case any earlier
                // detection pass overwrote it.
                if !originalIPAName.isEmpty {
                    item.metadata.applicationName = originalIPAName
                }
                DebugLog.shared.log("Detect \(bundleID) → NEW (no exact bundle-ID match in tenant)", level: .info)
            } else {
                item.detection = .updatesExisting(activeMatches)
                // Inherit the canonical app name only when every match
                // we got back agrees on what the app should be called.
                // (Multiple matches with different names → ambiguous;
                // keep whatever the IPA said and let the operator
                // arbitrate.)
                let distinctNames = Set(activeMatches.map(\.applicationName)).filter { !$0.isEmpty }
                if distinctNames.count == 1, let canonical = distinctNames.first {
                    item.metadata.applicationName = canonical
                    DebugLog.shared.log("Detect \(bundleID) → UPDATE (\(activeMatches.count)) — name locked to \"\(canonical)\"", level: .info)
                } else {
                    DebugLog.shared.log("Detect \(bundleID) → UPDATE (\(activeMatches.count)) — multiple candidate names, keeping IPA name \"\(item.metadata.applicationName)\"", level: .warn)
                }
            }
        } catch {
            item.detection = .error(error.localizedDescription)
            DebugLog.shared.log("Detect \(bundleID) failed: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Per-item plist & metadata edits

    /// Reads an Info.plist file and applies its values to the item.
    /// Re-runs detection automatically — useful for `.pkg` / `.dmg`
    /// macOS packages where we can't auto-extract metadata.
    func setInfoPlist(for item: BatchUploadItem, url: URL) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }

        guard let parsed = InfoPlistExtractor.metadata(fromPlistAt: url) else {
            // The detailed reason was already logged by the extractor.
            // Make this surface in the row so the operator knows the
            // selection didn't help and can pick a different plist or
            // type the bundle ID manually.
            DebugLog.shared.log("Plist did not apply to \(item.displayFilename) (see preceding entries for cause)", level: .warn)
            return
        }
        // Apply only the fields the plist actually carries — leaves
        // any operator edits alone if the plist was missing a value.
        var appliedAny = false
        if !parsed.applicationName.isEmpty {
            item.metadata.applicationName  = parsed.applicationName
            appliedAny = true
        }
        if !parsed.bundleIdentifier.isEmpty {
            item.metadata.bundleIdentifier = parsed.bundleIdentifier
            appliedAny = true
        }
        if !parsed.versionShort.isEmpty {
            item.metadata.versionShort     = parsed.versionShort
            appliedAny = true
        }
        if !parsed.versionBuild.isEmpty {
            item.metadata.versionBuild     = parsed.versionBuild
            appliedAny = true
        }
        if appliedAny {
            DebugLog.shared.log("Plist applied to \(item.displayFilename) — bundle=\(item.metadata.bundleIdentifier) version=\(item.metadata.combinedVersion)", level: .info)
        } else {
            DebugLog.shared.log("Plist \(url.lastPathComponent) had no recognized CFBundle* fields — please fill the form fields manually.", level: .warn)
        }
        // Re-run detection if we now have a bundle ID.
        if !item.metadata.bundleIdentifier.isEmpty {
            redetect(item: item)
        }
    }

    /// Manually re-detect when the user edits the bundle ID directly.
    func bundleIDDidChange(for item: BatchUploadItem) {
        // Reset to undetermined so the row UI shows the spinner.
        item.detection = .undetermined
        redetect(item: item)
    }

    // MARK: - Per-item icon

    /// Stage a chosen icon file in the app sandbox so it survives the
    /// security-scoped URL going out of scope before upload.
    func setIcon(for item: BatchUploadItem, url: URL) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }

        let staging = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WS1Uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging,
                                                 withIntermediateDirectories: true)
        let staged = staging
            .appendingPathComponent("\(UUID().uuidString)-icon-\(url.lastPathComponent)")
        do {
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.copyItem(at: url, to: staged)
            item.iconFileURL  = staged
            item.iconFilename = url.lastPathComponent
            DebugLog.shared.log("Staged icon for \(item.displayFilename): \(url.lastPathComponent)", level: .info)
        } catch {
            DebugLog.shared.log("Failed to stage icon for \(item.displayFilename): \(error.localizedDescription)", level: .error)
        }
    }

    func clearIcon(for item: BatchUploadItem) {
        if let url = item.iconFileURL,
           url.path.contains("/WS1Uploads/") {
            try? FileManager.default.removeItem(at: url)
        }
        item.iconFileURL  = nil
        item.iconFilename = nil
    }

    // MARK: - Organization groups

    func loadAllOrganizationGroups(force: Bool = false) async {
        if isLoadingOGs { return }
        if !force && !allOrganizationGroups.isEmpty { return }
        isLoadingOGs = true
        ogLoadError  = nil
        ogLoadProgress = 0
        defer { isLoadingOGs = false }
        do {
            let client = try appState.makeClient()
            allOrganizationGroups = try await client.fetchAllOrganizationGroups(
                progress: { [weak self] count in
                    Task { @MainActor in self?.ogLoadProgress = count }
                }
            )
            if selectedOrganizationGroup == nil,
               appState.connection.organizationGroupID > 0,
               let match = allOrganizationGroups.first(where: {
                   $0.id == appState.connection.organizationGroupID
               }) {
                selectedOrganizationGroup = match
            }
        } catch {
            ogLoadError = error.localizedDescription
        }
    }

    // MARK: - Execution

    func runBatch() async {
        guard !isRunning else { return }
        guard let og = selectedOrganizationGroup else {
            lastError = "Pick a default Organization Group before starting the batch."
            return
        }
        isRunning = true
        lastError = nil
        defer { isRunning = false }

        DebugLog.shared.log("Batch run starting — \(items.count) items, OG=\(og.name)(\(og.id))", level: .info)

        for item in items {
            // Skip already completed items so re-runs are resumable.
            if item.status == .succeeded || item.status == .skipped { continue }
            await run(item: item, locationGroupID: og.id)
        }

        let s = succeededCount
        let f = failedCount
        summary = "Completed: \(s) succeeded, \(f) failed."
        DebugLog.shared.log("Batch finished — \(summary)", level: .info)
    }

    private func run(item: BatchUploadItem, locationGroupID: Int) async {
        item.status = .running
        item.statusMessage = "Authenticating…"
        item.progress = 0.0
        do {
            let client = try appState.makeClient()

            // Step 1 — optional icon upload.
            var iconUUID: String? = nil
            if let iconURL = item.iconFileURL {
                item.statusMessage = "Uploading custom icon…"
                iconUUID = try await client.uploadIcon(
                    fileURL: iconURL,
                    organizationGroupID: locationGroupID
                )
            }

            // Step 2 — chunked binary upload.
            item.statusMessage = "Uploading binary — \(item.formattedFileSize)"
            let transactionID = try await client.uploadChunks(
                fileURL: item.fileURL,
                progress: { [weak item] f in
                    Task { @MainActor in item?.progress = f * 0.8 }
                }
            )

            // Step 3 — create the application record.
            item.statusMessage = "Creating application record…"
            item.progress = 0.85
            let payload = makePayload(for: item,
                                      transactionID: transactionID,
                                      iconUUID: iconUUID,
                                      locationGroupID: locationGroupID)
            let created = try await client.createInternalApplication(payload: payload)
            item.createdWS1Id = created.ws1Id

            // Retire previous if this is an update and user opted in.
            if case .updatesExisting(let existing) = item.detection,
               item.settings.retirePreviousVersion {
                item.statusMessage = "Retiring previous version(s)…"
                item.progress = 0.92
                for prior in existing {
                    do {
                        try await client.retireApplication(appID: prior.ws1Id)
                        DebugLog.shared.log("Retired \(prior.applicationName) [\(prior.ws1Id)]", level: .info)
                    } catch {
                        DebugLog.shared.log("Retire failed for \(prior.applicationName): \(error.localizedDescription)", level: .warn)
                    }
                }
            }

            item.progress = 1.0
            item.status   = .succeeded
            item.statusMessage = "Uploaded — \(created.applicationName) \(item.metadata.combinedVersion)"

            UploadHistoryStore.shared.record(
                UploadActivity(
                    applicationName: item.metadata.applicationName,
                    version: item.metadata.combinedVersion,
                    bundleIdentifier: item.metadata.bundleIdentifier,
                    platform: item.metadata.platform,
                    outcome: .succeeded,
                    message: detectionDescription(for: item),
                    retiredVersionIDs: item.detection.existingApps.map(\.ws1Id)
                )
            )

        } catch {
            item.status        = .failed
            item.statusMessage = error.localizedDescription
            DebugLog.shared.log("Batch item failed \(item.displayFilename): \(error.localizedDescription)", level: .error)
            UploadHistoryStore.shared.record(
                UploadActivity(
                    applicationName: item.metadata.applicationName,
                    version: item.metadata.combinedVersion,
                    bundleIdentifier: item.metadata.bundleIdentifier,
                    platform: item.metadata.platform,
                    outcome: .failed,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func makePayload(for item: BatchUploadItem,
                             transactionID: String,
                             iconUUID: String?,
                             locationGroupID: Int) -> CreateApplicationPayload {
        let m = item.metadata
        let macosPlist: CreateApplicationPayload.MacOSInfoPlist? = {
            guard m.platform == .macOS else { return nil }
            return .init(bundleId: m.bundleIdentifier,
                         bundleVersion: m.versionBuild,
                         bundleShortVersion: m.versionShort,
                         isInstaller: ["pkg", "dmg"].contains(item.fileURL.pathExtension.lowercased()))
        }()

        // Apply management defaults to NEW apps only — for updates the
        // server preserves the prior version's management config.
        let isNew: Bool = {
            if case .newApp = item.detection { return true }
            return false
        }()

        // When uploading via /uploadchunk the server derives the
        // bundle ID and version from the binary itself.  Sending them
        // here triggers errorCode 6 from /begininstall, so leave them
        // nil; the custom encoder omits the keys entirely.
        return CreateApplicationPayload(
            applicationName: m.applicationName,
            bundleId: nil,
            appVersion: nil,
            buildVersion: nil,
            deviceType: m.platform.ws1DeviceType,
            transactionId: transactionID,
            fileName: item.originalFilename,
            locationGroupId: locationGroupID,
            supportedModels: .defaults(for: m.platform.ws1DeviceType),
            pushMode: "Auto",
            macOsInfoPlist: macosPlist,
            applicationDescription: item.settings.description.isEmpty ? nil : item.settings.description,
            uploadViaLink: false,
            autoUpdateVersion: true,
            enableProvisioning: false,
            isDependencyFile: false,
            isReimbursable: false,
            contentGatewayId: 0,
            iconBlobUuid: iconUUID,
            management: isNew ? item.settings.management : nil
        )
    }

    private func detectionDescription(for item: BatchUploadItem) -> String {
        switch item.detection {
        case .newApp:                       return "Created as a new application."
        case .updatesExisting(let apps):    return "Updated version replacing \(apps.count) prior."
        default:                            return ""
        }
    }
}
