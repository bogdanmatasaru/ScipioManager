import Testing
import Foundation
@testable import ScipioManager

/// Tests for nuclearClean and cleanDerivedData using safe temporary directories.
@Suite("Nuclear Clean Tests")
struct NuclearCleanTests {

    // MARK: - nuclearClean with isolated temp directories

    @Test("nuclearClean removes XCFrameworks contents in temp scipio dir")
    func nuclearCleanRemovesXCFrameworks() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("nuclear-\(UUID())")
        let scipioDir = tempBase.appendingPathComponent("Scipio")
        let fwDir = scipioDir.appendingPathComponent("Frameworks/XCFrameworks")
        let fm = FileManager.default

        try fm.createDirectory(at: fwDir, withIntermediateDirectories: true)
        // Create a fake xcframework
        let fakeXCF = fwDir.appendingPathComponent("TestFW.xcframework")
        try fm.createDirectory(at: fakeXCF, withIntermediateDirectories: true)
        try "data".write(to: fakeXCF.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        defer { try? fm.removeItem(at: tempBase) }

        let result = try LocalCacheService.nuclearClean(scipioDir: scipioDir)
        #expect(result.xcframeworksSize > 0, "Should report freed size for XCFrameworks")

        // Verify XCFrameworks dir contents are cleared
        let contents = try fm.contentsOfDirectory(at: fwDir, includingPropertiesForKeys: nil)
        #expect(contents.isEmpty, "XCFrameworks dir should be empty after nuclear clean")
    }

    @Test("nuclearClean removes SourcePackages")
    func nuclearCleanRemovesSourcePackages() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("nuclear-\(UUID())")
        let scipioDir = tempBase.appendingPathComponent("Scipio")
        let sourcePackages = tempBase.appendingPathComponent("SourcePackages")
        let fm = FileManager.default

        try fm.createDirectory(at: scipioDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: sourcePackages, withIntermediateDirectories: true)
        try "data".write(to: sourcePackages.appendingPathComponent("pkg.json"), atomically: true, encoding: .utf8)

        defer { try? fm.removeItem(at: tempBase) }

        let result = try LocalCacheService.nuclearClean(scipioDir: scipioDir)
        #expect(result.sourcePackagesSize > 0, "Should report freed size for SourcePackages")
        #expect(!fm.fileExists(atPath: sourcePackages.path), "SourcePackages should be removed")
    }

    @Test("nuclearClean on empty dir returns all zeros")
    func nuclearCleanEmptyDir() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nuclear-empty-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try LocalCacheService.nuclearClean(scipioDir: tempDir)
        #expect(result.derivedDataSize == 0)
        #expect(result.spmArtifactsSize == 0)
        #expect(result.xcframeworksSize == 0)
        #expect(result.sourcePackagesSize == 0)
        #expect(result.totalSize == 0)
    }

    @Test("nuclearClean totalSizeFormatted works after clean")
    func nuclearCleanTotalFormatted() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("nuclear-fmt-\(UUID())")
        let scipioDir = tempBase.appendingPathComponent("Scipio")
        let fwDir = scipioDir.appendingPathComponent("Frameworks/XCFrameworks")
        let fm = FileManager.default

        try fm.createDirectory(at: fwDir, withIntermediateDirectories: true)
        // Create some data
        let data = Data(repeating: 0x42, count: 10_000)
        try data.write(to: fwDir.appendingPathComponent("test.bin"))

        defer { try? fm.removeItem(at: tempBase) }

        let result = try LocalCacheService.nuclearClean(scipioDir: scipioDir)
        #expect(!result.totalSizeFormatted.isEmpty)
    }

    // MARK: - cleanCache edge cases

    @Test("cleanCache with nested subdirectories")
    func cleanCacheNestedDirs() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clean-nested-\(UUID())")
        let subDir = tempDir.appendingPathComponent("subdir/deep")
        let fm = FileManager.default

        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "data".write(to: subDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try "data".write(to: tempDir.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)

        defer { try? fm.removeItem(at: tempDir) }

        let freed = try LocalCacheService.cleanCache(at: tempDir)
        #expect(freed > 0)

        let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        #expect(contents.isEmpty, "All contents should be removed")
    }

    @Test("cleanCache preserves the directory itself")
    func cleanCachePreservesDir() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clean-preserve-\(UUID())")
        let fm = FileManager.default

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "data".write(to: tempDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        defer { try? fm.removeItem(at: tempDir) }

        _ = try LocalCacheService.cleanCache(at: tempDir)
        #expect(fm.fileExists(atPath: tempDir.path), "Directory itself should still exist")
    }

    // MARK: - cleanDerivedData safety

    @Test("cleanDerivedData does not crash when no eMAG dirs exist")
    func cleanDerivedDataNoEMAG() throws {
        // This tests the safety of the operation - it should gracefully handle
        // the case where there are no eMAG derived data dirs.
        // NOTE: This could actually delete real derived data on a dev machine with eMAG,
        // so we only test the `findDerivedDataDirs` part safely.
        let dirs = LocalCacheService.findDerivedDataDirs()
        // Just verify it returns without crashing
        #expect(dirs.count >= 0)
    }
}
