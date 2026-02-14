import SwiftUI

struct CacheView: View {
    @Environment(AppState.self) private var appState
    @State private var cacheLocations: [LocalCacheService.CacheLocation] = []
    @State private var showNuclearConfirm = false
    @State private var nuclearResult: LocalCacheService.NuclearCleanResult?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                cacheLayers
                syncControls
                if !appState.logLines.isEmpty {
                    LogConsoleView(lines: appState.logLines)
                        .frame(minHeight: 200, maxHeight: 300)
                }
                nuclearSection
            }
            .padding()
        }
        .navigationTitle("Cache Management")
        .task { loadCaches() }
        .alert("Nuclear Clean", isPresented: $showNuclearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task { await performNuclearClean() }
            }
        } message: {
            Text("This will delete DerivedData, SPM artifacts, all XCFrameworks, and SourcePackages. You will need to run Sync to rebuild.")
        }
    }

    // MARK: - Cache Layers

    private var cacheLayers: some View {
        GroupBox("Cache Layers (3-tier)") {
            VStack(spacing: 8) {
                let projectCache = cacheLocations.first { $0.id == "project-xcframeworks" }
                CacheLayerCard(
                    name: "Layer 1: Project (XCFrameworks/)",
                    icon: "folder",
                    detail: projectCache?.path.path ?? "N/A",
                    size: projectCache?.sizeFormatted ?? "0 KB",
                    isPresent: projectCache?.exists ?? false
                )

                let localCache = cacheLocations.first { $0.id == "scipio-local" }
                CacheLayerCard(
                    name: "Layer 2: Local Disk (~/.cache/Scipio)",
                    icon: "internaldrive",
                    detail: localCache?.path.path ?? "N/A",
                    size: localCache?.sizeFormatted ?? "0 KB",
                    isPresent: localCache?.exists ?? false
                )

                CacheLayerCard(
                    name: "Layer 3: GCS Remote (emag-ios-scipio-cache)",
                    icon: "cloud",
                    detail: "See GCS Bucket tab for details",
                    size: "Remote",
                    isPresent: true
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var syncControls: some View {
        GroupBox("Sync Operations") {
            HStack(spacing: 12) {
                ActionButton("Consumer (Download)", icon: "arrow.down.circle", isRunning: appState.isRunning) {
                    await runSync(mode: .consumerOnly)
                }
                .buttonStyle(.borderedProminent)

                ActionButton("Producer + Consumer (Build + Cache)", icon: "hammer", isRunning: appState.isRunning) {
                    await runSync(mode: .producerAndConsumer)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var nuclearSection: some View {
        GroupBox("Cleanup") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(cacheLocations, id: \.id) { loc in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(loc.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(loc.exists ? loc.sizeFormatted : "N/A")
                            .font(.subheadline)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)

                        Button("Clean") {
                            Task { await cleanLocation(loc) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!loc.exists)
                    }
                    Divider()
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showNuclearConfirm = true
                    } label: {
                        Label("Nuclear Clean (Everything)", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func loadCaches() {
        guard let scipioDir = appState.scipioDir else { return }
        cacheLocations = LocalCacheService.discoverCaches(scipioDir: scipioDir)
    }

    private func runSync(mode: ScipioService.SyncMode) async {
        guard let scipioDir = appState.scipioDir else { return }
        appState.isRunning = true
        appState.clearLog()
        defer { appState.isRunning = false }

        let service = ScipioService(scipioDir: scipioDir)
        do {
            let result = try await service.sync(mode: mode, verbose: true) { line, stream in
                Task { @MainActor in
                    appState.appendLog(line, stream: stream)
                }
            }
            appState.lastSyncDate = Date()
            appState.addActivity("Synced \(result.frameworkCount) frameworks in \(result.elapsedFormatted)", type: .success)
            loadCaches()
        } catch {
            appState.addActivity("Sync failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func cleanLocation(_ loc: LocalCacheService.CacheLocation) async {
        do {
            let freed = try LocalCacheService.cleanCache(at: loc.path)
            appState.addActivity(
                "Cleaned \(loc.name): freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))",
                type: .success
            )
            loadCaches()
        } catch {
            appState.addActivity("Failed to clean \(loc.name): \(error.localizedDescription)", type: .error)
        }
    }

    private func performNuclearClean() async {
        guard let scipioDir = appState.scipioDir else { return }
        do {
            let result = try LocalCacheService.nuclearClean(scipioDir: scipioDir)
            nuclearResult = result
            appState.addActivity("Nuclear clean complete: freed \(result.totalSizeFormatted)", type: .success)
            loadCaches()
        } catch {
            appState.addActivity("Nuclear clean failed: \(error.localizedDescription)", type: .error)
        }
    }
}
