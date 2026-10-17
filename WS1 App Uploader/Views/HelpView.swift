//
//  HelpView.swift
//  WS1 App Uploader
//

import SwiftUI

struct HelpView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                helpCard(
                    title: "Workspace ONE Connection",
                    icon: "link",
                    items: [
                        ("API URL", "Use the API server host shown in your tenant — for example, `https://as1234.awmdm.com`.  Do NOT include the `/api` path."),
                        ("Tenant Code", "Required for legacy basic-auth endpoints.  Visible in the WS1 console under Groups & Settings → All Settings → System → Advanced → API → REST API."),
                        ("OAuth 2.0", "Strongly preferred.  Create a service client in the Omnissa Cloud Console and use the resulting client ID / secret with the token endpoint shown there.")
                    ]
                )

                helpCard(
                    title: "macOS App Deployment",
                    icon: "laptopcomputer",
                    items: [
                        ("Bundle Types", "WS1 accepts `.pkg` (preferred for system-wide installation), `.dmg`, and `.zip` containing a `.app` bundle."),
                        ("Info.plist Required", "macOS internal applications require a plist payload sent alongside the binary.  The uploader extracts this automatically from a `.app` bundle on macOS; on iPadOS, use the \"Select Info.plist…\" button."),
                        ("Pre-fills", "`CFBundleName` → Application Name, `CFBundleIdentifier` → Bundle ID, `CFBundleShortVersionString` → Version, `CFBundleVersion` → Build."),
                        ("Smart Upgrade", "Check \"This is an upgrade\" — the uploader searches existing apps with the same Bundle ID and lets you retire older versions in one click.")
                    ]
                )

                helpCard(
                    title: "Certificate Auth (CMSURL)",
                    icon: "lock.shield",
                    items: [
                        ("p12 Import", "On the Settings screen choose Certificate (p12 + CMSURL), then load your p12 file and supply the passphrase."),
                        ("How signing works", "Each outgoing API request URL is signed by your private key — the signature, certificate thumbprint, and algorithm identifier are attached to the `CMSURL` header.  The server verifies using the matching public certificate registered with your tenant."),
                        ("Troubleshooting", "If you see HTTP 401, verify your certificate is registered in the WS1 console under Groups & Settings → System → Advanced → API → REST API → Certificate Authentication.")
                    ]
                )

                helpCard(
                    title: "Tips & Common Issues",
                    icon: "wand.and.stars",
                    items: [
                        ("Large files", "Uploads over 2 GB use URLSession's streaming transfer encoding — keep the device awake until the progress bar finishes."),
                        ("Failed retirement", "Existing internal apps may be retired only when no active install jobs are running.  Re-try after the console finishes background reconciliation."),
                        ("Org Group missing", "If the OG dropdown is empty, your service account may lack `READ` rights on `LocationGroups`.  Grant the `LocationGroup Read` role in the WS1 console.")
                    ]
                )

                Text("Built with care for Air Force Reserve Mission Mobile administrators.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Help")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Field Reference & Tips")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
            Text("Quick guidance for setting up the WS1 connection and uploading apps across iOS, macOS, Android, and Windows.")
                .foregroundStyle(.secondary)
        }
    }

    private func helpCard(title: String,
                          icon: String,
                          items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Theme.brandAccent)
                Text(title).font(.title3.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.subheadline.weight(.semibold))
                        Text(item.1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .cardSurface()
    }
}
