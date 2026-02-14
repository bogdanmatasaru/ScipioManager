import Testing
import Foundation
@testable import ScipioManager

@Suite("AppState Tests")
struct AppStateTests {

    // MARK: - SidebarSection

    @Test("All sidebar sections defined")
    func sidebarSections() {
        let sections = SidebarSection.allCases
        #expect(sections.count == 6)
        #expect(sections.contains(.dashboard))
        #expect(sections.contains(.frameworks))
        #expect(sections.contains(.cache))
        #expect(sections.contains(.bucket))
        #expect(sections.contains(.diagnostics))
        #expect(sections.contains(.settings))
    }

    @Test("Sidebar section IDs match raw values")
    func sidebarSectionIds() {
        for section in SidebarSection.allCases {
            #expect(section.id == section.rawValue)
        }
    }

    @Test("Sidebar section icons are non-empty")
    func sidebarSectionIcons() {
        for section in SidebarSection.allCases {
            #expect(!section.icon.isEmpty, "\(section.rawValue) icon should not be empty")
        }
    }

    @Test("Sidebar section raw values")
    func sidebarSectionRawValues() {
        #expect(SidebarSection.dashboard.rawValue == "Dashboard")
        #expect(SidebarSection.frameworks.rawValue == "Frameworks")
        #expect(SidebarSection.cache.rawValue == "Cache")
        #expect(SidebarSection.bucket.rawValue == "GCS Bucket")
        #expect(SidebarSection.diagnostics.rawValue == "Diagnostics")
        #expect(SidebarSection.settings.rawValue == "Settings")
    }

    // MARK: - ActivityEntry

    @Test("Activity entry icons per type")
    func activityIcons() {
        let info = ActivityEntry(message: "m", type: .info, timestamp: Date())
        #expect(info.icon == "info.circle")

        let success = ActivityEntry(message: "m", type: .success, timestamp: Date())
        #expect(success.icon == "checkmark.circle")

        let warning = ActivityEntry(message: "m", type: .warning, timestamp: Date())
        #expect(warning.icon == "exclamationmark.triangle")

        let error = ActivityEntry(message: "m", type: .error, timestamp: Date())
        #expect(error.icon == "xmark.circle")
    }

    @Test("Activity entries have unique IDs")
    func activityUniqueIds() {
        let a1 = ActivityEntry(message: "same", type: .info, timestamp: Date())
        let a2 = ActivityEntry(message: "same", type: .info, timestamp: Date())
        #expect(a1.id != a2.id)
    }

    // MARK: - LogLine

    @Test("LogLine has unique ID")
    func logLineUniqueId() {
        let l1 = LogLine(text: "line", stream: .stdout, timestamp: Date())
        let l2 = LogLine(text: "line", stream: .stdout, timestamp: Date())
        #expect(l1.id != l2.id)
    }

    @Test("LogLine stream types")
    func logLineStreams() {
        let stdout = LogLine(text: "out", stream: .stdout, timestamp: Date())
        let stderr = LogLine(text: "err", stream: .stderr, timestamp: Date())
        #expect(stdout.text == "out")
        #expect(stderr.text == "err")
    }

    // MARK: - DiagnosticResult

    @Test("DiagnosticResult categories")
    func diagnosticCategories() {
        let cats = DiagnosticResult.Category.allCases
        #expect(cats.count == 4)
        #expect(DiagnosticResult.Category.frameworks.rawValue == "Frameworks")
        #expect(DiagnosticResult.Category.cache.rawValue == "Cache")
        #expect(DiagnosticResult.Category.credentials.rawValue == "Credentials")
        #expect(DiagnosticResult.Category.toolchain.rawValue == "Toolchain")
    }

    @Test("DiagnosticResult properties")
    func diagnosticResult() {
        let result = DiagnosticResult(name: "Test", passed: true, detail: "All good", category: .frameworks)
        #expect(result.name == "Test")
        #expect(result.passed == true)
        #expect(result.detail == "All good")
        #expect(result.category == .frameworks)
    }

    @Test("DiagnosticResult unique IDs")
    func diagnosticResultIds() {
        let r1 = DiagnosticResult(name: "Same", passed: true, detail: "", category: .cache)
        let r2 = DiagnosticResult(name: "Same", passed: true, detail: "", category: .cache)
        #expect(r1.id != r2.id)
    }

    // MARK: - AppState (MainActor)

    @Test("AppState defaults")
    @MainActor
    func defaults() {
        let state = AppState(config: .default)
        #expect(state.selectedSection == .dashboard)
        #expect(state.scipioDir == nil)
        #expect(state.buildPackageURL == nil)
        #expect(state.frameworks.isEmpty)
        #expect(state.dependencies.isEmpty)
        #expect(state.bucketEntries.isEmpty)
        #expect(state.diagnosticResults.isEmpty)
        #expect(state.logLines.isEmpty)
        #expect(state.isRunning == false)
        #expect(state.lastSyncDate == nil)
        #expect(state.recentActivities.isEmpty)
    }

    @Test("AppState addActivity inserts at front")
    @MainActor
    func addActivity() {
        let state = AppState(config: .default)
        state.addActivity("First", type: .info)
        state.addActivity("Second", type: .success)
        #expect(state.recentActivities.count == 2)
        #expect(state.recentActivities[0].message == "Second")
        #expect(state.recentActivities[1].message == "First")
    }

    @Test("AppState addActivity limits to 50")
    @MainActor
    func addActivityLimit() {
        let state = AppState(config: .default)
        for i in 0..<60 {
            state.addActivity("Activity \(i)")
        }
        #expect(state.recentActivities.count == 50)
    }

    @Test("AppState appendLog and clearLog")
    @MainActor
    func logManagement() {
        let state = AppState(config: .default)
        state.appendLog("line1", stream: .stdout)
        state.appendLog("line2", stream: .stderr)
        #expect(state.logLines.count == 2)
        #expect(state.logLines[0].text == "line1")
        #expect(state.logLines[0].stream == .stdout)
        #expect(state.logLines[1].stream == .stderr)

        state.clearLog()
        #expect(state.logLines.isEmpty)
    }

    @Test("AppState bucket config from AppConfig")
    @MainActor
    func bucketConfigFromAppConfig() {
        var config = AppConfig.default
        config.bucket.name = "my-test-bucket"
        config.bucket.region = "us-east1"
        let state = AppState(config: config)
        #expect(state.bucketConfig.bucketName == "my-test-bucket")
        #expect(state.bucketConfig.region == "us-east1")
    }

    // MARK: - Resolved DerivedData Prefix

    @Test("resolvedDerivedDataPrefix returns nil when no scipioDir")
    @MainActor
    func resolvedPrefixNil() {
        let state = AppState(config: .default)
        #expect(state.resolvedDerivedDataPrefix == nil)
    }

    @Test("resolvedDerivedDataPrefix uses explicit config when set")
    @MainActor
    func resolvedPrefixExplicit() {
        var config = AppConfig.default
        config.derivedDataPrefix = "Explicit-"
        let state = AppState(config: config)
        state.scipioDir = URL(fileURLWithPath: "/tmp")
        #expect(state.resolvedDerivedDataPrefix == "Explicit-")
    }

    @Test("resolvedDerivedDataPrefix auto-detects from xcworkspace")
    @MainActor
    func resolvedPrefixWorkspace() throws {
        // Create a temp project structure: /tmp/TestProject/Scipio + MyApp.xcworkspace
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestProject-\(UUID())")
        let scipioDir = projectRoot.appendingPathComponent("Scipio")
        let workspace = projectRoot.appendingPathComponent("MyApp.xcworkspace")
        try FileManager.default.createDirectory(at: scipioDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let state = AppState(config: .default)
        state.scipioDir = scipioDir
        #expect(state.resolvedDerivedDataPrefix == "MyApp-")
    }

    @Test("resolvedDerivedDataPrefix falls back to xcodeproj")
    @MainActor
    func resolvedPrefixProject() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestProject-\(UUID())")
        let scipioDir = projectRoot.appendingPathComponent("Scipio")
        let project = projectRoot.appendingPathComponent("MyProject.xcodeproj")
        try FileManager.default.createDirectory(at: scipioDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let state = AppState(config: .default)
        state.scipioDir = scipioDir
        #expect(state.resolvedDerivedDataPrefix == "MyProject-")
    }

    @Test("resolvedDerivedDataPrefix prefers xcworkspace over xcodeproj")
    @MainActor
    func resolvedPrefixPreference() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestProject-\(UUID())")
        let scipioDir = projectRoot.appendingPathComponent("Scipio")
        let workspace = projectRoot.appendingPathComponent("AppWorkspace.xcworkspace")
        let project = projectRoot.appendingPathComponent("AppProject.xcodeproj")
        try FileManager.default.createDirectory(at: scipioDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let state = AppState(config: .default)
        state.scipioDir = scipioDir
        #expect(state.resolvedDerivedDataPrefix == "AppWorkspace-")
    }

    // MARK: - BuildConfiguration

    @Test("Current build configuration values")
    func currentConfig() {
        let config = BuildConfiguration.current
        #expect(config.buildConfig == "release")
        #expect(config.frameworkType == "static")
        #expect(config.simulatorSupported == true)
        #expect(config.debugSymbolsEmbedded == false)
        #expect(config.libraryEvolution == false)
        #expect(config.stripDWARF == true)
    }

    // MARK: - BucketConfig

    @Test("Default bucket config has empty bucket name")
    func defaultBucketConfig() {
        let config = BucketConfig.default
        #expect(config.bucketName == "")
        #expect(config.endpoint == "https://storage.googleapis.com")
        #expect(config.storagePrefix == "XCFrameworks/")
        #expect(config.region == "auto")
    }

    @Test("BucketConfig Codable")
    func bucketConfigCodable() throws {
        let original = BucketConfig(bucketName: "test", endpoint: "https://test.com", storagePrefix: "pfx/", region: "us-east1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BucketConfig.self, from: data)
        #expect(decoded.bucketName == "test")
        #expect(decoded.endpoint == "https://test.com")
        #expect(decoded.storagePrefix == "pfx/")
        #expect(decoded.region == "us-east1")
    }

    // MARK: - ParsedDependency

    @Test("ParsedDependency display version for branch")
    func branchDisplayVersion() {
        let dep = ParsedDependency(url: "u", version: "main", versionType: .branch, packageName: "p", products: [], isCustomFork: false)
        #expect(dep.displayVersion == "branch: main")
    }
}
