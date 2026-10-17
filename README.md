# WS1 App Uploader

Mission Mobile companion app for **Air Force Reserve** administrators
who manage internal applications inside an **Omnissa Workspace ONE UEM**
tenant.  Built as a native, multiplatform SwiftUI application targeting
**iPadOS 18+** and **macOS 15+**.

---

## Features

- Modern, professional UI with Air Force blue branding and dark-mode default.
- Secure credential storage in the device Keychain.
- Three supported authentication modes:
  - Basic + `aw-tenant-code`
  - OAuth 2.0 client-credentials
  - p12 client certificate with **CMSURL** header signing
- Drag-and-drop file selection on macOS, sandboxed file-importer on
  iPadOS.
- Automatic platform detection (iOS / macOS / Android / Windows / Unknown).
- Info.plist extraction:
  - For `.app` bundles on macOS, plist is auto-extracted.
  - On iPadOS (or for `.pkg` / `.dmg`), the user can pick an
    Info.plist file separately.
- Form fields pre-populated from plist:
  - `CFBundleDisplayName` / `CFBundleName` → Application Name
  - `CFBundleIdentifier` → Bundle ID
  - `CFBundleShortVersionString` → Version
  - `CFBundleVersion` → Build
- Searchable Organization Group picker.
- "This is an upgrade — retire previous version(s)" workflow with
  multi-select retirement.
- Streamed blob upload with real-time progress and human-readable
  activity log.
- Dashboard with recent uploads, app library browser, and a Help
  section with WS1-macOS deployment tips.

---

## Project Structure

```
WS1 App Uploader/
├── Theme/                  Air Force Reserves design tokens & components
├── Models/                 Domain types (Platform, Connection, Activity, …)
├── Services/
│   ├── Keychain/           Secure credential storage
│   ├── WS1API/             REST client, OAuth2 + p12/CMSURL auth
│   └── FileInspection/     Info.plist extraction, IPA reader
├── ViewModels/             @Observable state holders (no Combine)
└── Views/
    ├── RootView.swift      NavigationSplitView shell
    ├── DashboardView.swift Welcome screen with quick actions
    ├── UploadView.swift    Main upload workflow
    ├── AppLibraryView.swift Browse existing internal apps
    ├── HistoryView.swift   Activity log of past uploads
    ├── HelpView.swift      Field reference & WS1 macOS tips
    └── SettingsView.swift  Connection / auth configuration
```

---

## Setup

1. Open `WS1 App Uploader.xcodeproj` in Xcode 17 or newer.
2. Select the **WS1 App Uploader** scheme.
3. If you want to run the macOS variant, add **My Mac (Designed for
   iPad)** as a destination, or convert the project to a multiplatform
   app via *File → Project → Add Platform → macOS*.  All code is
   already guarded with `#if os(macOS)` where appropriate.
4. Press **⌘R** to build & run.

### First-launch configuration

The Settings screen accepts three different connection modes:

| Mode | Required fields |
|---|---|
| Basic + Tenant Code | API URL, Tenant Code, Username, Password |
| OAuth 2.0 (client-credentials) | API URL, Token URL, Client ID, Client Secret, (Tenant Code optional) |
| Certificate (p12 + CMSURL) | API URL, p12 file + passphrase, (Tenant Code optional) |

Press **Test Connection** to issue a `GET /api/system/info` against the
configured tenant.

---

## API Notes

All requests are sent through `WS1APIClient` using `URLSession` with
`async/await`.  Endpoints used:

| Operation | Endpoint |
|---|---|
| Connection test | `GET /api/system/info` |
| OG search | `GET /api/system/groups/search?name=…` |
| App search (by name) | `GET /api/mam/apps/search?applicationname=…` |
| App search (by bundle) | `GET /api/mam/apps/search?bundleid=…` |
| Blob upload | `POST /api/mam/blobs/uploadblob` (octet-stream) |
| Create app (iOS/Android/Win) | `POST /api/mam/apps/internal/save` |
| Create app (macOS) | `POST /api/mam/apps/internal/macos/save` |
| Retire app | `POST /api/mam/apps/internal/{id}/retire` |

The blob upload uses `URLSession.uploadTask(with:fromFile:)` so memory
stays low even for multi-gigabyte payloads.  Real-time progress is
surfaced via KVO on the task's `Progress`.

### CMSURL Signing

When the **Certificate** auth method is selected, every request URL is
signed with the p12's private key using `SecKeyCreateSignature` with
`rsaSignatureMessagePKCS1v15SHA256`.  The signature, certificate
SHA-256 thumbprint, and algorithm identifier are bundled into a JSON
envelope, base64-encoded, and attached as the `CMSURL` header.  The
WS1 server verifies using the public certificate that you must
register in:

> **WS1 Console → Groups & Settings → System → Advanced → API → REST API → Certificate Authentication**

---

## macOS-Specific Instructions

1. Select a `.pkg`, `.dmg`, or `.zip` (containing a `.app` bundle).
2. If you selected an unwrapped `.app` directory, Info.plist will be
   auto-extracted from `Contents/Info.plist`.
3. For `.pkg` / `.dmg`, use the **Select Info.plist…** action to point
   the uploader at the plist contained within the package.  All
   fields can be edited manually before upload.
4. macOS uploads use the dedicated `/macos/save` endpoint and include
   the `MacOsInfoPlist` payload (BundleId, BundleVersion,
   BundleShortVersion, IsInstaller).

---

## Security Considerations

- Connection blob (URL, credentials, OAuth secrets, certificate
  passphrase) is JSON-encoded and stored as a single Keychain item
  with `kSecAttrAccessibleAfterFirstUnlock`.
- p12 binary data is stored as a separate Keychain item.
- Plaintext credentials are never written to disk or logs.
- Network traffic uses ATS defaults; only HTTPS endpoints are
  accepted.
- File-importer URLs are scoped — `startAccessingSecurityScopedResource`
  is used around all file reads.

---

## License

© Air Force Reserve / Mission Mobile Program.  Internal use only.
