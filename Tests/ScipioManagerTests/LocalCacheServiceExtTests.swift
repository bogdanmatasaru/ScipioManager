import Testing
import Foundation
@testable import ScipioManager

@Suite("Local Cache Service Extended Tests")
struct LocalCacheServiceExtTests {

    // MARK: - CacheLocation Properties

    @Test("CacheLocation sizeFormatted")
    func cacheLocationFormatted() {
        let loc = LocalCacheService.CacheLocation(
            id: "test", name: "Test", path: URL(fileURLWithPath: "/tmp"),
            description: "Test location", exists: true, size: 5_000_000
        )
        #expect(!loc.sizeFormatted.isEmpty)
        #expect(loc.sizeFormatted.contains("M") || loc.sizeFormatted.contains("MB"))
    }

    @Test("CacheLocation zero size")
    func cacheLocationZeroSize() {
        let loc = LocalCacheService.CacheLocation(
            id: "z", name: "Zero", path: URL(fileURLWithPath: "/tmp"),
            description: "Zero", exists: false, size: 0
        )
        #expect(!loc.sizeFormatted.isEmpty)
    }

    // MARK: - directorySize

    @Test("Directory size for temp dir with files")
    func directorySizeWithFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-test-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create some files
        try "Hello".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("a.txt"))
        try "World!".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("b.txt"))

        let size = LocalCacheService.directorySize(tempDir)
        #expect(size > 0)
    }

    @Test("Directory size for nonexistent dir returns 0")
    func directorySizeNonexistent() {
        let size = LocalCacheService.directorySize(URL(fileURLWithPath: "/tmp/no-such-\(UUID())"))
        #expect(size == 0)
    }

    @Test("Directory size for empty dir returns 0")
    func directorySizeEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-empty-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let size = LocalCacheService.directorySize(tempDir)
        #expect(size == 0)
    }

    // MARK: - directoryExists

    @Test("Directory exists for temp dir")
    func directoryExistsTrue() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-exists-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(LocalCacheService.directoryExists(tempDir) == true)
    }

    @Test("Directory exists false for nonexistent")
    func directoryExistsFalse() {
        #expect(LocalCacheService.directoryExists(URL(fileURLWithPath: "/tmp/no-\(UUID())")) == false)
    }

    @Test("Directory exists false for file")
    func directoryExistsFalseForFile() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("cache-file-\(UUID())")
        try "data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        #expect(LocalCacheService.directoryExists(tempFile) == false)
    }

    // MARK: - cleanCache

    @Test("Clean cache removes contents")
    func cleanCacheRemovesContents() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-clean-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "data".write(to: tempDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let freed = try LocalCacheService.cleanCache(at: tempDir)
        #expect(freed > 0)

        // Directory should still exist but be empty
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        #expect(contents.isEmpty)
    }

    @Test("Clean cache on nonexistent returns 0")
    func cleanCacheNonexistent() throws {
        let freed = try LocalCacheService.cleanCache(at: URL(fileURLWithPath: "/tmp/no-\(UUID())"))
        #expect(freed == 0)
    }

    // MARK: - NuclearCleanResult

    @Test("NuclearCleanResult totalSize sums all components")
    func nuclearCleanTotalSize() {
        var result = LocalCacheService.NuclearCleanResult()
        result.derivedDataSize = 100
        result.spmArtifactsSize = 200
        result.xcframeworksSize = 300
        result.sourcePackagesSize = 400
        #expect(result.totalSize == 1000)
    }

    @Test("NuclearCleanResult totalSizeFormatted")
    func nuclearCleanFormatted() {
        var result = LocalCacheService.NuclearCleanResult()
        result.derivedDataSize = 5_000_000
        #expect(!result.totalSizeFormatted.isEmpty)
    }

    @Test("NuclearCleanResult defaults to zero")
    func nuclearCleanDefaults() {
        let result = LocalCacheService.NuclearCleanResult()
        #expect(result.totalSize == 0)
    }

    // MARK: - discoverCaches

    @Test("Discover caches returns expected locations")
    func discoverCachesIDs() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("scipio-discover-\(UUID())")
        let locations = LocalCacheService.discoverCaches(scipioDir: tempDir)

        let ids = Set(locations.map(\.id))
        #expect(ids.contains("derived-data"))
        #expect(ids.contains("spm-cache"))
        #expect(ids.contains("spm-artifacts"))
        #expect(ids.contains("scipio-local"))
        #expect(ids.contains("project-xcframeworks"))
        #expect(ids.contains("runner-build"))
        #expect(ids.contains("source-packages"))
        #expect(locations.count == 7)
    }

    @Test("Discover caches descriptions are non-empty")
    func discoverCachesDescriptions() {
        let tempDir = URL(fileURLWithPath: "/tmp")
        let locations = LocalCacheService.discoverCaches(scipioDir: tempDir)
        for loc in locations {
            #expect(!loc.name.isEmpty)
            #expect(!loc.description.isEmpty)
        }
    }

    // MARK: - findDerivedDataDirs

    @Test("findDerivedDataDirs returns without crashing")
    func findDerivedData() {
        // Just ensure it doesn't crash and returns an array
        let dirs = LocalCacheService.findDerivedDataDirs()
        #expect(dirs.count >= 0) // Just verifying the call succeeds
    }

    @Test("findDerivedDataDirs with specific prefix")
    func findDerivedDataWithPrefix() {
        // A unique prefix that won't match anything
        let dirs = LocalCacheService.findDerivedDataDirs(prefix: "UniqueTestPrefix-\(UUID())-")
        #expect(dirs.isEmpty)
    }
}
