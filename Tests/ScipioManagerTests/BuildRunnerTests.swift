import Testing
import Foundation
@testable import ScipioManager

/// Thread-safe isolated value for Sendable closure captures.
private final class IsolatedLines: @unchecked Sendable {
    private var _lines: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.lock()
        _lines.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _lines
    }
}

/// Tests for ScipioService buildRunner and sync operations using safe mock setups.
@Suite("Build Runner Tests")
struct BuildRunnerTests {

    // MARK: - buildRunner error handling

    @Test("buildRunner fails with bad package path")
    func buildRunnerBadPath() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("runner-test-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let service = ScipioService(scipioDir: tempDir)
        let captured = IsolatedLines()

        do {
            try await service.buildRunner { line, _ in
                captured.append(line)
            }
            Issue.record("buildRunner should throw for nonexistent Runner package")
        } catch let error as ScipioService.ScipioError {
            switch error {
            case .runnerBuildFailed(let code):
                #expect(code != 0, "Exit code should be non-zero for failed build")
            default:
                Issue.record("Expected runnerBuildFailed, got \(error)")
            }
        }

        // Should have emitted at least the initial compile message
        #expect(captured.lines.contains { $0.contains("Compiling") })
    }

    @Test("buildRunner emits initial BUILD log line")
    func buildRunnerEmitsInitialLog() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("runner-log-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let service = ScipioService(scipioDir: tempDir)
        let captured = IsolatedLines()

        do {
            try await service.buildRunner { line, _ in
                captured.append(line)
            }
        } catch {
            // Expected to fail - we just want the log lines
        }

        let allLines = captured.lines
        #expect(!allLines.isEmpty, "Should have emitted at least one log line")
        #expect(allLines.first?.contains("[BUILD]") == true, "First line should be the BUILD message")
    }

    // MARK: - sync operations error handling

    @Test("sync fails gracefully when runner doesn't exist and can't be built")
    func syncFailsWhenNoBinary() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-test-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let service = ScipioService(scipioDir: tempDir)

        do {
            _ = try await service.sync(mode: .consumerOnly) { _, _ in }
            Issue.record("sync should throw when runner can't be built")
        } catch let error as ScipioService.ScipioError {
            switch error {
            case .runnerBuildFailed:
                break // Expected
            case .syncFailed:
                break // Also acceptable
            }
        }
    }

    @Test("sync with verbose flag emits log lines")
    func syncVerboseEmitsLog() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-verbose-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let service = ScipioService(scipioDir: tempDir)
        let captured = IsolatedLines()

        do {
            _ = try await service.sync(mode: .producerAndConsumer, verbose: true) { line, _ in
                captured.append(line)
            }
        } catch {
            // Expected to fail - we check logs were emitted
        }

        let allLines = captured.lines
        let hasInfoLog = allLines.contains { $0.contains("[INFO]") || $0.contains("[BUILD]") || $0.contains("[SYNC]") }
        #expect(hasInfoLog, "Should have emitted build/sync log lines")
    }

    // MARK: - Real buildRunner (only if the project exists)

    @Test("buildRunner succeeds with real project",
          .enabled(if: FileManager.default.fileExists(
              atPath: NSHomeDirectory() + "/Projects/eMAG/Scipio/Runner/Package.swift")))
    func buildRunnerReal() async throws {
        let scipioDir = URL(fileURLWithPath: NSHomeDirectory() + "/Projects/eMAG/Scipio")
        let service = ScipioService(scipioDir: scipioDir)
        let captured = IsolatedLines()

        try await service.buildRunner { line, _ in
            captured.append(line)
        }

        let allLines = captured.lines
        let hasSuccess = allLines.contains { $0.contains("successfully") }
        #expect(hasSuccess, "Should report successful build")

        // Runner should now exist
        let exists = await service.runnerExists
        #expect(exists, "Runner binary should exist after build")
    }

    // MARK: - SyncResult formatting edge cases

    @Test("SyncResult elapsed formatting boundary at 60s")
    func syncResultBoundary() {
        let result = ScipioService.SyncResult(frameworkCount: 10, elapsed: 60.0, mode: .consumerOnly)
        #expect(result.elapsedFormatted == "1m 0s")
    }

    @Test("SyncResult elapsed formatting for large values")
    func syncResultLargeElapsed() {
        let result = ScipioService.SyncResult(frameworkCount: 80, elapsed: 3661.0, mode: .producerAndConsumer)
        #expect(result.elapsedFormatted == "61m 1s")
    }

    @Test("SyncResult sub-second rounds to 0s")
    func syncResultSubSecond() {
        let result = ScipioService.SyncResult(frameworkCount: 0, elapsed: 0.5, mode: .consumerOnly)
        #expect(result.elapsedFormatted == "0s")
    }

    // MARK: - runnerExists

    @Test("runnerExists returns false for empty directory")
    func runnerExistsEmpty() async {
        let service = ScipioService(scipioDir: URL(fileURLWithPath: "/tmp/empty-\(UUID())"))
        let exists = await service.runnerExists
        #expect(exists == false)
    }
}
