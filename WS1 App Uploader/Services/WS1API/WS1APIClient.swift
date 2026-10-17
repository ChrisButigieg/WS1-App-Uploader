//
//  WS1APIClient.swift
//  WS1 App Uploader
//
//  Workspace ONE UEM REST client.  Endpoints are based on the public
//  Omnissa Mobile Application Management v1/v2 API.  All calls go
//  through `send(_:)` so authentication & errors are handled in one
//  place.
//

import Foundation

/// Public surface area used by view-models.
protocol WS1APIClientProtocol: Sendable {
    func testConnection() async throws
    func fetchAllOrganizationGroups(progress: @escaping @Sendable (Int) -> Void) async throws -> [OrganizationGroup]
    func searchApplicationsByBundleID(_ bundleID: String) async throws -> [WS1Application]
    func searchApplications(name: String?) async throws -> [WS1Application]
    func uploadChunks(fileURL: URL,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> String
    func uploadIcon(fileURL: URL,
                    organizationGroupID: Int) async throws -> String
    func createInternalApplication(payload: CreateApplicationPayload) async throws -> WS1Application
    func retireApplication(appID: Int) async throws
}

/// Concrete implementation backed by `URLSession`.
final class WS1APIClient: NSObject, WS1APIClientProtocol, @unchecked Sendable {

    private let baseURL: URL
    private let authenticator: WS1Authenticator
    private let session: URLSession

    init(connection: WS1Connection, authenticator: WS1Authenticator) throws {
        guard let url = URL(string: connection.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))) else {
            throw WS1Error.invalidURL(connection.apiBaseURL)
        }
        self.baseURL       = url
        self.authenticator = authenticator

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 60
        config.timeoutIntervalForResource = 60 * 30  // 30 min for large blobs
        config.httpAdditionalHeaders = ["Accept": "application/json;version=2"]

        self.session = URLSession(configuration: config,
                                  delegate: authenticator.sessionDelegate,
                                  delegateQueue: nil)
        super.init()
    }

    // MARK: - Connection test

    func testConnection() async throws {
        // `/system/info` returns a small payload describing the
        // console — perfect for verifying both reachability and auth.
        var request = try makeRequest(path: "/api/system/info", method: "GET")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        _ = try await send(request: request, expectedCodes: 200...299)
    }

    // MARK: - Organization groups

    /// Pulls every Organization Group from the tenant, paginating
    /// through `/api/system/groups/search` with a page size of 500.
    /// Reports each page as it arrives so the UI can show progress
    /// when tenants exceed thousands of OGs.
    func fetchAllOrganizationGroups(progress: @escaping @Sendable (Int) -> Void) async throws -> [OrganizationGroup] {
        var all: [OrganizationGroup] = []
        var page = 0
        let pageSize = 500

        while true {
            var components = URLComponents()
            components.path = "/api/system/groups/search"
            components.queryItems = [
                URLQueryItem(name: "pagesize", value: "\(pageSize)"),
                URLQueryItem(name: "page",     value: "\(page)"),
                URLQueryItem(name: "orderby",  value: "name")
            ]
            let request = try makeRequest(pathComponents: components, method: "GET")
            let data = try await send(request: request, expectedCodes: 200...299)

            let pageGroups = decodeGroupsResponse(data)
            if pageGroups.isEmpty { break }
            all.append(contentsOf: pageGroups)
            progress(all.count)

            // Stop when we got fewer than a full page back.
            if pageGroups.count < pageSize { break }
            page += 1

            // Safety cap — break runaway loops in misbehaving consoles.
            if page > 100 { break }
        }
        return all
    }

    private func decodeGroupsResponse(_ data: Data) -> [OrganizationGroup] {
        // Envelope variants observed across WS1 versions:
        //   { "LocationGroups": [...] }        — v1 PascalCase
        //   { "OrganizationGroups": [...] }    — newer PascalCase
        //   { "organization_groups": [...] }   — v2 snake_case
        //   { "location_groups": [...] }       — v2 snake_case
        //   [...]                              — bare array
        struct EnvelopeA: Decodable { let LocationGroups: [OrganizationGroup]? }
        struct EnvelopeB: Decodable { let OrganizationGroups: [OrganizationGroup]? }
        struct EnvelopeC: Decodable { let organization_groups: [OrganizationGroup]? }
        struct EnvelopeD: Decodable { let location_groups: [OrganizationGroup]? }
        if let env = try? JSONDecoder().decode(EnvelopeA.self, from: data),
           let groups = env.LocationGroups, !groups.isEmpty { return groups }
        if let env = try? JSONDecoder().decode(EnvelopeB.self, from: data),
           let groups = env.OrganizationGroups, !groups.isEmpty { return groups }
        if let env = try? JSONDecoder().decode(EnvelopeC.self, from: data),
           let groups = env.organization_groups, !groups.isEmpty { return groups }
        if let env = try? JSONDecoder().decode(EnvelopeD.self, from: data),
           let groups = env.location_groups, !groups.isEmpty { return groups }
        return (try? JSONDecoder().decode([OrganizationGroup].self, from: data)) ?? []
    }

    // MARK: - Applications

    /// Searches internal applications.  Restricted to `Active` apps
    /// (so retired versions don't crowd the library) and uses
    /// `applicationtype=Internal` so public-app records are excluded.
    func searchApplications(name: String?) async throws -> [WS1Application] {
        var components = URLComponents()
        components.path = "/api/mam/apps/search"
        components.queryItems = [
            URLQueryItem(name: "applicationtype", value: "Internal"),
            URLQueryItem(name: "status",          value: "Active"),
            URLQueryItem(name: "pagesize",        value: "500")
        ]
        if let name, !name.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "applicationname", value: name))
        }
        let request = try makeRequest(pathComponents: components, method: "GET")
        let data = try await send(request: request, expectedCodes: 200...299)
        return decodeApplicationsResponse(data)
    }

    func searchApplicationsByBundleID(_ bundleID: String) async throws -> [WS1Application] {
        var components = URLComponents()
        components.path = "/api/mam/apps/search"
        components.queryItems = [
            URLQueryItem(name: "applicationtype", value: "Internal"),
            URLQueryItem(name: "bundleid",        value: bundleID),
            URLQueryItem(name: "pagesize",        value: "100")
        ]
        let request = try makeRequest(pathComponents: components, method: "GET")
        let data = try await send(request: request, expectedCodes: 200...299)
        return decodeApplicationsResponse(data)
    }

    private func decodeApplicationsResponse(_ data: Data) -> [WS1Application] {
        // Envelope variants:
        //   { "Application": [...] }            — v1 PascalCase
        //   { "InternalApplications": [...] }   — alt PascalCase
        //   { "applications": [...] }           — v2 snake_case
        //   { "internal_applications": [...] }  — alt snake_case
        //   [...]                                — bare array
        struct EnvelopeA: Decodable { let Application: [WS1Application]? }
        struct EnvelopeB: Decodable { let InternalApplications: [WS1Application]? }
        struct EnvelopeC: Decodable { let applications: [WS1Application]? }
        struct EnvelopeD: Decodable { let internal_applications: [WS1Application]? }
        if let env = try? JSONDecoder().decode(EnvelopeA.self, from: data),
           let apps = env.Application, !apps.isEmpty { return apps }
        if let env = try? JSONDecoder().decode(EnvelopeB.self, from: data),
           let apps = env.InternalApplications, !apps.isEmpty { return apps }
        if let env = try? JSONDecoder().decode(EnvelopeC.self, from: data),
           let apps = env.applications, !apps.isEmpty { return apps }
        if let env = try? JSONDecoder().decode(EnvelopeD.self, from: data),
           let apps = env.internal_applications, !apps.isEmpty { return apps }
        return (try? JSONDecoder().decode([WS1Application].self, from: data)) ?? []
    }

    // MARK: - Chunked binary upload  (POST /api/mam/apps/internal/uploadchunk)

    /// Uploads the application binary in 20 MiB base64-encoded JSON
    /// chunks and returns the **TransactionId** (GUID) reported by the
    /// final chunk response.  The TransactionId is what
    /// `/begininstall` expects in place of the legacy `BlobId`.
    ///
    /// WS1's response field is misspelled — `TranscationId` (one `s`)
    /// — so we accept either spelling defensively.
    func uploadChunks(fileURL: URL,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> String {

        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw WS1Error.fileUnreadable(fileURL)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let totalSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard totalSize > 0 else {
            throw WS1Error.fileUnreadable(fileURL)
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let chunkSize: Int = 20 * 1024 * 1024   // 20 MiB
        let totalChunks = Int((totalSize + Int64(chunkSize) - 1) / Int64(chunkSize))
        var transactionId  = ""
        var sequenceNumber = 1
        var offset: Int64  = 0
        progress(0)

        DebugLog.write("Chunked upload begin — \(fileURL.lastPathComponent), \(totalSize) bytes in \(totalChunks) chunk(s) of \(chunkSize) max", level: .info)

        while offset < totalSize {
            try handle.seek(toOffset: UInt64(offset))
            let toRead = Int(min(Int64(chunkSize), totalSize - offset))
            guard let chunk = try handle.read(upToCount: toRead), !chunk.isEmpty else {
                throw WS1Error.fileUnreadable(fileURL)
            }

            let body: [String: Any] = [
                "TransactionId":        transactionId,
                "ChunkData":            chunk.base64EncodedString(),
                "ChunkSequenceNumber":  sequenceNumber,
                "TotalApplicationSize": totalSize,
                "ChunkSize":            chunk.count
            ]
            let json = try JSONSerialization.data(withJSONObject: body, options: [])

            var request = try makeRequest(path: "/api/mam/apps/internal/uploadchunk",
                                          method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = json

            DebugLog.write("Chunk \(sequenceNumber)/\(totalChunks): sending \(chunk.count) bytes with TransactionId=\(transactionId.isEmpty ? "(empty — first chunk)" : transactionId)", level: .info)

            let data = try await send(request: request,
                                      expectedCodes: 200...299,
                                      bodyForAuth: json)

            // Extract the TransactionId — the canonical field is
            // misspelled `TranscationId` (one s); try every variant.
            let parsedID = Self.parseTransactionId(from: data)
            if let id = parsedID, !id.isEmpty {
                if id != transactionId {
                    DebugLog.write("Chunk \(sequenceNumber): server returned TransactionId=\(id)", level: .info)
                }
                transactionId = id
            } else {
                // Empty / unparsable response — fail fast on the first
                // chunk because the next call would have nothing to
                // send.  For subsequent chunks, log a warning but
                // continue (the server occasionally returns the ID
                // only on the first or final call).
                let preview = String(data: data, encoding: .utf8) ?? "(non-utf8 \(data.count) bytes)"
                if transactionId.isEmpty {
                    throw WS1Error.decoding("uploadchunk chunk \(sequenceNumber) returned no TransactionId. Response body: \(preview.prefix(500))")
                } else {
                    DebugLog.write("Chunk \(sequenceNumber): response carried no TransactionId; continuing with cached value \(transactionId). Body: \(preview.prefix(200))", level: .warn)
                }
            }

            offset += Int64(chunk.count)
            sequenceNumber += 1
            progress(Double(offset) / Double(totalSize))
        }

        guard !transactionId.isEmpty else {
            throw WS1Error.decoding("uploadchunk did not return a TransactionId across any of the \(totalChunks) chunk(s).")
        }
        DebugLog.write("Chunked upload complete — final TransactionId=\(transactionId) (after \(totalChunks) chunk(s))", level: .info)
        return transactionId
    }

    /// Pulls the `TransactionId` out of an /uploadchunk response,
    /// trying every documented and observed field-name variant.
    /// WS1's canonical spelling is the misspelled `TranscationId`
    /// (one `s`).  Some console versions wrap the response in a
    /// `d` or `Result` envelope — we handle both.
    private static func parseTransactionId(from data: Data) -> String? {
        struct Direct: Decodable {
            let TranscationId: String?   // sic — WS1's misspelling
            let TransactionId: String?
            let transcation_id: String?
            let transaction_id: String?
        }
        if let r = try? JSONDecoder().decode(Direct.self, from: data) {
            if let id = r.TranscationId ?? r.TransactionId ?? r.transcation_id ?? r.transaction_id,
               !id.isEmpty {
                return id
            }
        }
        struct Wrapped: Decodable {
            let d:      Direct?
            let Result: Direct?
            let result: Direct?
            let Value:  Direct?
        }
        if let w = try? JSONDecoder().decode(Wrapped.self, from: data) {
            for inner in [w.d, w.Result, w.result, w.Value] {
                if let r = inner,
                   let id = r.TranscationId ?? r.TransactionId ?? r.transcation_id ?? r.transaction_id,
                   !id.isEmpty {
                    return id
                }
            }
        }
        // Last resort — search any string-valued top-level key whose
        // name (case-insensitive, dashes / underscores stripped) is
        // some variant of "transactionid".
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in json {
                let normalized = key.lowercased()
                                     .replacingOccurrences(of: "_", with: "")
                                     .replacingOccurrences(of: "-", with: "")
                if (normalized == "transactionid" || normalized == "transcationid"),
                   let v = value as? String, !v.isEmpty {
                    return v
                }
            }
        }
        return nil
    }

    // MARK: - Icon upload  (POST /api/mam/blobs/uploadblob)

    /// Uploads an image and returns the blob's `uuid` to use as
    /// `IconBlobUuid` on `begininstall`.  Body is raw octet-stream.
    func uploadIcon(fileURL: URL,
                    organizationGroupID: Int) async throws -> String {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw WS1Error.fileUnreadable(fileURL)
        }
        let bytes = try Data(contentsOf: fileURL)

        var components = URLComponents()
        components.path = "/api/mam/blobs/uploadblob"
        components.queryItems = [
            URLQueryItem(name: "filename",            value: fileURL.lastPathComponent),
            URLQueryItem(name: "organizationgroupid", value: "\(organizationGroupID)"),
            URLQueryItem(name: "moduleType",          value: "Application")
        ]
        var request = try makeRequest(pathComponents: components, method: "POST")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json",         forHTTPHeaderField: "Accept")
        request.httpBody = bytes

        let data = try await send(request: request,
                                  expectedCodes: 200...299,
                                  bodyForAuth: bytes)

        struct IconResponse: Decodable {
            let uuid: String?
            let Uuid: String?
            let UUID: String?
            let Value: String?    // some tenants nest it as {"Value":"…"}
        }
        if let r = try? JSONDecoder().decode(IconResponse.self, from: data),
           let id = r.uuid ?? r.Uuid ?? r.UUID ?? r.Value, !id.isEmpty {
            DebugLog.write("Icon uploaded — uuid=\(id)", level: .info)
            return id
        }
        throw WS1Error.decoding("uploadblob (icon) did not return a uuid")
    }

    // MARK: - Create internal application

    func createInternalApplication(payload: CreateApplicationPayload) async throws -> WS1Application {
        let body = try JSONEncoder().encode(payload)

        // Try save paths in order — `/begininstall` is the current
        // (TransactionId-based) entry point per the Omnissa API
        // reference; the v1 path lives at `/api/v1/mam/…`.  Older
        // consoles also expose `/api/mam/apps/internal/save`, and
        // pre-22.x macOS consoles route through `/macos/save`.  Any
        // 404 advances to the next candidate.
        let candidatePaths: [String]
        switch payload.deviceType {
        case "AppleOsX":
            candidatePaths = [
                "/api/v1/mam/apps/internal/begininstall",
                "/api/mam/apps/internal/begininstall",
                "/api/mam/apps/internal/save",
                "/api/mam/apps/internal/macos/save"
            ]
        default:
            candidatePaths = [
                "/api/v1/mam/apps/internal/begininstall",
                "/api/mam/apps/internal/begininstall",
                "/api/mam/apps/internal/save"
            ]
        }

        var lastError: Error?
        for path in candidatePaths {
            var request = try makeRequest(path: path, method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            do {
                let data = try await send(request: request,
                                          expectedCodes: 200...299,
                                          bodyForAuth: body)
                return decodeCreatedApplication(data, fallbackPayload: payload)
            } catch let e as WS1Error {
                if case .httpStatus(let code, _) = e, code == 404 {
                    lastError = e
                    continue  // try the next candidate path
                }
                throw e
            } catch {
                throw error
            }
        }
        throw lastError ?? WS1Error.generic("Application save endpoint not found on this tenant.")
    }

    private func decodeCreatedApplication(_ data: Data,
                                          fallbackPayload payload: CreateApplicationPayload) -> WS1Application {
        if let app = try? JSONDecoder().decode(WS1Application.self, from: data) {
            return app
        }
        struct EnvelopeA: Decodable { let ApplicationId: WS1Application? }
        struct EnvelopeB: Decodable { let Id: Int? }
        if let env = try? JSONDecoder().decode(EnvelopeA.self, from: data),
           let app = env.ApplicationId {
            return app
        }
        if let env = try? JSONDecoder().decode(EnvelopeB.self, from: data),
           let id = env.Id {
            return WS1Application(ws1Id: id,
                                  applicationName: payload.applicationName,
                                  bundleIdentifier: payload.bundleId ?? "",
                                  appVersion: payload.appVersion ?? "",
                                  platform: payload.deviceType,
                                  status: "Active")
        }
        return WS1Application(ws1Id: 0,
                              applicationName: payload.applicationName,
                              bundleIdentifier: payload.bundleId ?? "",
                              appVersion: payload.appVersion ?? "",
                              platform: payload.deviceType,
                              status: "Active")
    }

    // MARK: - Retire application

    func retireApplication(appID: Int) async throws {
        let request = try makeRequest(path: "/api/mam/apps/internal/\(appID)/retire", method: "POST")
        _ = try await send(request: request, expectedCodes: 200...299)
    }

    // MARK: - Request building & sending

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw WS1Error.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func makeRequest(pathComponents components: URLComponents, method: String) throws -> URLRequest {
        var base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        base.path  = components.path
        base.queryItems = components.queryItems
        guard let url = base.url else { throw WS1Error.invalidURL(components.path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    @discardableResult
    private func send(request: URLRequest,
                      expectedCodes: ClosedRange<Int>,
                      bodyForAuth: Data? = nil) async throws -> Data {
        var authorized = request
        do {
            try await authenticator.authorize(&authorized, bodyBytes: bodyForAuth ?? request.httpBody)
        } catch let e as WS1Error {
            throw e
        } catch {
            throw WS1Error.authenticationFailed(error.localizedDescription)
        }

        let method = authorized.httpMethod ?? "GET"
        let urlString = authorized.url?.absoluteString ?? "(nil)"
        DebugLog.write("→ \(method) \(urlString)", level: .api)

        do {
            let (data, response) = try await session.data(for: authorized)
            guard let http = response as? HTTPURLResponse else {
                DebugLog.write("← \(urlString) : no HTTPURLResponse", level: .error)
                throw WS1Error.generic("No HTTP response from server")
            }
            let bodyText = String(data: data, encoding: .utf8) ?? "(non-utf8 \(data.count) bytes)"
            let snippet = bodyText.count > 1500
                ? String(bodyText.prefix(1500)) + "… [\(bodyText.count - 1500) more bytes]"
                : bodyText
            let level: DebugLog.Level = expectedCodes.contains(http.statusCode) ? .api : .error
            DebugLog.write("← \(http.statusCode) \(urlString)\n\(snippet)", level: level)

            if !expectedCodes.contains(http.statusCode) {
                throw WS1Error.httpStatus(http.statusCode, bodyText)
            }
            return data
        } catch let e as URLError {
            DebugLog.write("× \(urlString) URLError code=\(e.code.rawValue): \(e.localizedDescription)", level: .error)
            throw WS1Error.transport(e)
        } catch let e as WS1Error {
            throw e
        } catch {
            DebugLog.write("× \(urlString) error: \(error.localizedDescription)", level: .error)
            throw WS1Error.generic(error.localizedDescription)
        }
    }
}

// MARK: - Create Application Payload

/// Payload for `/api/v1/mam/apps/internal/begininstall`.  Includes
/// every field documented in the Omnissa API reference for the
/// chunked-upload flow; unused fields are quietly ignored by older
/// console versions, so we can safely send the superset.
struct CreateApplicationPayload: Encodable {
    let applicationName: String

    /// Bundle ID / version are **derived from the binary** by WS1
    /// when uploading via chunks (`UploadViaLink = false`).  Sending
    /// them here triggers
    ///   `errorCode 6: "UploadViaLink should be true when bundle id or
    ///   actual file version is passed"`
    /// from `/begininstall`.  We retain the fields so that future
    /// support for the URL-fetch flow can populate them, but for the
    /// chunked-upload path they must remain `nil` and be omitted
    /// from the JSON entirely.
    let bundleId: String?
    let appVersion: String?
    let buildVersion: String?

    let deviceType: String
    /// GUID returned by the final `uploadchunk` response.  Required
    /// by `/begininstall`.  Replaces the legacy numeric `BlobId`.
    let transactionId: String
    /// Original filename with extension (e.g. `calculator.ipa`).
    /// Required by `/begininstall` whenever `TransactionId` is sent —
    /// the server uses it to validate the extension and store the
    /// binary under a meaningful name.  Without it the API returns
    /// `errorCode 7008 "File name with valid extension is required
    /// when Transaction Id is passed."`
    let fileName: String?
    let locationGroupId: Int
    let supportedModels: SupportedModels?
    let pushMode: String
    let macOsInfoPlist: MacOSInfoPlist?
    let applicationDescription: String?

    /// `false` = binary already uploaded via /uploadchunk (default).
    /// `true`  = WS1 fetches the binary from `FileLink`.
    let uploadViaLink: Bool

    /// Auto-push new versions to devices already running the app.
    let autoUpdateVersion: Bool
    /// Used by product-provisioning workflows.  Almost always
    /// `false` for standard app deployment.
    let enableProvisioning: Bool
    /// `true` if this binary is a framework / dependency rather than
    /// a standalone application.
    let isDependencyFile: Bool
    /// VPP / cost-tracking flag — `false` for typical USAF use.
    let isReimbursable: Bool
    /// `0` = direct delivery; set to your Content Gateway ID when
    /// routing through SEG / EIS.
    let contentGatewayId: Int

    /// UUID of an app icon previously uploaded via
    /// `/api/mam/blobs/uploadblob`.  Optional — if omitted the
    /// console derives an icon from the bundle when possible.
    let iconBlobUuid: String?

    /// Management defaults applied when creating a new internal app.
    let management: ManagementSettings?

    /// Custom encoder so optional fields are **omitted** rather than
    /// emitted as `null`.  This matters specifically for `BundleId`
    /// and `AppVersion`, which `/begininstall` rejects with
    /// `errorCode 6` if either appears in the payload while
    /// `UploadViaLink = false`.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(applicationName,                 forKey: .applicationName)
        try c.encodeIfPresent(bundleId,               forKey: .bundleId)
        try c.encodeIfPresent(appVersion,             forKey: .appVersion)
        try c.encodeIfPresent(buildVersion,           forKey: .buildVersion)
        try c.encode(deviceType,                      forKey: .deviceType)
        try c.encode(transactionId,                   forKey: .transactionId)
        try c.encodeIfPresent(fileName,               forKey: .fileName)
        try c.encode(locationGroupId,                 forKey: .locationGroupId)
        try c.encodeIfPresent(supportedModels,        forKey: .supportedModels)
        try c.encode(pushMode,                        forKey: .pushMode)
        try c.encodeIfPresent(macOsInfoPlist,         forKey: .macOsInfoPlist)
        try c.encodeIfPresent(applicationDescription, forKey: .applicationDescription)
        try c.encode(uploadViaLink,                   forKey: .uploadViaLink)
        try c.encode(autoUpdateVersion,               forKey: .autoUpdateVersion)
        try c.encode(enableProvisioning,              forKey: .enableProvisioning)
        try c.encode(isDependencyFile,                forKey: .isDependencyFile)
        try c.encode(isReimbursable,                  forKey: .isReimbursable)
        try c.encode(contentGatewayId,                forKey: .contentGatewayId)
        try c.encodeIfPresent(iconBlobUuid,           forKey: .iconBlobUuid)
        try c.encodeIfPresent(management,             forKey: .management)
    }

    struct SupportedModels: Encodable {
        struct Model: Encodable {
            let modelName: String
            let modelId: Int

            enum CodingKeys: String, CodingKey {
                case modelName = "ModelName"
                case modelId   = "ModelId"
            }
        }
        let model: [Model]?
        enum CodingKeys: String, CodingKey { case model = "Model" }

        /// Sensible defaults per WS1 `DeviceType`.  These IDs are the
        /// well-known canonical entries in stock WS1 / Omnissa
        /// tenants.  Sent so the `/begininstall` endpoint doesn't
        /// reject the payload with "Supported model list cannot be
        /// empty".  Operators with custom model registries can
        /// override per-item if needed.
        static func defaults(for deviceType: String) -> SupportedModels? {
            switch deviceType {
            case "Apple":     // iOS / iPadOS
                return .init(model: [
                    .init(modelName: "iPhone",     modelId: 2),
                    .init(modelName: "iPad",       modelId: 1),
                    .init(modelName: "iPod Touch", modelId: 3)
                ])
            case "AppleOsX":  // macOS
                return .init(model: [
                    .init(modelName: "MacBook Pro", modelId: 14),
                    .init(modelName: "MacBook Air", modelId: 15),
                    .init(modelName: "Mac Mini",    modelId: 16),
                    .init(modelName: "iMac",        modelId: 30),
                    .init(modelName: "Mac Pro",     modelId: 31),
                    .init(modelName: "MacBook",     modelId: 35),
                    .init(modelName: "Mac Studio",  modelId: 113)
                ])
            case "Android":
                return .init(model: [
                    .init(modelName: "Android", modelId: 5)
                ])
            case "WinRT":
                return .init(model: [
                    .init(modelName: "Windows", modelId: 12)
                ])
            default:
                return nil
            }
        }
    }

    struct MacOSInfoPlist: Encodable {
        let bundleId: String
        let bundleVersion: String
        let bundleShortVersion: String
        let isInstaller: Bool

        enum CodingKeys: String, CodingKey {
            case bundleId           = "BundleId"
            case bundleVersion      = "BundleVersion"
            case bundleShortVersion = "BundleShortVersion"
            case isInstaller        = "IsInstaller"
        }
    }

    struct ManagementSettings: Encodable, Hashable, Sendable {
        var preventBackup: Bool                = true
        var removeOnUnenroll: Bool             = true
        var takeManagementOfUserInstalled: Bool = true

        static let standard = ManagementSettings()

        enum CodingKeys: String, CodingKey {
            case preventBackup                  = "PreventApplicationBackup"
            case removeOnUnenroll               = "RemoveOnUnEnroll"
            case takeManagementOfUserInstalled  = "ManagedAccessControl"
        }
    }

    enum CodingKeys: String, CodingKey {
        case applicationName        = "ApplicationName"
        case bundleId               = "BundleId"
        case appVersion             = "AppVersion"
        case buildVersion           = "BuildVersion"
        case deviceType             = "DeviceType"
        case transactionId          = "TransactionId"
        case fileName               = "FileName"
        case locationGroupId        = "LocationGroupId"
        case supportedModels        = "SupportedModels"
        case pushMode               = "PushMode"
        case macOsInfoPlist         = "MacOsInfoPlist"
        case applicationDescription = "Description"
        case uploadViaLink          = "UploadViaLink"
        case autoUpdateVersion      = "AutoUpdateVersion"
        case enableProvisioning     = "EnableProvisioning"
        case isDependencyFile       = "IsDependencyFile"
        case isReimbursable         = "IsReimbursable"
        case contentGatewayId       = "ContentGatewayId"
        case iconBlobUuid           = "IconBlobUuid"
        case management             = "ApplicationParameters"
    }
}
