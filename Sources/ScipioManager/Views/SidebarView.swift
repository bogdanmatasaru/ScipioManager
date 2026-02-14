import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarSection.allCases) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            statusFooter
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.isRunning ? .orange : .green)
                .frame(width: 7, height: 7)
            Text(appState.isRunning ? "Running..." : "Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
