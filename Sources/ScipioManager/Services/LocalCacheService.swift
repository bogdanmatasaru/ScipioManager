import Foundation

/// Service for managing local caches (DerivedData, SPM, Scipio local disk cache).
struct LocalCacheService: Sendable {

    // MARK: - Cache Locations

    struct CacheLocation: Identifiable, Sendable {
        let id: String
        let name: String
        let path: URL
        let description: String
        var exists: Bool
        var size: Int64
        var sizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    /// Discover all cache locations and their sizes.
    static func discoverCaches(scipioDir: URL) -> [CacheLocation] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())

        let locations: [(String, String, URL, String)] = [
            (
                "derived-data",
                "Xcode DerivedData",
                home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                "Xcode build products, indexes, and logs. Safe to delete but requires full rebuild."
            ),
            (
                "spm-cache",
                "SPM Cache",
                home.appendingPathComponent("Library/Caches/org.swift.swiftpm"),
                "Swift Package Manager global cache. Safe to delete but packages will re-download."
            ),
            (
                "spm-artifacts",
                "SPM Artifacts",
                home.appendingPathComponent("Library/Caches/org.swift.swiftpm/artifacts"),
                "Downloaded binary artifacts (xcframeworks zips). Can cause stale issues."
            ),
            (
                "scipio-local",
                "Scipio Local Cache",
                home.appendingPathComponent("Library/Caches/Scipio"),
                "Scipio's local disk cache (Layer 2). Fast restore without GCS network calls."
            ),
            (
                "project-xcframeworks",
                "Project XCFrameworks",
                scipioDir.appendingPathComponent("Frameworks/XCFrameworks"),
                "Scipio-built xcframeworks in the project (Layer 1). The actual output."
            ),
            (
                "runner-build",
                "ScipioRunner Build",
                scipioDir.appendingPathComponent("Runner/.build"),
                "ScipioRunner compiled binary and build artifacts."
            ),
            (
                "source-packages",
                "SourcePackages",
                scipioDir.deletingLastPathComponent().appendingPathComponent("SourcePackages"),
                "Xcode's local SPM package checkouts."
            ),
        ]

        return locations.map { id, name, path, desc in
            let exists = fm.fileExists(atPath: path.path)
            let size = exists ? directorySize(path) : 0
            return CacheLocation(id: id, name: name, path: path, description: desc, exists: exists, size: size)
        }
    }

    /// Find all eMAG DerivedData directories.
    static func findDerivedDataDirs() -> [URL] {
        let derivedData = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return contents.filter { $0.lastPathComponent.hasPrefix("eMag-") }
    }

    // MARK: - Cleanup Operations

    /// Delete a specific cache location.
    static func cleanCache(at path: URL) throws -> Int64 {
        let size = directorySize(path)
        let fm = FileManager.default

        if fm.fileExists(atPath: path.path) {
            // For directories that should persist (like XCFrameworks), clear contents
            if let contents = try? fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) {
                for item in contents {
                    try fm.removeItem(at: item)
                }
            }
        }
        return size
    }

    /// Delete DerivedData for eMAG.
    static func cleanDerivedData() throws -> Int64 {
        let dirs = findDerivedDataDirs()
        var totalSize: Int64 = 0
        for dir in dirs {
            totalSize += directorySize(dir)
            try FileManager.default.removeItem(at: dir)
        }
        return totalSize
    }

    /// Nuclear clean: wipe everything.
    static func nuclearClean(scipioDir: URL) throws -> NuclearCleanResult {
        var result = NuclearCleanResult()

        // 1. DerivedData
        if let size = try? cleanDerivedData() {
            result.derivedDataSize = size
        }

        // 2. SPM artifacts
        let spmArtifacts = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/org.swift.swiftpm/artifacts")
        if let size = try? cleanCache(at: spmArtifacts) {
            result.spmArtifactsSize = size
        }

        // 3. Project XCFrameworks
        let xcframeworks = scipioDir.appendingPathComponent("Frameworks/XCFrameworks")
        if let size = try? cleanCache(at: xcframeworks) {
            result.xcframeworksSize = size
        }

        // 4. SourcePackages
        let sourcePackages = scipioDir.deletingLastPathComponent()
            .appendingPathComponent("SourcePackages")
        if FileManager.default.fileExists(atPath: sourcePackages.path) {
            result.sourcePackagesSize = directorySize(sourcePackages)
            try? FileManager.default.removeItem(at: sourcePackages)
        }

        return result
    }

    struct NuclearCleanResult: Sendable {
        var derivedDataSize: Int64 = 0
        var spmArtifactsSize: Int64 = 0
        var xcframeworksSize: Int64 = 0
        var sourcePackagesSize: Int64 = 0

        var totalSize: Int64 {
            derivedDataSize + spmArtifactsSize + xcframeworksSize + sourcePackagesSize
        }

        var totalSizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        }
    }

    // MARK: - Utilities

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Check if a directory exists and is non-empty.
    static func directoryExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
