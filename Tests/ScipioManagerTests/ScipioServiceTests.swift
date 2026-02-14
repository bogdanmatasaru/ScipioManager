import Testing
import Foundation
@testable import ScipioManager

@Suite("Scipio Service Tests")
struct ScipioServiceTests {

    // MARK: - SyncMode

    @Test("SyncMode raw values")
    func syncModeRawValues() {
        #expect(ScipioService.SyncMode.producerAndConsumer.rawValue == "Producer + Consumer")
        #expect(ScipioService.SyncMode.consumerOnly.rawValue == "Consumer Only")
    }

    // MARK: - SyncResult

    @Test("SyncResult elapsed formatted for seconds")
    func syncResultSeconds() {
        let result = ScipioService.SyncResult(frameworkCount: 10, elapsed: 45.0, mode: .consumerOnly)
        #expect(result.elapsedFormatted == "45s")
    }

    @Test("SyncResult elapsed formatted for minutes")
    func syncResultMinutes() {
        let result = ScipioService.SyncResult(frameworkCount: 80, elapsed: 125.0, mode: .producerAndConsumer)
        #expect(result.elapsedFormatted == "2m 5s")
    }

    @Test("SyncResult elapsed formatted for zero")
    func syncResultZero() {
        let result = ScipioService.SyncResult(frameworkCount: 0, elapsed: 0, mode: .consumerOnly)
        #expect(result.elapsedFormatted == "0s")
    }

    // MARK: - ScipioError

    @Test("ScipioError descriptions")
    func errorDescriptions() {
        let buildError = ScipioService.ScipioError.runnerBuildFailed(exitCode: 1)
        #expect(buildError.localizedDescription.contains("build failed"))
        #expect(buildError.localizedDescription.contains("1"))

        let syncError = ScipioService.ScipioError.syncFailed(exitCode: 65)
        #expect(syncError.localizedDescription.contains("sync failed"))
        #expect(syncError.localizedDescription.contains("65"))
    }

    // MARK: - Framework Discovery (with temp dirs)

    @Test("Runner existence check with fake dir")
    func runnerExistsFakeDir() async {
        let service = ScipioService(scipioDir: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID())"))
        let exists = await service.runnerExists
        #expect(exists == false)
    }

    @Test("Framework count with empty dir returns 0")
    func frameworkCountEmptyDir() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ScipioTests-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = ScipioService(scipioDir: tempDir)
        let count = await service.frameworkCount()
        #expect(count == 0)
    }

    @Test("Framework count with nonexistent dir returns 0")
    func frameworkCountNoDir() async {
        let service = ScipioService(scipioDir: URL(fileURLWithPath: "/tmp/no-such-dir-\(UUID())"))
        let count = await service.frameworkCount()
        #expect(count == 0)
    }

    @Test("Discover frameworks from empty dir returns empty")
    func discoverFrameworksEmpty() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ScipioTests-\(UUID())")
        let fwDir = tempDir.appendingPathComponent("Frameworks/XCFrameworks")
        try FileManager.default.createDirectory(at: fwDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = ScipioService(scipioDir: tempDir)
        let frameworks = try await service.discoverFrameworks()
        #expect(frameworks.isEmpty)
    }

    @Test("Discover frameworks finds xcframeworks with slices")
    func discoverFrameworksWithSlices() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ScipioTests-\(UUID())")
        let fwDir = tempDir.appendingPathComponent("Frameworks/XCFrameworks")
        let xcfw = fwDir.appendingPathComponent("TestLib.xcframework")
        let fm = FileManager.default

        try fm.createDirectory(at: xcfw.appendingPathComponent("ios-arm64"), withIntermediateDirectories: true)
        try fm.createDirectory(at: xcfw.appendingPathComponent("ios-arm64_x86_64-simulator"), withIntermediateDirectories: true)
        try "plist".write(to: xcfw.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        defer { try? fm.removeItem(at: tempDir) }

        let service = ScipioService(scipioDir: tempDir)
        let frameworks = try await service.discoverFrameworks()
        #expect(frameworks.count == 1)
        #expect(frameworks.first?.name == "TestLib")
        #expect(frameworks.first?.slices.count == 2)
    }
}
