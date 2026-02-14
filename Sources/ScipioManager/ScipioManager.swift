import SwiftUI

@main
struct ScipioManagerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appState.detectProjectPaths()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
        }
        #endif
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView(selection: $state.selectedSection)
        } detail: {
            detailView(for: appState.selectedSection)
        }
    }

    @ViewBuilder
    private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .frameworks:
            FrameworksView()
        case .cache:
            CacheView()
        case .bucket:
            BucketBrowserView()
        case .diagnostics:
            DiagnosticsView()
        case .settings:
            SettingsView()
        }
    }
}
