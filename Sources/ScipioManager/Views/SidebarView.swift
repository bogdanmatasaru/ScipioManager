import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: $selection) {
            Section("Navigation") {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }

            Section("Quick Actions") {
                Button {
                    Task { await syncConsumerOnly() }
                } label: {
                    Label("Sync Frameworks", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appState.isRunning)

                Button {
                    Task { await syncFull() }
                } label: {
                    Label("Full Build + Cache", systemImage: "hammer")
                }
                .disabled(appState.isRunning)
            }

            if !appState.recentActivities.isEmpty {
                Section("Recent Activity") {
                    ForEach(appState.recentActivities.prefix(5)) { activity in
                        HStack(spacing: 6) {
                            Image(systemName: activity.icon)
                                .foregroundStyle(activityColor(activity.type))
                                .font(.caption)
                            Text(activity.message)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Scipio Manager")
    }

    private func activityColor(_ type: ActivityEntry.ActivityType) -> Color {
        switch type {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func syncConsumerOnly() async {
        guard let scipioDir = appState.scipioDir else { return }
        appState.isRunning = true
        appState.clearLog()
        defer { appState.isRunning = false }

        let service = ScipioService(scipioDir: scipioDir)
        do {
            let result = try await service.sync(mode: .consumerOnly) { line, stream in
                Task { @MainActor in
                    appState.appendLog(line, stream: stream)
                }
            }
            appState.lastSyncDate = Date()
            appState.addActivity("Synced \(result.frameworkCount) frameworks in \(result.elapsedFormatted)", type: .success)
        } catch {
            appState.addActivity("Sync failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func syncFull() async {
        guard let scipioDir = appState.scipioDir else { return }
        appState.isRunning = true
        appState.clearLog()
        defer { appState.isRunning = false }

        let service = ScipioService(scipioDir: scipioDir)
        do {
            let result = try await service.sync(mode: .producerAndConsumer, verbose: true) { line, stream in
                Task { @MainActor in
                    appState.appendLog(line, stream: stream)
                }
            }
            appState.lastSyncDate = Date()
            appState.addActivity("Built + cached \(result.frameworkCount) frameworks in \(result.elapsedFormatted)", type: .success)
        } catch {
            appState.addActivity("Build failed: \(error.localizedDescription)", type: .error)
        }
    }
}
