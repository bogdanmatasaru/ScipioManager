import Foundation
import SwiftUI

/// Global observable application state.
@Observable
@MainActor
final class AppState {
    // MARK: - Configuration
    let config: AppConfig

    // MARK: - Navigation
    var selectedSection: SidebarSection = .dashboard

    // MARK: - Project Paths (auto-detected or configured)
    var scipioDir: URL?
    var buildPackageURL: URL?
    var frameworksDir: URL?
    var runnerBinaryURL: URL?
    var hmacKeyURL: URL?

    // MARK: - Runtime State
    var frameworks: [FrameworkInfo] = []
    var dependencies: [ParsedDependency] = []
    var bucketEntries: [CacheEntry] = []
    var diagnosticResults: [DiagnosticResult] = []
    var logLines: [LogLine] = []
    var isRunning = false
    var lastSyncDate: Date?
    var bucketConfig: BucketConfig

    // MARK: - Activity Log
    var recentActivities: [ActivityEntry] = []

    // MARK: - Initialization

    init(config: AppConfig = .load()) {
        self.config = config
        self.bucketConfig = BucketConfig(
            bucketName: config.bucket.name,
            endpoint: config.bucket.endpoint,
            storagePrefix: config.bucket.storagePrefix,
            region: config.bucket.region
        )
    }

    /// Detect project paths from config or by scanning common locations.
    func detectProjectPaths() {
        // Priority 1: Explicit path from config
        if let configPath = config.scipioPath {
            let url = URL(fileURLWithPath: configPath)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Build/Package.swift").path) {
                applyScipioDir(url)
                return
            }
        }

        // Priority 2: Scan parent directories of the app bundle
        if let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent() as URL? {
            // Check if the app is inside a Scipio/Tools folder
            let candidate = bundleDir.deletingLastPathComponent() // Go up from Tools/
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Build/Package.swift").path) {
                applyScipioDir(candidate)
                return
            }
        }

        // Priority 3: Scan common locations
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scipio"),
            home.appendingPathComponent("Developer/Scipio"),
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Build/Package.swift").path) {
                applyScipioDir(candidate)
                return
            }
        }
    }

    private func applyScipioDir(_ url: URL) {
        scipioDir = url
        buildPackageURL = url.appendingPathComponent("Build/Package.swift")
        frameworksDir = url.appendingPathComponent("Frameworks/XCFrameworks")
        runnerBinaryURL = Self.resolveRunnerBinary(in: url)
        hmacKeyURL = url.appendingPathComponent(config.hmacKeyFilename)
    }

    /// Locate the ScipioRunner binary by checking known locations in priority order:
    /// 1. `Runner/bin/ScipioRunner` — pre-built universal binary (committed to git)
    /// 2. `Runner/.build/release/ScipioRunner` — built from source (symlink, arch-agnostic)
    static func resolveRunnerBinary(in scipioDir: URL) -> URL {
        let candidates = [
            scipioDir.appendingPathComponent("Runner/bin/ScipioRunner"),
            scipioDir.appendingPathComponent("Runner/.build/release/ScipioRunner"),
        ]
        for candidate in candidates {
            if ProcessRunner.executableExists(at: candidate.path) {
                return candidate
            }
        }
        // Default to the pre-built location even if it doesn't exist yet
        return candidates[0]
    }

    /// Auto-detect the DerivedData folder prefix for this project.
    ///
    /// Resolution order:
    /// 1. Explicit `derived_data_prefix` from config (override)
    /// 2. Name of the first `.xcworkspace` found next to the Scipio directory
    /// 3. Name of the first `.xcodeproj` found next to the Scipio directory
    /// 4. `nil` — all DerivedData folders are eligible for cleanup
    var resolvedDerivedDataPrefix: String? {
        // 1. Explicit config override
        if let explicit = config.derivedDataPrefix {
            return explicit
        }
        // 2. Auto-detect from Xcode workspace/project in parent of scipioDir
        guard let scipioDir = scipioDir else { return nil }
        let projectRoot = scipioDir.deletingLastPathComponent()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        // Prefer .xcworkspace (Xcode uses the workspace name for DerivedData)
        if let workspace = contents.first(where: { $0.pathExtension == "xcworkspace" }) {
            return workspace.deletingPathExtension().lastPathComponent + "-"
        }
        // Fall back to .xcodeproj
        if let project = contents.first(where: { $0.pathExtension == "xcodeproj" }) {
            return project.deletingPathExtension().lastPathComponent + "-"
        }
        return nil
    }

    func addActivity(_ message: String, type: ActivityEntry.ActivityType = .info) {
        let entry = ActivityEntry(message: message, type: type, timestamp: Date())
        recentActivities.insert(entry, at: 0)
        if recentActivities.count > 50 {
            recentActivities = Array(recentActivities.prefix(50))
        }
    }

    func appendLog(_ line: String, stream: LogLine.Stream = .stdout) {
        logLines.append(LogLine(text: line, stream: stream, timestamp: Date()))
    }

    func clearLog() {
        logLines.removeAll()
    }
}

// MARK: - Supporting Types

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case frameworks = "Frameworks"
    case cache = "Cache"
    case bucket = "GCS Bucket"
    case diagnostics = "Diagnostics"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .frameworks: return "shippingbox"
        case .cache: return "internaldrive"
        case .bucket: return "cloud"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }
}

struct LogLine: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let stream: Stream
    let timestamp: Date

    enum Stream: Sendable {
        case stdout, stderr
    }
}

struct ActivityEntry: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let type: ActivityType
    let timestamp: Date

    enum ActivityType: Sendable {
        case info, success, warning, error
    }

    var icon: String {
        switch type {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}

struct DiagnosticResult: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
    let category: Category

    enum Category: String, Sendable, CaseIterable {
        case frameworks = "Frameworks"
        case cache = "Cache"
        case credentials = "Credentials"
        case toolchain = "Toolchain"
    }
}
