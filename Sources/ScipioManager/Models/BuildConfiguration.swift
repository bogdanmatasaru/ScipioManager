import Foundation

/// Mirrors the ScipioKit build options for display purposes.
struct BuildConfiguration: Sendable {
    let buildConfig: String          // "release" or "debug"
    let frameworkType: String        // "static" or "dynamic"
    let simulatorSupported: Bool
    let debugSymbolsEmbedded: Bool
    let libraryEvolution: Bool
    let stripDWARF: Bool
    let swiftVersion: String

    static let current = BuildConfiguration(
        buildConfig: "release",
        frameworkType: "static",
        simulatorSupported: true,
        debugSymbolsEmbedded: false,
        libraryEvolution: false,
        stripDWARF: true,
        swiftVersion: "6.2"
    )
}

/// Parsed dependency from Build/Package.swift.
struct ParsedDependency: Identifiable, Hashable, Sendable {
    var id: String { url }
    let url: String
    let version: String
    let versionType: VersionType
    let packageName: String
    let products: [String]
    let isCustomFork: Bool

    enum VersionType: String, Sendable, Hashable {
        case exact
        case revision
        case from
        case branch
    }

    var displayVersion: String {
        switch versionType {
        case .exact: return version
        case .revision: return String(version.prefix(12))
        case .from: return ">= \(version)"
        case .branch: return "branch: \(version)"
        }
    }
}

/// GCS bucket configuration.
struct BucketConfig: Sendable, Codable {
    var bucketName: String
    var endpoint: String
    var storagePrefix: String
    var region: String

    static let `default` = BucketConfig(
        bucketName: "emag-ios-scipio-cache",
        endpoint: "https://storage.googleapis.com",
        storagePrefix: "cache/v1",
        region: "auto"
    )
}
