import Foundation

/// A single object in the GCS bucket (S3 ListObjectsV2 result).
struct CacheEntry: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let size: Int64
    let lastModified: Date
    let etag: String

    /// Extract the framework name from a cache key.
    /// Handles both formats:
    ///   - "XCFrameworks/Alamofire/hash.zip"  -> "Alamofire"
    ///   - "XCFrameworks/.Alamofire.version"   -> "Alamofire"
    var frameworkName: String {
        let parts = key.split(separator: "/")
        guard parts.count >= 2 else { return key }

        // For 3+ segments like "prefix/Framework/file.zip", the framework is the second-to-last directory
        if parts.count >= 3 {
            return String(parts[parts.count - 2])
        }

        // For 2 segments like "XCFrameworks/.Alamofire.version", extract name from the filename
        let filename = String(parts.last!)
        if filename.hasPrefix(".") && filename.hasSuffix(".version") {
            return String(filename.dropFirst().dropLast(8))
        }
        return filename
    }

    /// The hash/file portion of the key (last path component without .zip)
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
