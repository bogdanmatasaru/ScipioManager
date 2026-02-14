import SwiftUI

struct BucketBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var entries: [CacheEntry] = []
    @State private var groups: [CacheFrameworkGroup] = []
    @State private var stats: BucketStats?
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""
    @State private var selectedEntries = Set<String>()
    @State private var showDeleteConfirm = false
    @State private var staleDays = 90
    @State private var showStaleConfirm = false
    @State private var viewMode: ViewMode = .grouped

    enum ViewMode: String, CaseIterable {
        case grouped = "By Framework"
        case flat = "All Entries"
    }

    var filteredGroups: [CacheFrameworkGroup] {
        if searchText.isEmpty { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredEntries: [CacheEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let stats {
                statsBar(stats)
            }

            if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.callout)
                    Spacer()
                    Button("Retry") { Task { await loadEntries() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding()
                .background(.red.opacity(0.05))
            }

            if isLoading {
                ProgressView("Loading bucket contents...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("GCS Bucket")
        .searchable(text: $searchText, prompt: "Filter...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadEntries() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Menu {
                    Button("Delete Selected (\(selectedEntries.count))") {
                        showDeleteConfirm = true
                    }
                    .disabled(selectedEntries.isEmpty)

                    Divider()

                    Button("Delete Entries Older Than \(staleDays) Days") {
                        showStaleConfirm = true
                    }

                    Stepper("Stale Threshold: \(staleDays) days", value: $staleDays, in: 7...365, step: 7)
                } label: {
                    Label("Cleanup", systemImage: "trash")
                }
            }
        }
        .alert("Delete Selected Entries?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selectedEntries.count) entries", role: .destructive) {
                Task { await deleteSelected() }
            }
        }
        .alert("Delete Stale Entries?", isPresented: $showStaleConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteStale() }
            }
        } message: {
            Text("This will delete all cache entries older than \(staleDays) days.")
        }
        .task { await loadEntries() }
    }

    // MARK: - Stats Bar

    private func statsBar(_ stats: BucketStats) -> some View {
        HStack(spacing: 20) {
            Label("\(stats.totalEntries) entries", systemImage: "doc.on.doc")
            Label(stats.totalSizeFormatted, systemImage: "internaldrive")
            Label("\(stats.frameworkCount) frameworks", systemImage: "shippingbox")
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .grouped:
            groupedView
        case .flat:
            flatView
        }
    }

    private var groupedView: some View {
        List {
            ForEach(filteredGroups) { group in
                DisclosureGroup {
                    ForEach(group.entries) { entry in
                        entryRow(entry)
                    }
                } label: {
                    HStack {
                        Text(group.name)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(group.entryCount) versions")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(group.totalSizeFormatted)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .fontDesign(.monospaced)
                    }
                }
            }
        }
    }

    private var flatView: some View {
        Table(filteredEntries, selection: $selectedEntries) {
            TableColumn("Key") { entry in
                Text(entry.key)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
            .width(min: 300)

            TableColumn("Framework") { entry in
                Text(entry.frameworkName)
            }
            .width(min: 100)

            TableColumn("Size") { entry in
                Text(entry.sizeFormatted)
                    .fontDesign(.monospaced)
            }
            .width(80)

            TableColumn("Modified") { entry in
                Text(entry.lastModifiedFormatted)
            }
            .width(80)
        }
    }

    private func entryRow(_ entry: CacheEntry) -> some View {
        HStack {
            Text(entry.cacheHash)
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Text(entry.sizeFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.lastModifiedFormatted)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button(role: .destructive) {
                Task { await deleteSingle(entry) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Actions

    private func loadEntries() async {
        guard let hmacURL = appState.hmacKeyURL else {
            error = "HMAC key path not configured. Go to Settings to configure."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let hmac = try HMACKeyLoader.load(from: hmacURL)
            let service = GCSBucketService(hmacKey: hmac, config: appState.bucketConfig)

            let bucketStats = try await service.bucketStats()
            stats = bucketStats
            entries = bucketStats.entries

            let grouped = Dictionary(grouping: entries) { $0.frameworkName }
            groups = grouped.map { CacheFrameworkGroup(name: $0.key, entries: $0.value) }
                .sorted { $0.name < $1.name }

            appState.addActivity("Loaded \(entries.count) bucket entries", type: .info)
        } catch let loadError as HMACKeyLoader.LoadError {
            self.error = "Credentials missing. Ask your team for the gcs-hmac.json file and place it in the Scipio/ folder. Then go to Settings > HMAC Credentials."
            appState.addActivity("GCS credentials not found", type: .error)
        } catch {
            self.error = error.localizedDescription
            appState.addActivity("Failed to load bucket: \(error.localizedDescription)", type: .error)
        }
    }

    private func deleteSelected() async {
        guard let hmacURL = appState.hmacKeyURL else { return }
        do {
            let hmac = try HMACKeyLoader.load(from: hmacURL)
            let service = GCSBucketService(hmacKey: hmac, config: appState.bucketConfig)
            let result = try await service.deleteObjects(keys: Array(selectedEntries))
            selectedEntries.removeAll()
            appState.addActivity("Deleted \(result.deleted) entries (\(result.failed) failed)", type: .success)
            await loadEntries()
        } catch {
            appState.addActivity("Delete failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func deleteStale() async {
        guard let hmacURL = appState.hmacKeyURL else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -staleDays, to: Date())!
        do {
            let hmac = try HMACKeyLoader.load(from: hmacURL)
            let service = GCSBucketService(hmacKey: hmac, config: appState.bucketConfig)
            let deleted = try await service.deleteStaleEntries(olderThan: cutoff)
            appState.addActivity("Deleted \(deleted) stale entries (older than \(staleDays) days)", type: .success)
            await loadEntries()
        } catch {
            appState.addActivity("Stale cleanup failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func deleteSingle(_ entry: CacheEntry) async {
        guard let hmacURL = appState.hmacKeyURL else { return }
        do {
            let hmac = try HMACKeyLoader.load(from: hmacURL)
            let service = GCSBucketService(hmacKey: hmac, config: appState.bucketConfig)
            try await service.deleteObject(key: entry.key)
            appState.addActivity("Deleted \(entry.frameworkName)/\(entry.cacheHash)", type: .info)
            await loadEntries()
        } catch {
            appState.addActivity("Delete failed: \(error.localizedDescription)", type: .error)
        }
    }
}
