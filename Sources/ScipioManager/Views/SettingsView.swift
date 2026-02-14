import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var customScipioPath = ""
    @State private var credentialSource: HMACKeyLoader.CredentialSource = .none

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
            HStack {
                Image(systemName: credentialSource == .none ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(credentialSource == .none ? .red : .green)
                Text("Source: \(credentialSource.rawValue)")
                Spacer()
                Button("Refresh") { refreshCredentials() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
}
