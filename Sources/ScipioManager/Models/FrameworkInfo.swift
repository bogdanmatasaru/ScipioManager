import Foundation

/// Represents a single XCFramework managed by Scipio.
struct FrameworkInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let productName: String
    let version: String?
    let source: DependencySource
    let url: String?
    let slices: [ArchSlice]
    let sizeBytes: Int64
    var cacheStatus: CacheStatus

    var displayName: String { productName.isEmpty ? name : productName }
    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }

    init(
        name: String,
        productName: String = "",
        version: String? = nil,
        source: DependencySource = .official,
        url: String? = nil,
        slices: [ArchSlice] = [],
        sizeBytes: Int64 = 0,
        cacheStatus: CacheStatus = .unknown
    ) {
        self.id = name
        self.name = name
        self.productName = productName.isEmpty ? name : productName
        self.version = version
        self.source = source
        self.url = url
        self.slices = slices
        self.sizeBytes = sizeBytes
        self.cacheStatus = cacheStatus
    }
}

enum DependencySource: String, Sendable, Hashable, CaseIterable {
    case official = "Official"
    case fork = "Fork"
    case unknown = "Unknown"
}

enum CacheStatus: String, Sendable, Hashable, CaseIterable {
    case allLayers = "Cached (All Layers)"
    case localOnly = "Local Only"
    case remoteOnly = "Remote Only"
    case missing = "Not Cached"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .allLayers: return "green"
        case .localOnly, .remoteOnly: return "yellow"
        case .missing: return "red"
        case .unknown: return "gray"
        }
    }
}

struct ArchSlice: Hashable, Sendable {
    let identifier: String
    let platform: String

    static let arm64Device = ArchSlice(identifier: "ios-arm64", platform: "Device (arm64)")
    static let simulatorUniversal = ArchSlice(
        identifier: "ios-arm64_x86_64-simulator",
        platform: "Simulator (arm64 + x86_64)"
    )
}
