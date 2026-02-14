import SwiftUI

struct CacheView: View {
    @Environment(AppState.self) private var appState
    @State private var cacheLocations: [LocalCacheService.CacheLocation] = []
    @State private var showNuclearConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                cacheLayers
                storageLocations
            }
            .padding(24)
        }
        .navigationTitle("Cache")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    loadCaches()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { loadCaches() }
        .alert("Nuclear Clean", isPresented: $showNuclearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task { await performNuclearClean() }
            }
        } message: {
            Text("This will delete DerivedData, SPM artifacts, all XCFrameworks, and SourcePackages. You will need to re-sync.")
        }
    }

    // MARK: - Cache Layers

    private var cacheLayers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cache Architecture")
                .font(.headline)

            let projectCache = cacheLocations.first { $0.id == "project-xcframeworks" }
            let localCache = cacheLocations.first { $0.id == "scipio-local" }

            VStack(spacing: 0) {
                layerRow(
                    number: "1",
                    name: "Project",
                    detail: "Frameworks/XCFrameworks/",
                    size: projectCache?.sizeFormatted ?? "--",
                    isPresent: projectCache?.exists ?? false
                )
                Divider().padding(.leading, 40)
                layerRow(
                    number: "2",
                    name: "Local Disk",
                    detail: "~/.cache/Scipio/",
                    size: localCache?.sizeFormatted ?? "--",
                    isPresent: localCache?.exists ?? false
                )
                Divider().padding(.leading, 40)
                layerRow(
                    number: "3",
                    name: "GCS Remote",
                    detail: appState.bucketConfig.bucketName.isEmpty ? "Not configured" : appState.bucketConfig.bucketName,
                    size: "Cloud",
                    isPresent: !appState.bucketConfig.bucketName.isEmpty
                )
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func layerRow(number: String, name: String, detail: String, size: String, isPresent: Bool) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(isPresent ? Color.accentColor : .gray, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }

            Spacer()

            Text(size)
                .font(.subheadline)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Storage Locations

    private var storageLocations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Storage Locations")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    showNuclearConfirm = true
                } label: {
                    Label("Clean All", systemImage: "trash")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.red)
            }

            VStack(spacing: 0) {
                ForEach(Array(cacheLocations.enumerated()), id: \.element.id) { index, loc in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(loc.description)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(loc.exists ? loc.sizeFormatted : "--")
                            .font(.subheadline)
                            .fontDesign(.monospaced)
                            .foregroundStyle(loc.exists ? .secondary : .quaternary)

                        Button("Clean") {
                            Task { await cleanLocation(loc) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!loc.exists)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < cacheLocations.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Actions

    private func loadCaches() {
        guard let scipioDir = appState.scipioDir else { return }
        cacheLocations = LocalCacheService.discoverCaches(scipioDir: scipioDir)
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
            let result = try LocalCacheService.nuclearClean(
                scipioDir: scipioDir,
                derivedDataPrefix: appState.resolvedDerivedDataPrefix
            )
            appState.addActivity("Nuclear clean: freed \(result.totalSizeFormatted)", type: .success)
            loadCaches()
        } catch {
            appState.addActivity("Nuclear clean failed: \(error.localizedDescription)", type: .error)
        }
    }
}
