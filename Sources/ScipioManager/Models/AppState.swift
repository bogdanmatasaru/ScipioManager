import Foundation
import SwiftUI

/// Global observable application state.
@Observable
@MainActor
final class AppState {
    // MARK: - Navigation
    var selectedSection: SidebarSection = .dashboard

    // MARK: - Project Paths (auto-detected)
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
    var bucketConfig = BucketConfig.default

    // MARK: - Activity Log
    var recentActivities: [ActivityEntry] = []

    // MARK: - Initialization

    func detectProjectPaths() {
        // Try to detect Scipio directory relative to the executable or user-selected path
        let candidates = [
            // Running from within the eMAG project
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scipio"),
            // Common development path
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Projects/eMAG/Scipio"),
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Build/Package.swift").path) {
                scipioDir = candidate
                buildPackageURL = candidate.appendingPathComponent("Build/Package.swift")
                frameworksDir = candidate.appendingPathComponent("Frameworks/XCFrameworks")
                runnerBinaryURL = candidate.appendingPathComponent("Runner/.build/arm64-apple-macosx/release/ScipioRunner")
                hmacKeyURL = candidate.appendingPathComponent("gcs-hmac.json")
                return
            }
        }
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
