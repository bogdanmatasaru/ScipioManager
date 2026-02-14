import Testing
import Foundation
@testable import ScipioManager

/// Live integration tests for GCSBucketService network calls.
/// Enable by setting SCIPIO_INTEGRATION_TEST_DIR to a Scipio directory with gcs-hmac.json.
@Suite("GCS Bucket Live Tests", .enabled(if: {
    if let dir = ProcessInfo.processInfo.environment["SCIPIO_INTEGRATION_TEST_DIR"] {
        return FileManager.default.fileExists(atPath: dir + "/gcs-hmac.json")
    }
    return false
}()))
struct GCSBucketLiveTests {

    var hmacKeyURL: URL {
        let dir = ProcessInfo.processInfo.environment["SCIPIO_INTEGRATION_TEST_DIR"] ?? "/tmp"
        return URL(fileURLWithPath: dir).appendingPathComponent("gcs-hmac.json")
    }

    private func makeService() throws -> GCSBucketService {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        let config = BucketConfig(
            bucketName: ProcessInfo.processInfo.environment["SCIPIO_BUCKET_NAME"] ?? "",
            endpoint: "https://storage.googleapis.com",
            storagePrefix: "XCFrameworks/",
            region: "auto"
        )
        return GCSBucketService(hmacKey: key, config: config)
    }

    // MARK: - headObject

    @Test("headObject returns true for a known existing object")
    func headObjectExists() async throws {
        let service = try makeService()
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

    // MARK: - deleteObject (safe - nonexistent key)

    @Test("deleteObject handles nonexistent key")
    func deleteObjectNonexistent() async throws {
        let service = try makeService()
        let fakeKey = "XCFrameworks/__TEST_DELETE_NONEXISTENT__/fake_\(UUID()).zip"

        do {
            try await service.deleteObject(key: fakeKey)
            // S3-compatible API often returns 204 for deletes even if key doesn't exist
        } catch let error as GCSBucketService.GCSError {
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

    // MARK: - deleteFrameworkEntries (safe)

    @Test("deleteFrameworkEntries for nonexistent framework returns 0")
    func deleteFrameworkEntriesNonexistent() async throws {
        let service = try makeService()
        let deleted = try await service.deleteFrameworkEntries(frameworkName: "__NONEXISTENT_FW_\(UUID())__")
        #expect(deleted == 0)
    }

    // MARK: - deleteStaleEntries (safe)

    @Test("deleteStaleEntries with ancient date deletes nothing")
    func deleteStaleEntriesWithDistantPast() async throws {
        let service = try makeService()
        let ancientDate = Date(timeIntervalSince1970: 0)
        let deleted = try await service.deleteStaleEntries(olderThan: ancientDate)
        #expect(deleted == 0, "Nothing should be older than epoch")
    }

    // MARK: - listObjects pagination

    @Test("listObjects returns entries")
    func listObjectsPagination() async throws {
        let service = try makeService()
        let entries = try await service.listObjects()
        #expect(entries.count > 0, "Expected entries in bucket")

        let uniqueKeys = Set(entries.map(\.key))
        #expect(uniqueKeys.count == entries.count, "Found \(entries.count - uniqueKeys.count) duplicate keys")
    }

    // MARK: - bucketStats

    @Test("bucketStats framework count is consistent")
    func bucketStatsConsistency() async throws {
        let service = try makeService()
        let stats = try await service.bucketStats()

        let uniqueFrameworks = Set(stats.entries.map(\.frameworkName))
        #expect(stats.frameworkCount == uniqueFrameworks.count)
        #expect(stats.totalEntries == stats.entries.count)

        let computedSize = stats.entries.reduce(Int64(0)) { $0 + $1.size }
        #expect(stats.totalSize == computedSize)
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
