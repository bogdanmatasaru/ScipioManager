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
            if let error {
                errorBanner(error)
            }

            if isLoading && entries.isEmpty {
                loadingView
            } else {
                content
            }
        }
        .navigationTitle("GCS Bucket")
        .navigationSubtitle(subtitleText)
        .searchable(text: $searchText, prompt: "Filter...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
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

    private var subtitleText: String {
        guard let stats else { return "" }
        return "\(stats.totalEntries) entries -- \(stats.totalSizeFormatted) -- \(stats.frameworkCount) frameworks"
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Retry") { Task { await loadEntries() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(.red.opacity(0.06))
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading bucket contents...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .foregroundStyle(.tertiary)
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
        HStack(spacing: 8) {
            Text(entry.cacheHash)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Text(entry.sizeFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.lastModifiedFormatted)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func loadEntries() async {
        guard let hmacURL = appState.hmacKeyURL else {
            error = "HMAC key not configured. Go to Settings."
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
        } catch is HMACKeyLoader.LoadError {
            self.error = "GCS credentials missing. Go to Settings to configure."
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
}
