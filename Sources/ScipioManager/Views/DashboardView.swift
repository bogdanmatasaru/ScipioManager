import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var frameworkCount = 0
    @State private var totalSize: Int64 = 0
    @State private var cacheLocations: [LocalCacheService.CacheLocation] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                heroCards
                quickActions
                if !appState.logLines.isEmpty {
                    LogConsoleView(lines: appState.logLines)
                        .frame(minHeight: 200, maxHeight: 300)
                }
                activitySection
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .task { await loadData() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 4) {
            if let dir = appState.scipioDir {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(dir.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Scipio directory not detected. Open Settings to configure.")
                        .font(.callout)
                }
                .padding(8)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var heroCards: some View {
        HStack(spacing: 12) {
            HeroCard(
                title: "Frameworks",
                value: "\(frameworkCount)",
                icon: "shippingbox",
                color: .blue
            )
            HeroCard(
                title: "Disk Usage",
                value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                icon: "internaldrive",
                color: .purple
            )
            HeroCard(
                title: "Last Sync",
                value: lastSyncText,
                icon: "clock",
                color: .green
            )
            HeroCard(
                title: "Status",
                value: appState.isRunning ? "Running" : "Ready",
                icon: appState.isRunning ? "hourglass" : "checkmark.circle",
                color: appState.isRunning ? .orange : .green
            )
        }
    }

    private var quickActions: some View {
        GroupBox("Actions") {
            HStack(spacing: 12) {
                ActionButton("Sync (Download)", icon: "arrow.down.circle", isRunning: appState.isRunning) {
                    await runSync(mode: .consumerOnly)
                }
                .buttonStyle(.borderedProminent)

                ActionButton("Full Build + Cache", icon: "hammer", isRunning: appState.isRunning) {
                    await runSync(mode: .producerAndConsumer)
                }
                .buttonStyle(.bordered)

                ActionButton("Refresh Status", icon: "arrow.clockwise") {
                    await loadData()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var activitySection: some View {
        Group {
            if !appState.recentActivities.isEmpty {
                GroupBox("Recent Activity") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.recentActivities.prefix(10)) { activity in
                            HStack(spacing: 8) {
                                Image(systemName: activity.icon)
                                    .foregroundStyle(activityColor(activity.type))
                                Text(activity.message)
                                    .font(.callout)
                                Spacer()
                                Text(activity.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Logic

    private var lastSyncText: String {
        guard let date = appState.lastSyncDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadData() async {
        guard let scipioDir = appState.scipioDir else { return }
        let service = ScipioService(scipioDir: scipioDir)
        frameworkCount = await service.frameworkCount()
        cacheLocations = LocalCacheService.discoverCaches(scipioDir: scipioDir)
        totalSize = cacheLocations
            .first { $0.id == "project-xcframeworks" }?.size ?? 0
    }

    private func runSync(mode: ScipioService.SyncMode) async {
        guard let scipioDir = appState.scipioDir else { return }
        appState.isRunning = true
        appState.clearLog()
        defer { appState.isRunning = false }

        let service = ScipioService(scipioDir: scipioDir)
        do {
            let result = try await service.sync(mode: mode) { line, stream in
                Task { @MainActor in
                    appState.appendLog(line, stream: stream)
                }
            }
            appState.lastSyncDate = Date()
            appState.addActivity("Synced \(result.frameworkCount) frameworks in \(result.elapsedFormatted)", type: .success)
            await loadData()
        } catch {
            appState.addActivity("Sync failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func activityColor(_ type: ActivityEntry.ActivityType) -> Color {
        switch type {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
