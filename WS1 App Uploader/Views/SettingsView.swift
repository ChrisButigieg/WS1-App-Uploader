//
//  SettingsView.swift
//  WS1 App Uploader
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @State private var vm: SettingsViewModel?
    @State private var showCertPicker = false

    var body: some View {
        Group {
            if let vm { content(vm: vm) }
            else { ProgressView() }
        }
        .navigationTitle("Settings")
        .onAppear {
            if vm == nil { vm = SettingsViewModel(appState: appState) }
        }
    }

    @ViewBuilder
    private func content(vm: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                connectionCard(vm: vm)
                authCard(vm: vm)
                actionsBar(vm: vm)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $showCertPicker,
                      allowedContentTypes: [
                        UTType(filenameExtension: "p12") ?? .data,
                        UTType(filenameExtension: "pfx") ?? .data
                      ],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let needs = url.startAccessingSecurityScopedResource()
            defer { if needs { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let viewModel = self.vm {
                viewModel.stageCertificate(data, filename: url.lastPathComponent)
            }
        }
    }

    // MARK: - Connection card

    private func connectionCard(vm: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: "Tenant",
                         subtitle: "Stored securely in the device Keychain.  Never written to disk in plaintext.",
                         icon: "server.rack")
            VStack(spacing: Theme.Spacing.md) {
                LabelledField(title: "API URL",
                              hint: "Example: https://as1234.awmdm.com  (no trailing /api)") {
                    TextField("https://as1234.awmdm.com",
                              text: Bindable(vm).draft.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
                LabelledField(title: "Tenant Code (aw-tenant-code header)",
                              hint: "Required for v1 endpoints and basic auth.") {
                    TextField("eg. UNDXXXXXX==",
                              text: Bindable(vm).draft.tenantCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
                HStack(spacing: Theme.Spacing.md) {
                    LabelledField(title: "Default OG ID") {
                        TextField("0",
                                  value: Bindable(vm).draft.organizationGroupID,
                                  format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabelledField(title: "Default OG Name") {
                        TextField("Air Force Reserve",
                                  text: Bindable(vm).draft.organizationGroupName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .cardSurface()
        }
    }

    // MARK: - Auth card

    @ViewBuilder
    private func authCard(vm: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: "Authentication", icon: "key.fill")
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Picker("Method", selection: Bindable(vm).draft.authMethod) {
                    ForEach(AuthMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                Text(vm.draft.authMethod.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch vm.draft.authMethod {
                case .basicTenantCode:    basicFields(vm: vm)
                case .oauth2ClientCredentials: oauthFields(vm: vm)
                case .certificateCMSURL:  certificateFields(vm: vm)
                }
            }
            .cardSurface()
        }
    }

    private func basicFields(vm: SettingsViewModel) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            LabelledField(title: "Username") {
                TextField("admin",
                          text: Bindable(vm).draft.username)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            LabelledField(title: "Password") {
                SecureField("••••••••",
                            text: Bindable(vm).draft.password)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func oauthFields(vm: SettingsViewModel) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            LabelledField(title: "Token URL",
                          hint: "From the WS1 / Omnissa Cloud OAuth client config.") {
                TextField("https://uat.uemauth.vmwservices.com/connect/token",
                          text: Bindable(vm).draft.oauthTokenURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }
            LabelledField(title: "Client ID") {
                TextField("",
                          text: Bindable(vm).draft.oauthClientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }
            LabelledField(title: "Client Secret") {
                SecureField("",
                            text: Bindable(vm).draft.oauthClientSecret)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func certificateFields(vm: SettingsViewModel) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: vm.certificateExistsInKeychain ? "checkmark.shield.fill" : "shield.slash")
                    .font(.title2)
                    .foregroundStyle(vm.certificateExistsInKeychain ? Theme.success : Theme.warning)
                VStack(alignment: .leading) {
                    Text(vm.draft.certificateFilename.isEmpty
                            ? "No certificate selected"
                            : vm.draft.certificateFilename)
                        .font(.body.weight(.medium))
                    Text(vm.certificateExistsInKeychain
                            ? "A p12 certificate is stored in the Keychain."
                            : "Select a .p12 / .pfx file to enable certificate-based auth.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select p12…") { showCertPicker = true }
                    .buttonStyle(SecondaryButtonStyle())
                if vm.certificateExistsInKeychain {
                    Button("Remove", role: .destructive) { vm.clearCertificate() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            LabelledField(title: "Certificate Password (passphrase)") {
                SecureField("••••••••",
                            text: Bindable(vm).draft.certificatePassword)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Actions

    private func actionsBar(vm: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Button("Test Connection") {
                    Task { await vm.testConnection() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!vm.draft.isMinimallyConfigured || vm.result == .testing)

                Spacer()

                Button("Revert") { vm.revert() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save") {
                    do { try vm.save() }
                    catch { vm.result = .failure(error.localizedDescription) }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            resultView(vm: vm)
        }
    }

    @ViewBuilder
    private func resultView(vm: SettingsViewModel) -> some View {
        switch vm.result {
        case .idle:
            EmptyView()
        case .testing:
            HStack { ProgressView(); Text("Testing connection…").foregroundStyle(.secondary) }
        case .success(let message):
            Label(message, systemImage: "checkmark.seal.fill")
                .foregroundStyle(Theme.success)
                .padding(Theme.Spacing.md)
                .background(Theme.success.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(Theme.actionRed)
                .padding(Theme.Spacing.md)
                .background(Theme.actionRed.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
