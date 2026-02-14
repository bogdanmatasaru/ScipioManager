import Foundation

/// A single object in the GCS bucket (S3 ListObjectsV2 result).
struct CacheEntry: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let size: Int64
    let lastModified: Date
    let etag: String

    /// Extract the framework name from a cache key like "cache/v1/FrameworkName/hash.zip"
    var frameworkName: String {
        let parts = key.split(separator: "/")
        guard parts.count >= 3 else { return key }
        return String(parts[2])
    }

    /// The hash portion of the key
    var cacheHash: String {
        let parts = key.split(separator: "/")
        guard let last = parts.last else { return "" }
        return String(last).replacingOccurrences(of: ".zip", with: "")
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var lastModifiedFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }
}

/// Aggregated info for all cache entries of a single framework.
struct CacheFrameworkGroup: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let entries: [CacheEntry]

    var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }
    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    var entryCount: Int { entries.count }
    var latestModified: Date? { entries.map(\.lastModified).max() }
}
