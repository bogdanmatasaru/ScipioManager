import Testing
import Foundation
@testable import ScipioManager

@Suite("CacheEntry Tests")
struct CacheEntryTests {

    // MARK: - CacheEntry Properties

    @Test("ID is derived from key")
    func idDerivation() {
        let entry = CacheEntry(key: "XCFrameworks/Alamofire/abc123.zip", size: 1024, lastModified: Date(), etag: "e1")
        #expect(entry.id == "XCFrameworks/Alamofire/abc123.zip")
    }

    @Test("Framework name extracted from 3-segment key")
    func frameworkNameTypical() {
        let entry = CacheEntry(key: "XCFrameworks/Alamofire/abc123.zip", size: 0, lastModified: Date(), etag: "")
        #expect(entry.frameworkName == "Alamofire")
    }

    @Test("Framework name extracted from deep key path")
    func frameworkNameDeep() {
        let entry = CacheEntry(key: "prefix/sub/RxSwift/hash/file.zip", size: 0, lastModified: Date(), etag: "")
        #expect(entry.frameworkName == "hash")
    }

    @Test("Framework name from .version file format")
    func frameworkNameVersionFile() {
        let entry = CacheEntry(key: "XCFrameworks/.Alamofire.version", size: 0, lastModified: Date(), etag: "")
        #expect(entry.frameworkName == "Alamofire")
    }

    @Test("Framework name fallback for short keys")
    func frameworkNameShortKey() {
        let entry = CacheEntry(key: "singleSegment", size: 0, lastModified: Date(), etag: "")
        #expect(entry.frameworkName == "singleSegment")

        let entry2 = CacheEntry(key: "a/b", size: 0, lastModified: Date(), etag: "")
        #expect(entry2.frameworkName == "b")
    }

    @Test("Cache hash extracted correctly")
    func cacheHashExtraction() {
        let entry = CacheEntry(key: "XCFrameworks/Alamofire/abc123.zip", size: 0, lastModified: Date(), etag: "")
        #expect(entry.cacheHash == "abc123")
    }

    @Test("Cache hash strips .zip extension")
    func cacheHashStripsZip() {
        let entry = CacheEntry(key: "prefix/framework/hash-value.zip", size: 0, lastModified: Date(), etag: "")
        #expect(entry.cacheHash == "hash-value")
    }

    @Test("Cache hash for key without .zip")
    func cacheHashNoZip() {
        let entry = CacheEntry(key: "prefix/framework/rawvalue", size: 0, lastModified: Date(), etag: "")
        #expect(entry.cacheHash == "rawvalue")
    }

    @Test("Cache hash empty key")
    func cacheHashEmpty() {
        let entry = CacheEntry(key: "", size: 0, lastModified: Date(), etag: "")
        #expect(entry.cacheHash == "")
    }

    @Test("Size formatted produces human-readable string")
    func sizeFormatted() {
        let entry = CacheEntry(key: "k", size: 1_048_576, lastModified: Date(), etag: "")
        #expect(!entry.sizeFormatted.isEmpty)
        #expect(entry.sizeFormatted.contains("MB") || entry.sizeFormatted.contains("M"))
    }

    @Test("Size formatted for zero bytes")
    func sizeFormattedZero() {
        let entry = CacheEntry(key: "k", size: 0, lastModified: Date(), etag: "")
        #expect(!entry.sizeFormatted.isEmpty)
    }

    @Test("Last modified formatted produces non-empty string")
    func lastModifiedFormatted() {
        let entry = CacheEntry(key: "k", size: 0, lastModified: Date().addingTimeInterval(-3600), etag: "")
        #expect(!entry.lastModifiedFormatted.isEmpty)
    }

    @Test("Hashable conformance works")
    func hashable() {
        let date = Date()
        let entry1 = CacheEntry(key: "k1", size: 100, lastModified: date, etag: "e1")
        let entry2 = CacheEntry(key: "k2", size: 200, lastModified: date, etag: "e2")
        let entry3 = CacheEntry(key: "k1", size: 100, lastModified: date, etag: "e1")
        let set: Set<CacheEntry> = [entry1, entry2, entry3]
        #expect(set.count == 2)
    }

    // MARK: - CacheFrameworkGroup

    @Test("Group totalSize sums entries")
    func groupTotalSize() {
        let entries = [
            CacheEntry(key: "a/b/c.zip", size: 100, lastModified: Date(), etag: ""),
            CacheEntry(key: "a/b/d.zip", size: 250, lastModified: Date(), etag: ""),
        ]
        let group = CacheFrameworkGroup(name: "TestFW", entries: entries)
        #expect(group.totalSize == 350)
    }

    @Test("Group totalSizeFormatted produces string")
    func groupTotalSizeFormatted() {
        let entries = [CacheEntry(key: "k", size: 5_000_000, lastModified: Date(), etag: "")]
        let group = CacheFrameworkGroup(name: "TestFW", entries: entries)
        #expect(!group.totalSizeFormatted.isEmpty)
    }

    @Test("Group entryCount matches")
    func groupEntryCount() {
        let entries = [
            CacheEntry(key: "k1", size: 0, lastModified: Date(), etag: ""),
            CacheEntry(key: "k2", size: 0, lastModified: Date(), etag: ""),
            CacheEntry(key: "k3", size: 0, lastModified: Date(), etag: ""),
        ]
        let group = CacheFrameworkGroup(name: "G", entries: entries)
        #expect(group.entryCount == 3)
    }

    @Test("Group latestModified returns max date")
    func groupLatestModified() {
        let old = Date().addingTimeInterval(-3600)
        let newer = Date().addingTimeInterval(-60)
        let entries = [
            CacheEntry(key: "k1", size: 0, lastModified: old, etag: ""),
            CacheEntry(key: "k2", size: 0, lastModified: newer, etag: ""),
        ]
        let group = CacheFrameworkGroup(name: "G", entries: entries)
        #expect(group.latestModified == newer)
    }

    @Test("Group latestModified nil for empty entries")
    func groupLatestModifiedEmpty() {
        let group = CacheFrameworkGroup(name: "G", entries: [])
        #expect(group.latestModified == nil)
    }

    @Test("Group id is name")
    func groupId() {
        let group = CacheFrameworkGroup(name: "MyFramework", entries: [])
        #expect(group.id == "MyFramework")
    }

    @Test("Group hashable conformance")
    func groupHashable() {
        let g1 = CacheFrameworkGroup(name: "A", entries: [])
        let g2 = CacheFrameworkGroup(name: "B", entries: [])
        let g3 = CacheFrameworkGroup(name: "A", entries: [])
        let set: Set<CacheFrameworkGroup> = [g1, g2, g3]
        #expect(set.count == 2)
    }
}
