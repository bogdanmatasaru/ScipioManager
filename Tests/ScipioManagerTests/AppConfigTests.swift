import Testing
import Foundation
@testable import ScipioManager

@Suite("AppConfig Tests")
struct AppConfigTests {

    // MARK: - Defaults

    @Test("Default config has sensible values")
    func defaultConfig() {
        let config = AppConfig.default
        #expect(config.scipioPath == nil)
        #expect(config.bucket.name == "")
        #expect(config.bucket.endpoint == "https://storage.googleapis.com")
        #expect(config.bucket.storagePrefix == "XCFrameworks/")
        #expect(config.bucket.region == "auto")
        #expect(config.hmacKeyFilename == "gcs-hmac.json")
        #expect(config.derivedDataPrefix == nil)
        #expect(config.forkOrganizations.isEmpty)
    }

    // MARK: - JSON Encoding/Decoding

    @Test("Config round-trips through JSON")
    func jsonRoundTrip() throws {
        let original = AppConfig(
            scipioPath: "/path/to/scipio",
            bucket: .init(
                name: "my-bucket",
                endpoint: "https://storage.googleapis.com",
                storagePrefix: "cache/v1/",
                region: "us-east1"
            ),
            hmacKeyFilename: "hmac.json",
            derivedDataPrefix: "MyApp-",
            forkOrganizations: ["my-org", "team-fork"]
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(AppConfig.self, from: data)

        #expect(decoded.scipioPath == "/path/to/scipio")
        #expect(decoded.bucket.name == "my-bucket")
        #expect(decoded.bucket.endpoint == "https://storage.googleapis.com")
        #expect(decoded.bucket.storagePrefix == "cache/v1/")
        #expect(decoded.bucket.region == "us-east1")
        #expect(decoded.hmacKeyFilename == "hmac.json")
        #expect(decoded.derivedDataPrefix == "MyApp-")
        #expect(decoded.forkOrganizations == ["my-org", "team-fork"])
    }

    @Test("Config loads from JSON file")
    func loadFromFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("config-test-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {
            "scipio_path": "/test/path",
            "bucket": {
                "name": "test-bucket",
                "endpoint": "https://storage.googleapis.com",
                "storage_prefix": "XCFrameworks/",
                "region": "auto"
            },
            "hmac_key_filename": "gcs-hmac.json",
            "fork_organizations": ["org1"]
        }
        """
        let fileURL = tempDir.appendingPathComponent("scipio-manager.json")
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let config = try AppConfig.load(from: fileURL)
        #expect(config.scipioPath == "/test/path")
        #expect(config.bucket.name == "test-bucket")
        #expect(config.forkOrganizations == ["org1"])
    }

    @Test("Config save and reload")
    func saveAndReload() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("config-save-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var config = AppConfig.default
        config.scipioPath = "/my/scipio"
        config.bucket.name = "saved-bucket"
        config.derivedDataPrefix = "App-"

        let fileURL = tempDir.appendingPathComponent("config.json")
        try config.save(to: fileURL)

        let reloaded = try AppConfig.load(from: fileURL)
        #expect(reloaded.scipioPath == "/my/scipio")
        #expect(reloaded.bucket.name == "saved-bucket")
        #expect(reloaded.derivedDataPrefix == "App-")
    }

    @Test("Load returns defaults for missing file")
    func loadMissingFile() {
        let config = AppConfig.load()
        // Should return defaults without crashing
        #expect(config.bucket.endpoint == "https://storage.googleapis.com")
    }

    @Test("Load throws for invalid JSON file")
    func loadInvalidJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("config-bad-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("bad.json")
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            _ = try AppConfig.load(from: fileURL)
        }
    }

    // MARK: - Sample JSON

    @Test("Sample JSON is valid JSON")
    func sampleJSON() throws {
        let sample = AppConfig.sampleJSON
        #expect(!sample.isEmpty)

        let data = sample.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["scipio_path"] != nil)
    }

    // MARK: - BucketSettings defaults

    @Test("BucketSettings default values")
    func bucketSettingsDefaults() {
        let settings = AppConfig.BucketSettings.default
        #expect(settings.name == "")
        #expect(settings.endpoint == "https://storage.googleapis.com")
        #expect(settings.storagePrefix == "XCFrameworks/")
        #expect(settings.region == "auto")
    }

    // MARK: - Minimal JSON (partial config with defaults)

    @Test("Minimal JSON with only bucket name fills defaults")
    func minimalJSON() throws {
        let json = """
        {
            "bucket": { "name": "my-bucket" }
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(AppConfig.self, from: data)

        #expect(config.scipioPath == nil)
        #expect(config.bucket.name == "my-bucket")
        #expect(config.bucket.endpoint == "https://storage.googleapis.com")
        #expect(config.bucket.storagePrefix == "XCFrameworks/")
        #expect(config.bucket.region == "auto")
        #expect(config.hmacKeyFilename == "gcs-hmac.json")
        #expect(config.derivedDataPrefix == nil)
        #expect(config.forkOrganizations.isEmpty)
    }

    @Test("Empty JSON fills all defaults")
    func emptyJSON() throws {
        let data = "{}".data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(AppConfig.self, from: data)

        #expect(config.bucket.name == "")
        #expect(config.bucket.endpoint == "https://storage.googleapis.com")
        #expect(config.hmacKeyFilename == "gcs-hmac.json")
        #expect(config.forkOrganizations.isEmpty)
    }
}
