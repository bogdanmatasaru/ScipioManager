import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var customScipioPath = ""
    @State private var credentialSource: HMACKeyLoader.CredentialSource = .none
    @State private var showKeyFilePicker = false
    @State private var importError: String?

    var body: some View {
        Form {
            projectSection
            credentialsSection
            bucketConfigSection
            buildInfoSection
            configInfoSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { refreshCredentials() }
        .fileImporter(
            isPresented: $showKeyFilePicker,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            handleKeyFileImport(result)
        }
    }

    // MARK: - Project

    private var projectSection: some View {
        Section("Project") {
            LabeledContent("Scipio Directory") {
                pathText(appState.scipioDir?.path)
            }
            LabeledContent("Build Package") {
                pathText(appState.buildPackageURL?.path)
            }
            LabeledContent("Frameworks") {
                pathText(appState.frameworksDir?.path)
            }
            LabeledContent("Runner Binary") {
                pathWithStatus(
                    appState.runnerBinaryURL?.path,
                    exists: appState.runnerBinaryURL.map { ProcessRunner.executableExists(at: $0.path) }
                )
            }

            LabeledContent("DerivedData Prefix") {
                if let prefix = appState.resolvedDerivedDataPrefix {
                    HStack(spacing: 4) {
                        Text(prefix)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("(auto-detected)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Not detected")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }

            HStack {
                TextField("Scipio path", text: $customScipioPath, prompt: Text("/path/to/Scipio"))
                    .textFieldStyle(.roundedBorder)
                Button("Set") {
                    let url = URL(fileURLWithPath: customScipioPath)
                    appState.scipioDir = url
                    appState.buildPackageURL = url.appendingPathComponent("Build/Package.swift")
                    appState.frameworksDir = url.appendingPathComponent("Frameworks/XCFrameworks")
                    appState.runnerBinaryURL = url.appendingPathComponent("Runner/.build/arm64-apple-macosx/release/ScipioRunner")
                    appState.hmacKeyURL = url.appendingPathComponent(appState.config.hmacKeyFilename)
                }
                .buttonStyle(.bordered)
                Button("Auto-Detect") {
                    appState.detectProjectPaths()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Credentials

    private var credentialsSection: some View {
        Section("GCS Credentials") {
            HStack(spacing: 8) {
                Image(systemName: credentialSource == .none ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(credentialSource == .none ? .red : .green)
                Text(credentialSource.rawValue)
                Spacer()
                Button("Refresh") { refreshCredentials() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if credentialSource == .none {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HMAC credentials are required for remote cache access.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Place a **\(appState.config.hmacKeyFilename)** file in your Scipio/ directory, or set environment variables.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Expected JSON format:")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("{ \"accessKeyId\": \"GOOG1E...\", \"secretAccessKey\": \"...\" }")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Text("Or set environment variables:")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("SCIPIO_GCS_HMAC_ACCESS_KEY / SCIPIO_GCS_HMAC_SECRET_KEY")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Button {
                        showKeyFilePicker = true
                    } label: {
                        Label("Import Key File...", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Bucket Config

    private var bucketConfigSection: some View {
        Section("Bucket Configuration") {
            @Bindable var state = appState
            LabeledContent("Bucket Name") {
                TextField("Bucket", text: $state.bucketConfig.bucketName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            LabeledContent("Endpoint") {
                TextField("Endpoint", text: $state.bucketConfig.endpoint)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            LabeledContent("Prefix") {
                TextField("Prefix", text: $state.bucketConfig.storagePrefix)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            LabeledContent("Region") {
                TextField("Region", text: $state.bucketConfig.region)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
        }
    }

    // MARK: - Build Info

    private var buildInfoSection: some View {
        Section("Build Configuration") {
            let config = BuildConfiguration.current
            LabeledContent("Configuration", value: config.buildConfig)
            LabeledContent("Framework Type", value: config.frameworkType)
            LabeledContent("Simulator Support", value: config.simulatorSupported ? "Yes" : "No")
            LabeledContent("Debug Symbols", value: config.debugSymbolsEmbedded ? "Embedded" : "Not Embedded")
            LabeledContent("Library Evolution", value: config.libraryEvolution ? "Enabled" : "Disabled")
            LabeledContent("Swift Version", value: config.swiftVersion)
        }
    }

    // MARK: - Config Info

    private var configInfoSection: some View {
        Section("Configuration File") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings are loaded from `scipio-manager.json` placed next to the app bundle.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Search locations:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("1. Next to the .app bundle")
                    Text("2. Current working directory")
                    Text("3. ~/.config/scipio-manager/config.json")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func pathText(_ path: String?) -> some View {
        Group {
            if let path {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Not configured")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func pathWithStatus(_ path: String?, exists: Bool?) -> some View {
        HStack(spacing: 4) {
            pathText(path)
            if let exists {
                Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(exists ? .green : .red)
                    .font(.caption)
            }
        }
    }

    private func refreshCredentials() {
        guard let hmacURL = appState.hmacKeyURL else {
            credentialSource = .none
            return
        }
        credentialSource = HMACKeyLoader.credentialsAvailable(at: hmacURL)
    }

    private func handleKeyFileImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }
            guard let targetURL = appState.hmacKeyURL else {
                importError = "Scipio directory not configured."
                return
            }

            guard sourceURL.startAccessingSecurityScopedResource() else {
                importError = "Cannot access the selected file."
                return
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: sourceURL)
                let decoded = try JSONDecoder().decode(HMACKey.self, from: data)
                guard !decoded.accessKeyId.isEmpty, !decoded.secretAccessKey.isEmpty else {
                    importError = "Key file has empty credentials."
                    return
                }

                try data.write(to: targetURL, options: .atomic)
                refreshCredentials()
                appState.addActivity("Imported HMAC key file", type: .success)
            } catch let error as DecodingError {
                importError = "Invalid JSON format: \(error.localizedDescription)"
            } catch {
                importError = "Import failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = "File selection failed: \(error.localizedDescription)"
        }
    }
}
