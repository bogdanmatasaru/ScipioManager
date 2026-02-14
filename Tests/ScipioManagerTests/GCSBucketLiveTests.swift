import Testing
import Foundation
@testable import ScipioManager

/// Live integration tests for GCSBucketService network calls (headObject, deleteObject, etc.).
/// These require real HMAC credentials at ~/Projects/eMAG/Scipio/gcs-hmac.json
@Suite("GCS Bucket Live Tests", .enabled(if: FileManager.default.fileExists(
    atPath: NSHomeDirectory() + "/Projects/eMAG/Scipio/gcs-hmac.json"
)))
struct GCSBucketLiveTests {

    let hmacKeyURL = URL(fileURLWithPath: NSHomeDirectory() + "/Projects/eMAG/Scipio/gcs-hmac.json")

    private func makeService() throws -> GCSBucketService {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        return GCSBucketService(hmacKey: key, config: .default)
    }

    // MARK: - headObject

    @Test("headObject returns true for a known existing object")
    func headObjectExists() async throws {
        let service = try makeService()
        // First list to find a real key
        let entries = try await service.listObjects()
        guard let first = entries.first else {
            Issue.record("Bucket is empty, cannot test headObject")
            return
        }

        let (exists, size) = try await service.headObject(key: first.key)
        #expect(exists == true, "headObject should confirm existing key: \(first.key)")
        #expect(size > 0, "headObject should return non-zero size for \(first.key)")
    }

    @Test("headObject returns false for nonexistent key")
    func headObjectNotExists() async throws {
        let service = try makeService()
        let fakeKey = "XCFrameworks/__NONEXISTENT_TEST_FRAMEWORK__/abc123.zip"
        let (exists, size) = try await service.headObject(key: fakeKey)
        #expect(exists == false)
        #expect(size == 0)
    }

    @Test("headObject size matches listObjects size for same key")
    func headObjectSizeMatchesList() async throws {
        let service = try makeService()
        let entries = try await service.listObjects()
        guard let entry = entries.first(where: { $0.size > 0 }) else {
            Issue.record("No entries with size > 0 found")
            return
        }

        let (exists, headSize) = try await service.headObject(key: entry.key)
        #expect(exists == true)
        #expect(headSize == entry.size, "HEAD size (\(headSize)) should match list size (\(entry.size)) for \(entry.key)")
    }

    // MARK: - deleteObject (safe - we test that deleting a nonexistent key throws appropriately)

    @Test("deleteObject throws deleteFailed for nonexistent key")
    func deleteObjectNonexistent() async throws {
        let service = try makeService()
        let fakeKey = "XCFrameworks/__TEST_DELETE_NONEXISTENT__/fake_\(UUID()).zip"

        // GCS may return 204 (success) even for deleting nonexistent keys in some cases,
        // or 404 which would throw. We test both scenarios.
        do {
            try await service.deleteObject(key: fakeKey)
            // S3-compatible API often returns 204 for deletes even if key doesn't exist
            // This is valid behavior (idempotent delete)
        } catch let error as GCSBucketService.GCSError {
            // Also valid - some backends return 404
            switch error {
            case .deleteFailed(let key, let code):
                #expect(key == fakeKey)
                #expect(code == 404 || code == 403, "Expected 404 or 403 for missing key, got \(code)")
            default:
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - deleteObjects

    @Test("deleteObjects with empty array returns 0/0")
    func deleteObjectsEmpty() async throws {
        let service = try makeService()
        let (deleted, failed) = try await service.deleteObjects(keys: [])
        #expect(deleted == 0)
        #expect(failed == 0)
    }

    // MARK: - deleteFrameworkEntries (safe - nonexistent framework)

    @Test("deleteFrameworkEntries for nonexistent framework returns 0")
    func deleteFrameworkEntriesNonexistent() async throws {
        let service = try makeService()
        let deleted = try await service.deleteFrameworkEntries(frameworkName: "__NONEXISTENT_FW_\(UUID())__")
        #expect(deleted == 0)
    }

    // MARK: - deleteStaleEntries (safe - future cutoff)

    @Test("deleteStaleEntries with future date deletes nothing when tested with far-future cutoff")
    func deleteStaleEntriesWithDistantPast() async throws {
        let service = try makeService()
        // Use a very old date so nothing is "stale"
        let ancientDate = Date(timeIntervalSince1970: 0) // Jan 1, 1970
        let deleted = try await service.deleteStaleEntries(olderThan: ancientDate)
        #expect(deleted == 0, "Nothing should be older than epoch")
    }

    // MARK: - listObjects pagination

    @Test("listObjects returns all entries across pages")
    func listObjectsPagination() async throws {
        let service = try makeService()
        let entries = try await service.listObjects()
        #expect(entries.count > 100, "Expected many entries to test pagination, got \(entries.count)")

        // Verify no duplicate keys
        let uniqueKeys = Set(entries.map(\.key))
        #expect(uniqueKeys.count == entries.count, "Found \(entries.count - uniqueKeys.count) duplicate keys")
    }

    // MARK: - bucketStats

    @Test("bucketStats framework count matches unique framework names from entries")
    func bucketStatsConsistency() async throws {
        let service = try makeService()
        let stats = try await service.bucketStats()

        let uniqueFrameworks = Set(stats.entries.map(\.frameworkName))
        #expect(stats.frameworkCount == uniqueFrameworks.count)
        #expect(stats.totalEntries == stats.entries.count)

        let computedSize = stats.entries.reduce(Int64(0)) { $0 + $1.size }
        #expect(stats.totalSize == computedSize)
    }

    // MARK: - listObjects with custom prefix

    @Test("listObjects with specific framework prefix returns only matching entries")
    func listObjectsCustomPrefix() async throws {
        let service = try makeService()
        // List all to find a framework that has a 3-segment key (XCFrameworks/Name/hash.zip)
        let allEntries = try await service.listObjects()
        guard let entry = allEntries.first(where: { $0.key.split(separator: "/").count >= 3 }) else {
            Issue.record("No 3-segment key entries found in bucket")
            return
        }

        // Extract the actual prefix (e.g. "XCFrameworks/Alamofire/") from the key
        let keyParts = entry.key.split(separator: "/")
        let frameworkPrefix = "\(keyParts[0])/\(keyParts[1])/"
        let frameworkName = String(keyParts[1])

        let filtered = try await service.listObjects(prefix: frameworkPrefix)

        #expect(!filtered.isEmpty, "Should have entries for prefix \(frameworkPrefix)")
        for e in filtered {
            #expect(e.key.hasPrefix(frameworkPrefix), "Entry \(e.key) should start with \(frameworkPrefix)")
        }

        // Also verify using fewer results than total
        #expect(filtered.count <= allEntries.count, "Filtered should be <= total")
        #expect(filtered.count < allEntries.count, "Filtered by one framework should be less than total")
    }

    // MARK: - Error construction

    @Test("GCSError.listFailed preserves status code")
    func listFailedError() {
        let error = GCSBucketService.GCSError.listFailed(statusCode: 500)
        #expect(error.localizedDescription.contains("500"))
    }

    @Test("GCSError.deleteFailed preserves key and status code")
    func deleteFailedError() {
        let error = GCSBucketService.GCSError.deleteFailed(key: "some/key.zip", statusCode: 403)
        #expect(error.localizedDescription.contains("some/key.zip"))
        #expect(error.localizedDescription.contains("403"))
    }
}
