import Testing
import Foundation
@testable import ScipioManager

@Suite("Diagnostics Service Tests")
struct DiagnosticsServiceTests {

    @Test("XCFrameworks check passes with frameworks present")
    func xcframeworksPresent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let xcfDir = tempDir.appendingPathComponent("Frameworks/XCFrameworks")
        let fw = xcfDir.appendingPathComponent("Test.xcframework")
        try FileManager.default.createDirectory(at: fw.appendingPathComponent("ios-arm64"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fw.appendingPathComponent("ios-arm64_x86_64-simulator"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkXCFrameworksExist(at: xcfDir)
        #expect(result.passed == true)
        #expect(result.detail.contains("1"))
    }

    @Test("XCFrameworks check fails with empty directory")
    func xcframeworksEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let xcfDir = tempDir.appendingPathComponent("Frameworks/XCFrameworks")
        try FileManager.default.createDirectory(at: xcfDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkXCFrameworksExist(at: xcfDir)
        #expect(result.passed == false)
    }

    @Test("Slice check passes when both slices present")
    func sliceCheckPass() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let xcfDir = tempDir.appendingPathComponent("Frameworks/XCFrameworks")
        let fw = xcfDir.appendingPathComponent("Test.xcframework")
        try FileManager.default.createDirectory(at: fw.appendingPathComponent("ios-arm64"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fw.appendingPathComponent("ios-arm64_x86_64-simulator"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkAllSlices(at: xcfDir)
        #expect(result.passed == true)
    }

    @Test("Slice check fails when simulator slice missing")
    func sliceCheckFail() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let xcfDir = tempDir.appendingPathComponent("Frameworks/XCFrameworks")
        let fw = xcfDir.appendingPathComponent("Broken.xcframework")
        try FileManager.default.createDirectory(at: fw.appendingPathComponent("ios-arm64"), withIntermediateDirectories: true)
        // Missing simulator slice
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkAllSlices(at: xcfDir)
        #expect(result.passed == false)
        #expect(result.detail.contains("Broken"))
    }

    @Test("Credential check passes with file present")
    func credentialCheckPass() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let keyFile = tempDir.appendingPathComponent("gcs-hmac.json")
        try "{}".write(to: keyFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkCredentials(hmacURL: keyFile)
        #expect(result.passed == true)
    }

    @Test("Credential check fails with missing file")
    func credentialCheckFail() {
        let fakePath = URL(fileURLWithPath: "/nonexistent/gcs-hmac.json")
        let result = DiagnosticsService.checkCredentials(hmacURL: fakePath)
        #expect(result.passed == false)
    }

    @Test("Runner binary check correctly detects /usr/bin/swift")
    func runnerBinaryExists() {
        let swiftURL = URL(fileURLWithPath: "/usr/bin/swift")
        let result = DiagnosticsService.checkRunnerBinary(at: swiftURL)
        #expect(result.passed == true)
    }

    @Test("Build package check parses valid file")
    func buildPackageValid() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let pkgFile = tempDir.appendingPathComponent("Package.swift")
        let content = """
        let package = Package(
            dependencies: [
                .package(url: "https://github.com/test/lib.git", exact: "1.0.0"),
            ],
            targets: [
                .target(dependencies: [
                    .product(name: "Lib", package: "lib"),
                ])
            ]
        )
        """
        try content.write(to: pkgFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = DiagnosticsService.checkBuildPackage(at: pkgFile)
        #expect(result.passed == true)
        #expect(result.detail.contains("1"))
    }
}
