import Testing
import Foundation
@testable import ScipioManager

@Suite("Local Cache Service Tests")
struct LocalCacheServiceTests {

    @Test("Directory size calculation")
    func directorySize() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write 1KB of data
        let data = Data(repeating: 0x42, count: 1024)
        try data.write(to: tempDir.appendingPathComponent("test.dat"))

        let size = LocalCacheService.directorySize(tempDir)
        #expect(size >= 1024)
    }

    @Test("Directory exists check")
    func directoryExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(LocalCacheService.directoryExists(tempDir) == true)
        #expect(LocalCacheService.directoryExists(URL(fileURLWithPath: "/nonexistent")) == false)
    }

    @Test("Clean cache removes contents")
    func cleanCache() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data(repeating: 0x42, count: 512).write(to: tempDir.appendingPathComponent("file1.dat"))
        try Data(repeating: 0x43, count: 512).write(to: tempDir.appendingPathComponent("file2.dat"))

        let freed = try LocalCacheService.cleanCache(at: tempDir)
        #expect(freed >= 1024)

        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        #expect(contents.isEmpty)
    }

    @Test("Discover caches returns valid structure")
    func discoverCaches() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scipioDir = tempDir.appendingPathComponent("Scipio")
        try FileManager.default.createDirectory(
            at: scipioDir.appendingPathComponent("Frameworks/XCFrameworks"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let locations = LocalCacheService.discoverCaches(scipioDir: scipioDir)
        #expect(!locations.isEmpty)
        #expect(locations.contains { $0.id == "project-xcframeworks" })
        #expect(locations.contains { $0.id == "scipio-local" })
    }

    @Test("Cache location has correct properties")
    func cacheLocationProperties() {
        let loc = LocalCacheService.CacheLocation(
            id: "test",
            name: "Test Cache",
            path: URL(fileURLWithPath: "/tmp"),
            description: "Test description",
            exists: true,
            size: 1024 * 1024
        )
        #expect(loc.sizeFormatted.contains("MB") || loc.sizeFormatted.contains("KB"))
        #expect(loc.id == "test")
    }
}
