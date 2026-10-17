//
//  OrganizationGroup.swift
//  WS1 App Uploader
//

import Foundation

// MARK: - Dynamic Coding Key

/// CodingKey backed by a string — lets us look up arbitrary JSON field
/// names at decode time, which is essential when a single endpoint can
/// return either PascalCase (`ApplicationName`) or snake_case
/// (`application_name`) depending on console version and Accept header.
struct AnyKey: CodingKey {
    let stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

// MARK: - Multi-alias helpers

enum WS1Decoding {

    static func int(in container: KeyedDecodingContainer<AnyKey>,
                    aliases: [String]) -> Int? {
        for name in aliases {
            let key = AnyKey(stringValue: name)
            if let flat = try? container.decode(Int.self, forKey: key) {
                return flat
            }
            if let env = try? container.decode(WS1ValueEnvelope.self, forKey: key),
               let v = env.Value {
                return v
            }
            if let s = try? container.decode(String.self, forKey: key),
               let n = Int(s) {
                return n
            }
        }
        return nil
    }

    static func string(in container: KeyedDecodingContainer<AnyKey>,
                       aliases: [String]) -> String? {
        for name in aliases {
            let key = AnyKey(stringValue: name)
            if let s = try? container.decode(String.self, forKey: key), !s.isEmpty {
                return s
            }
            // Some WS1 endpoints wrap names in `{ "Value": Int, "Name": String }`
            if let env = try? container.decode(WS1NameEnvelope.self, forKey: key),
               let n = env.Name, !n.isEmpty {
                return n
            }
        }
        return nil
    }
}

/// `{ "Value": 12345 }` envelope used for IDs.
struct WS1ValueEnvelope: Decodable {
    let Value: Int?
}

/// `{ "Value": 12345, "Name": "…" }` envelope used for IDs+display.
struct WS1NameEnvelope: Decodable {
    let Value: Int?
    let Name: String?
}

// MARK: - OrganizationGroup

/// Workspace ONE UEM organization group.  Accepts both PascalCase
/// (`Id`, `Name`) and snake_case (`id`, `name`) responses.
struct OrganizationGroup: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let groupId: String?
    let locationGroupType: String?

    init(id: Int, name: String, groupId: String?, locationGroupType: String?) {
        self.id = id
        self.name = name
        self.groupId = groupId
        self.locationGroupType = locationGroupType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id                = WS1Decoding.int(in: c, aliases: ["Id", "id", "organization_group_id"]) ?? 0
        self.name              = WS1Decoding.string(in: c, aliases: ["Name", "name", "organization_group_name"]) ?? ""
        self.groupId           = WS1Decoding.string(in: c, aliases: ["GroupId", "group_id"])
        self.locationGroupType = WS1Decoding.string(in: c, aliases: ["LocationGroupType", "location_group_type"])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(id,   forKey: AnyKey(stringValue: "Id"))
        try c.encode(name, forKey: AnyKey(stringValue: "Name"))
        if let groupId           { try c.encode(groupId,           forKey: AnyKey(stringValue: "GroupId")) }
        if let locationGroupType { try c.encode(locationGroupType, forKey: AnyKey(stringValue: "LocationGroupType")) }
    }
}

// MARK: - SmartGroupAssignment

/// Lightweight reference to a smart group an app is assigned to.
struct SmartGroupAssignment: Hashable, Codable, Sendable {
    let name: String
    let uuid: String?

    init(name: String, uuid: String?) {
        self.name = name
        self.uuid = uuid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.name = WS1Decoding.string(in: c, aliases: ["Name", "name", "smart_group_name"]) ?? ""
        self.uuid = WS1Decoding.string(in: c, aliases: ["Uuid", "uuid", "smart_group_uuid"])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(name, forKey: AnyKey(stringValue: "Name"))
        if let uuid { try c.encode(uuid, forKey: AnyKey(stringValue: "Uuid")) }
    }
}

// MARK: - WS1Application

/// Lightweight description of an internal application already present
/// in the tenant.  Tolerates both PascalCase and snake_case responses
/// across endpoint versions.
///
/// `id` is a **client-side stable identifier** computed at decode time
/// from whichever real WS1 IDs / UUIDs we can find — so SwiftUI's
/// `ForEach` always renders every row, even if the upstream `id`
/// field is missing or all rows accidentally share the value `0`.
/// The original WS1 numeric ID (used for retire / status operations)
/// is preserved in `ws1Id`.
struct WS1Application: Identifiable, Hashable, Codable, Sendable {

    /// Stable identifier for SwiftUI — never `0`.
    let id: String
    /// The numeric WS1 application ID, used by retire / status calls.
    /// Zero when the endpoint didn't return one.
    let ws1Id: Int

    let applicationName: String
    let bundleIdentifier: String
    let appVersion: String
    let platform: String?
    let status: String?

    // Extended fields surfaced in the App Library UI.
    let organizationGroupName: String?
    let assignmentStatus: String?
    let smartGroups: [SmartGroupAssignment]
    let assignedDeviceCount: Int
    let installedDeviceCount: Int
    let notInstalledDeviceCount: Int

    init(id: String? = nil,
         ws1Id: Int = 0,
         applicationName: String,
         bundleIdentifier: String,
         appVersion: String,
         platform: String?,
         status: String?,
         organizationGroupName: String? = nil,
         assignmentStatus: String? = nil,
         smartGroups: [SmartGroupAssignment] = [],
         assignedDeviceCount: Int = 0,
         installedDeviceCount: Int = 0,
         notInstalledDeviceCount: Int = 0) {
        self.id = id ?? Self.deriveStableID(
            ws1Id: ws1Id,
            bundleIdentifier: bundleIdentifier,
            appVersion: appVersion,
            applicationName: applicationName
        )
        self.ws1Id                 = ws1Id
        self.applicationName       = applicationName
        self.bundleIdentifier      = bundleIdentifier
        self.appVersion            = appVersion
        self.platform              = platform
        self.status                = status
        self.organizationGroupName = organizationGroupName
        self.assignmentStatus      = assignmentStatus
        self.smartGroups           = smartGroups
        self.assignedDeviceCount   = assignedDeviceCount
        self.installedDeviceCount  = installedDeviceCount
        self.notInstalledDeviceCount = notInstalledDeviceCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)

        let ws1Id = WS1Decoding.int(in: c, aliases: [
            "Id", "id", "application_id", "ApplicationId",
            "applicationId", "applicationid"
        ]) ?? 0

        let applicationName = WS1Decoding.string(in: c, aliases: [
            "ApplicationName", "application_name", "name", "Name"
        ]) ?? ""

        let bundleIdentifier = WS1Decoding.string(in: c, aliases: [
            "BundleId", "bundle_id", "BundleIdentifier", "bundle_identifier"
        ]) ?? ""

        let v = WS1Decoding.string(in: c, aliases: [
            "AppVersion", "application_version", "app_version",
            "ActualFileVersion", "actual_file_version"
        ]) ?? ""

        let platform = WS1Decoding.string(in: c, aliases: [
            "Platform", "platform"
        ])

        let status = WS1Decoding.string(in: c, aliases: [
            "Status", "status"
        ])

        let assignmentStatus = WS1Decoding.string(in: c, aliases: [
            "AssignmentStatus", "assignment_status"
        ])

        let organizationGroupName = WS1Decoding.string(in: c, aliases: [
            "RootOrganizationGroupName", "root_organization_group_name",
            "OrganizationGroupName",     "organization_group_name",
            "LocationGroupName",         "location_group_name"
        ])

        // Optional collections — try the obvious shapes, swallow errors.
        let smartGroups = Self.decodeSmartGroups(container: c)

        let assignedDeviceCount = WS1Decoding.int(in: c, aliases: [
            "AssignedDeviceCount", "assigned_device_count"
        ]) ?? 0
        let installedDeviceCount = WS1Decoding.int(in: c, aliases: [
            "InstalledDeviceCount", "installed_device_count"
        ]) ?? 0
        let notInstalledDeviceCount = WS1Decoding.int(in: c, aliases: [
            "NotInstalledDeviceCount", "not_installed_device_count"
        ]) ?? 0

        // UUID-bearing fields make for excellent stable IDs.
        let uuid = WS1Decoding.string(in: c, aliases: [
            "Uuid", "uuid", "application_uuid", "ApplicationUuid"
        ])

        self.ws1Id                  = ws1Id
        self.applicationName        = applicationName
        self.bundleIdentifier       = bundleIdentifier
        self.appVersion             = v
        self.platform               = platform
        self.status                 = status
        self.organizationGroupName  = organizationGroupName
        self.assignmentStatus       = assignmentStatus
        self.smartGroups            = smartGroups
        self.assignedDeviceCount    = assignedDeviceCount
        self.installedDeviceCount   = installedDeviceCount
        self.notInstalledDeviceCount = notInstalledDeviceCount

        // Stable client-side ID.  Preference order:
        //   uuid → ws1Id → bundle+version → fallback uuid.
        if let uuid, !uuid.isEmpty {
            self.id = "uuid:" + uuid
        } else if ws1Id > 0 {
            self.id = "ws1:\(ws1Id)"
        } else if !bundleIdentifier.isEmpty {
            self.id = "bv:\(bundleIdentifier):\(v)"
        } else {
            self.id = "rnd:" + UUID().uuidString
        }
    }

    private static func decodeSmartGroups(container c: KeyedDecodingContainer<AnyKey>) -> [SmartGroupAssignment] {
        // Variant 1: `smart_groups`: [SmartGroupAssignment]
        for name in ["smart_groups", "SmartGroups"] {
            if let arr = try? c.decode([SmartGroupAssignment].self, forKey: AnyKey(stringValue: name)) {
                return arr
            }
        }
        // Variant 2: `Assignments`: { Assignment: [...] }
        return []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(ws1Id,            forKey: AnyKey(stringValue: "Id"))
        try c.encode(applicationName,  forKey: AnyKey(stringValue: "ApplicationName"))
        try c.encode(bundleIdentifier, forKey: AnyKey(stringValue: "BundleId"))
        try c.encode(appVersion,       forKey: AnyKey(stringValue: "AppVersion"))
        if let platform { try c.encode(platform, forKey: AnyKey(stringValue: "Platform")) }
        if let status   { try c.encode(status,   forKey: AnyKey(stringValue: "Status")) }
    }

    private static func deriveStableID(ws1Id: Int,
                                       bundleIdentifier: String,
                                       appVersion: String,
                                       applicationName: String) -> String {
        if ws1Id > 0 { return "ws1:\(ws1Id)" }
        if !bundleIdentifier.isEmpty { return "bv:\(bundleIdentifier):\(appVersion)" }
        if !applicationName.isEmpty  { return "nm:\(applicationName)" }
        return "rnd:" + UUID().uuidString
    }

    /// Maps WS1's many platform strings to our enum.
    var platformType: PlatformType {
        switch platform?.lowercased() {
        case "apple", "ios", "ipados":
            return .iOS
        case "appleosx", "apple_os_x", "apple-osx", "macos", "osx":
            return .macOS
        case "android":
            return .android
        case "winrt", "windows", "windows_phone", "windows_rt", "winpc":
            return .windows
        default:
            return .unknown
        }
    }
}
