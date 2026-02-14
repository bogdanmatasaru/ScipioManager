import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var frameworkCount = 0
    @State private var totalSize: Int64 = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Warning banner if no project detected
                if appState.scipioDir == nil {
                    notConfiguredBanner
                }

                // Stats row
                statsRow

                // Primary Actions
                actionRow

                // Console (only when there's output)
                if !appState.logLines.isEmpty {
                    LogConsoleView(lines: appState.logLines)
                        .frame(minHeight: 180, maxHeight: 280)
                }

                // Recent Activity
                if !appState.recentActivities.isEmpty {
                    activitySection
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadData() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - Not Configured

    private var notConfiguredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scipio directory not detected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Go to Settings to configure your project path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Frameworks",
                value: "\(frameworkCount)",
                icon: "shippingbox",
                tint: .blue
            )
            StatCard(
                title: "Disk Usage",
                value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                icon: "internaldrive",
                tint: .purple
            )
            StatCard(
                title: "Last Sync",
                value: lastSyncText,
                icon: "clock",
                tint: .green
            )
            StatCard(
                title: "Status",
                value: appState.isRunning ? "Running" : "Ready",
                icon: appState.isRunning ? "hourglass" : "checkmark.circle",
                tint: appState.isRunning ? .orange : .green
            )
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionButton("Sync (Download)", icon: "arrow.down.circle", isRunning: appState.isRunning) {
                await runSync(mode: .consumerOnly)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            ActionButton("Full Build + Cache", icon: "hammer", isRunning: appState.isRunning) {
                await runSync(mode: .producerAndConsumer)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(appState.recentActivities.prefix(8)) { activity in
                    HStack(spacing: 8) {
                        Image(systemName: activity.icon)
                            .font(.caption)
                            .foregroundStyle(activityColor(activity.type))
                            .frame(width: 16)
                        Text(activity.message)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(activity.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)

                    if activity.id != appState.recentActivities.prefix(8).last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        let locations = LocalCacheService.discoverCaches(scipioDir: scipioDir)
        totalSize = locations.first { $0.id == "project-xcframeworks" }?.size ?? 0
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
