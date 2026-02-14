import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var customScipioPath = ""
    @State private var credentialSource: HMACKeyLoader.CredentialSource = .none
    @State private var showKeyFilePicker = false
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                projectPaths
                bucketConfig
                credentials
                buildOptions
            }
            .padding()
        }
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

    // MARK: - Project Paths

    private var projectPaths: some View {
        GroupBox("Project Paths") {
            VStack(alignment: .leading, spacing: 10) {
                pathRow("Scipio Directory", path: appState.scipioDir?.path)
                pathRow("Build Package", path: appState.buildPackageURL?.path)
                pathRow("Frameworks Dir", path: appState.frameworksDir?.path)
                pathRow("Runner Binary", path: appState.runnerBinaryURL?.path,
                        exists: appState.runnerBinaryURL.map { ProcessRunner.executableExists(at: $0.path) })
                pathRow("HMAC Key", path: appState.hmacKeyURL?.path,
                        exists: appState.hmacKeyURL.map { FileManager.default.fileExists(atPath: $0.path) })

                Divider()

                HStack {
                    TextField("Custom Scipio Path", text: $customScipioPath, prompt: Text("/path/to/Scipio"))
                        .textFieldStyle(.roundedBorder)
                    Button("Set") {
                        let url = URL(fileURLWithPath: customScipioPath)
                        appState.scipioDir = url
                        appState.buildPackageURL = url.appendingPathComponent("Build/Package.swift")
                        appState.frameworksDir = url.appendingPathComponent("Frameworks/XCFrameworks")
                        appState.runnerBinaryURL = url.appendingPathComponent("Runner/.build/arm64-apple-macosx/release/ScipioRunner")
                        appState.hmacKeyURL = url.appendingPathComponent("gcs-hmac.json")
                    }
                    .buttonStyle(.bordered)

                    Button("Auto-Detect") {
                        appState.detectProjectPaths()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Bucket Config

    private var bucketConfig: some View {
        GroupBox("GCS Bucket Configuration") {
            @Bindable var state = appState
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Bucket Name") {
                    TextField("Bucket", text: $state.bucketConfig.bucketName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }
                LabeledContent("Endpoint") {
                    TextField("Endpoint", text: $state.bucketConfig.endpoint)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }
                LabeledContent("Storage Prefix") {
                    TextField("Prefix", text: $state.bucketConfig.storagePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }
                LabeledContent("Region") {
                    TextField("Region", text: $state.bucketConfig.region)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Credentials

    private var credentials: some View {
        GroupBox("HMAC Credentials") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: credentialSource == .none ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(credentialSource == .none ? .red : .green)
                        .font(.title3)
                    Text("Source: \(credentialSource.rawValue)")
                        .fontWeight(.medium)
                    Spacer()
                    Button("Refresh") { refreshCredentials() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if credentialSource == .none {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "key.slash")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HMAC credentials not found")
                                    .font(.headline)
                                Text("Remote cache operations require GCS HMAC keys (bucket browsing, sync, cleanup).")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("How to get the credentials", systemImage: "questionmark.circle")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("1. Ask a team member or your iOS lead for the GCS HMAC key file.")
                                    .font(.callout)

                                Text("2. Save the file as **gcs-hmac.json** in the root of the **Scipio/** folder:")
                                    .font(.callout)

                                Text("Scipio/gcs-hmac.json")
                                    .font(.system(.callout, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                                Text("3. The file format is:")
                                    .font(.callout)

                                Text("""
                                { "accessKeyId": "GOOG1E...", "secretAccessKey": "..." }
                                """)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                                Text("This file is gitignored and will not be committed to the repository.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                showKeyFilePicker = true
                            } label: {
                                Label("Import Key File...", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            Text("or drop a .json file here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        if let importError {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(importError)
                                    .foregroundStyle(.red)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Build Options

    private var buildOptions: some View {
        GroupBox("Build Configuration (Read-Only)") {
            let config = BuildConfiguration.current
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Build Configuration", value: config.buildConfig)
                LabeledContent("Framework Type", value: config.frameworkType)
                LabeledContent("Simulator Support", value: config.simulatorSupported ? "Yes" : "No")
                LabeledContent("Debug Symbols", value: config.debugSymbolsEmbedded ? "Embedded" : "Not Embedded")
                LabeledContent("Library Evolution", value: config.libraryEvolution ? "Enabled" : "Disabled")
                LabeledContent("Strip DWARF", value: config.stripDWARF ? "Yes" : "No")
                LabeledContent("Swift Version", value: config.swiftVersion)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func pathRow(_ label: String, path: String?, exists: Bool? = nil) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            if let path {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let exists {
                    Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(exists ? .green : .red)
                        .font(.caption)
                }
            } else {
                Text("Not configured")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
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

            // Validate the JSON file has the required keys
            guard sourceURL.startAccessingSecurityScopedResource() else {
                importError = "Cannot access the selected file (sandbox restriction)."
                return
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: sourceURL)
                let decoded = try JSONDecoder().decode(HMACKey.self, from: data)
                guard !decoded.accessKeyId.isEmpty, !decoded.secretAccessKey.isEmpty else {
                    importError = "Key file has empty accessKeyId or secretAccessKey."
                    return
                }

                // Copy to the Scipio directory
                try data.write(to: targetURL, options: .atomic)
                refreshCredentials()
                appState.addActivity("Imported HMAC key file to \(targetURL.lastPathComponent)", type: .success)
            } catch let error as DecodingError {
                importError = "Invalid JSON format. Expected {\"accessKeyId\": \"...\", \"secretAccessKey\": \"...\"}. Error: \(error.localizedDescription)"
            } catch {
                importError = "Failed to import: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = "File selection failed: \(error.localizedDescription)"
        }
    }
}
