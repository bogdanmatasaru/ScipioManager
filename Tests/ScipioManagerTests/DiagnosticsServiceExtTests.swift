import Testing
import Foundation
@testable import ScipioManager

@Suite("Diagnostics Service Extended Tests")
struct DiagnosticsServiceExtTests {

    // MARK: - checkXCFrameworksExist

    @Test("XCFrameworks check fails for nonexistent directory")
    func xcframeworksNotFound() {
        let result = DiagnosticsService.checkXCFrameworksExist(
            at: URL(fileURLWithPath: "/tmp/no-such-dir-\(UUID())")
        )
        #expect(result.passed == false)
        #expect(result.category == .frameworks)
    }

    @Test("XCFrameworks check fails for empty directory")
    func xcframeworksEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkXCFrameworksExist(at: tempDir)
        #expect(result.passed == false)
    }

    // MARK: - checkAllSlices

    @Test("Slices check handles nonexistent directory")
    func slicesNonexistent() {
        let result = DiagnosticsService.checkAllSlices(
            at: URL(fileURLWithPath: "/tmp/no-such-\(UUID())")
        )
        #expect(result.passed == false)
    }

    @Test("Slices check passes for correctly structured framework")
    func slicesCorrect() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-slices-\(UUID())")
        let fwDir = tempDir.appendingPathComponent("Test.xcframework")
        try FileManager.default.createDirectory(at: fwDir.appendingPathComponent("ios-arm64"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fwDir.appendingPathComponent("ios-arm64_x86_64-simulator"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkAllSlices(at: tempDir)
        #expect(result.passed == true)
        #expect(result.detail.contains("1"))
    }

    @Test("Slices check detects missing simulator slice")
    func slicesMissingSim() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-slices2-\(UUID())")
        let fwDir = tempDir.appendingPathComponent("Broken.xcframework")
        try FileManager.default.createDirectory(at: fwDir.appendingPathComponent("ios-arm64"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkAllSlices(at: tempDir)
        #expect(result.passed == false)
        #expect(result.detail.contains("Broken"))
    }

    // MARK: - checkCredentials

    @Test("Credentials check fails for missing file")
    func credentialsMissing() {
        let result = DiagnosticsService.checkCredentials(
            hmacURL: URL(fileURLWithPath: "/tmp/no-\(UUID()).json")
        )
        #expect(result.passed == false)
        #expect(result.category == .credentials)
    }

    @Test("Credentials check passes for existing file")
    func credentialsFound() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("creds-\(UUID()).json")
        try "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = DiagnosticsService.checkCredentials(hmacURL: tempFile)
        #expect(result.passed == true)
    }

    // MARK: - checkRunnerBinary

    @Test("Runner binary check fails for nonexistent")
    func runnerMissing() {
        let result = DiagnosticsService.checkRunnerBinary(
            at: URL(fileURLWithPath: "/tmp/no-runner-\(UUID())")
        )
        #expect(result.passed == false)
        #expect(result.category == .toolchain)
    }

    // MARK: - checkPackageResolved

    @Test("Package.resolved check fails for missing file")
    func resolvedMissing() {
        let result = DiagnosticsService.checkPackageResolved(
            at: URL(fileURLWithPath: "/tmp/no-resolved-\(UUID())")
        )
        #expect(result.passed == false)
    }

    @Test("Package.resolved check passes for existing file")
    func resolvedFound() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("resolved-\(UUID())")
        try "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = DiagnosticsService.checkPackageResolved(at: tempFile)
        #expect(result.passed == true)
    }

    // MARK: - checkBuildPackage

    @Test("Build package check fails for missing file")
    func buildPackageMissing() {
        let result = DiagnosticsService.checkBuildPackage(
            at: URL(fileURLWithPath: "/tmp/no-pkg-\(UUID())")
        )
        #expect(result.passed == false)
    }

    @Test("Build package check fails for empty file")
    func buildPackageEmpty() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID()).swift")
        try "let x = 1".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = DiagnosticsService.checkBuildPackage(at: tempFile)
        #expect(result.passed == false)
    }

    // MARK: - checkSwiftToolchain

    @Test("Swift toolchain check succeeds")
    func swiftToolchain() async {
        let result = await DiagnosticsService.checkSwiftToolchain()
        #expect(result.passed == true)
        #expect(result.category == .toolchain)
        #expect(result.detail.contains("Swift"))
    }

    // MARK: - checkOrphans

    @Test("Orphans check handles missing directories gracefully")
    func orphansMissingDirs() async {
        let result = await DiagnosticsService.checkOrphans(
            frameworksDir: URL(fileURLWithPath: "/tmp/no-fw-\(UUID())"),
            buildPackage: URL(fileURLWithPath: "/tmp/no-pkg-\(UUID())")
        )
        #expect(result.passed == true) // Graceful fallback
    }
}
