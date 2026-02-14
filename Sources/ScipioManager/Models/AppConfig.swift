import Foundation

/// External configuration loaded from `scipio-manager.json` next to the app bundle.
///
/// **Only `bucket.name` is required.** Everything else is auto-detected or has sensible defaults:
/// - `scipio_path`: Auto-detected from the app bundle location
/// - `bucket.endpoint`, `bucket.storage_prefix`, `bucket.region`: GCS defaults
/// - `hmac_key_filename`: Defaults to `"gcs-hmac.json"`
/// - `derived_data_prefix`: Auto-detected from `.xcworkspace` / `.xcodeproj` name
/// - `fork_organizations`: Defaults to empty
///
/// If no config file is found, the app uses defaults and prompts for setup in Settings.
struct AppConfig: Codable, Sendable {

    // MARK: - Project

    /// Absolute path to the Scipio directory (e.g., `/Users/me/Projects/MyApp/Scipio`).
    /// If `nil`, the app will attempt auto-detection.
    var scipioPath: String?

    // MARK: - Bucket

    /// GCS/S3 bucket configuration.
    var bucket: BucketSettings

    // MARK: - Credentials

    /// Name of the HMAC credentials JSON file inside the Scipio directory.
    /// Default: `"gcs-hmac.json"`.
    var hmacKeyFilename: String

    // MARK: - Cleanup

    /// DerivedData directory prefix override (e.g., `"MyApp-"`).
    /// **Auto-detected** from the `.xcworkspace` or `.xcodeproj` name next to the Scipio directory.
    /// Only set this if auto-detection picks the wrong name.
    var derivedDataPrefix: String?

    // MARK: - Dependencies

    /// GitHub organizations or usernames considered "custom forks" (shown with a Fork badge).
    /// Example: `["my-org", "my-username"]`.
    var forkOrganizations: [String]

    // MARK: - Nested Types

    struct BucketSettings: Codable, Sendable {
        var name: String
        var endpoint: String
        var storagePrefix: String
        var region: String

        static let `default` = BucketSettings(
            name: "",
            endpoint: "https://storage.googleapis.com",
            storagePrefix: "XCFrameworks/",
            region: "auto"
        )

        init(name: String = "", endpoint: String = "https://storage.googleapis.com",
             storagePrefix: String = "XCFrameworks/", region: String = "auto") {
            self.name = name
            self.endpoint = endpoint
            self.storagePrefix = storagePrefix
            self.region = region
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? "https://storage.googleapis.com"
            storagePrefix = try container.decodeIfPresent(String.self, forKey: .storagePrefix) ?? "XCFrameworks/"
            region = try container.decodeIfPresent(String.self, forKey: .region) ?? "auto"
        }
    }

    // MARK: - Defaults

    static let `default` = AppConfig(
        scipioPath: nil,
        bucket: .default,
        hmacKeyFilename: "gcs-hmac.json",
        derivedDataPrefix: nil,
        forkOrganizations: []
    )

    init(scipioPath: String? = nil, bucket: BucketSettings = .default,
         hmacKeyFilename: String = "gcs-hmac.json", derivedDataPrefix: String? = nil,
         forkOrganizations: [String] = []) {
        self.scipioPath = scipioPath
        self.bucket = bucket
        self.hmacKeyFilename = hmacKeyFilename
        self.derivedDataPrefix = derivedDataPrefix
        self.forkOrganizations = forkOrganizations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scipioPath = try container.decodeIfPresent(String.self, forKey: .scipioPath)
        bucket = try container.decodeIfPresent(BucketSettings.self, forKey: .bucket) ?? .default
        hmacKeyFilename = try container.decodeIfPresent(String.self, forKey: .hmacKeyFilename) ?? "gcs-hmac.json"
        derivedDataPrefix = try container.decodeIfPresent(String.self, forKey: .derivedDataPrefix)
        forkOrganizations = try container.decodeIfPresent([String].self, forKey: .forkOrganizations) ?? []
    }

    // MARK: - Loading

    /// Load configuration from the standard location next to the app bundle.
    ///
    /// Search order:
    /// 1. `scipio-manager.json` next to the `.app` bundle
    /// 2. `scipio-manager.json` in the current working directory
    /// 3. `~/.config/scipio-manager/config.json`
    /// 4. Falls back to defaults
    static func load() -> AppConfig {
        let candidates: [URL] = [
            // Next to the .app bundle
            appBundleDirectory?.appendingPathComponent("scipio-manager.json"),
            // Current working directory
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scipio-manager.json"),
            // XDG config
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".config/scipio-manager/config.json"),
        ].compactMap { $0 }

        for candidate in candidates {
            if let config = try? load(from: candidate) {
                return config
            }
        }

        return .default
    }

    /// Load from a specific file URL.
    static func load(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AppConfig.self, from: data)
    }

    /// Save to a specific file URL.
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Generate a minimal sample config file content for documentation.
    ///
    /// Only the bucket name is required — everything else is auto-detected or has sensible defaults.
    static var sampleJSON: String {
        """
        {
          "bucket": {
            "name": "your-bucket-name"
          }
        }
        """
    }

    /// Generate a fully-expanded sample config file content showing all available options.
    static var fullSampleJSON: String {
        let sample = AppConfig(
            scipioPath: "/path/to/your/project/Scipio",
            bucket: BucketSettings(
                name: "your-bucket-name",
                endpoint: "https://storage.googleapis.com",
                storagePrefix: "XCFrameworks/",
                region: "auto"
            ),
            hmacKeyFilename: "gcs-hmac.json",
            derivedDataPrefix: "MyApp-",
            forkOrganizations: ["your-org", "your-username"]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: encoder.encode(sample), encoding: .utf8)) ?? "{}"
    }

    // MARK: - Private

    private static var appBundleDirectory: URL? {
        Bundle.main.bundleURL.deletingLastPathComponent()
    }
}
