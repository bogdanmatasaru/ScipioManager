import Testing
import Foundation
@testable import ScipioManager

@Suite("FrameworkInfo Tests")
struct FrameworkInfoTests {

    // MARK: - FrameworkInfo

    @Test("Default initializer sets correct values")
    func defaultInit() {
        let fw = FrameworkInfo(name: "TestFW")
        #expect(fw.id == "TestFW")
        #expect(fw.name == "TestFW")
        #expect(fw.productName == "TestFW")
        #expect(fw.version == nil)
        #expect(fw.source == .official)
        #expect(fw.url == nil)
        #expect(fw.slices.isEmpty)
        #expect(fw.sizeBytes == 0)
        #expect(fw.cacheStatus == .unknown)
    }

    @Test("Custom product name used when provided")
    func customProductName() {
        let fw = FrameworkInfo(name: "rxswift", productName: "RxSwift")
        #expect(fw.productName == "RxSwift")
        #expect(fw.displayName == "RxSwift")
    }

    @Test("Display name falls back to product name from initializer")
    func displayNameFallback() {
        let fw = FrameworkInfo(name: "Alamofire", productName: "")
        // When productName is empty, init sets it to name
        #expect(fw.displayName == "Alamofire")
    }

    @Test("Size formatted returns human-readable string")
    func sizeFormatted() {
        let fw = FrameworkInfo(name: "FW", sizeBytes: 2_500_000)
        #expect(!fw.sizeFormatted.isEmpty)
    }

    @Test("Full initializer sets all properties")
    func fullInit() {
        let slices = [ArchSlice.arm64Device, ArchSlice.simulatorUniversal]
        let fw = FrameworkInfo(
            name: "RxSwift",
            productName: "RxSwift",
            version: "6.10.1",
            source: .fork,
            url: "https://github.com/ReactiveX/RxSwift.git",
            slices: slices,
            sizeBytes: 1_000_000,
            cacheStatus: .allLayers
        )
        #expect(fw.version == "6.10.1")
        #expect(fw.source == .fork)
        #expect(fw.url == "https://github.com/ReactiveX/RxSwift.git")
        #expect(fw.slices.count == 2)
        #expect(fw.sizeBytes == 1_000_000)
        #expect(fw.cacheStatus == .allLayers)
    }

    @Test("Hashable conformance works correctly")
    func hashable() {
        let fw1 = FrameworkInfo(name: "A")
        let fw2 = FrameworkInfo(name: "B")
        let fw3 = FrameworkInfo(name: "A")
        let set: Set<FrameworkInfo> = [fw1, fw2, fw3]
        #expect(set.count == 2)
    }

    @Test("Mutable cache status")
    func mutableCacheStatus() {
        var fw = FrameworkInfo(name: "Test")
        #expect(fw.cacheStatus == .unknown)
        fw.cacheStatus = .allLayers
        #expect(fw.cacheStatus == .allLayers)
        fw.cacheStatus = .localOnly
        #expect(fw.cacheStatus == .localOnly)
    }

    // MARK: - DependencySource

    @Test("All dependency source raw values")
    func dependencySourceRawValues() {
        #expect(DependencySource.official.rawValue == "Official")
        #expect(DependencySource.fork.rawValue == "Fork")
        #expect(DependencySource.unknown.rawValue == "Unknown")
    }

    @Test("DependencySource allCases")
    func dependencySourceAllCases() {
        #expect(DependencySource.allCases.count == 3)
    }

    // MARK: - CacheStatus

    @Test("All cache status raw values")
    func cacheStatusRawValues() {
        #expect(CacheStatus.allLayers.rawValue == "Cached (All Layers)")
        #expect(CacheStatus.localOnly.rawValue == "Local Only")
        #expect(CacheStatus.remoteOnly.rawValue == "Remote Only")
        #expect(CacheStatus.missing.rawValue == "Not Cached")
        #expect(CacheStatus.unknown.rawValue == "Unknown")
    }

    @Test("Cache status colors")
    func cacheStatusColors() {
        #expect(CacheStatus.allLayers.color == "green")
        #expect(CacheStatus.localOnly.color == "yellow")
        #expect(CacheStatus.remoteOnly.color == "yellow")
        #expect(CacheStatus.missing.color == "red")
        #expect(CacheStatus.unknown.color == "gray")
    }

    @Test("CacheStatus allCases")
    func cacheStatusAllCases() {
        #expect(CacheStatus.allCases.count == 5)
    }

    // MARK: - ArchSlice

    @Test("Predefined arch slices")
    func predefinedSlices() {
        #expect(ArchSlice.arm64Device.identifier == "ios-arm64")
        #expect(ArchSlice.arm64Device.platform == "Device (arm64)")
        #expect(ArchSlice.simulatorUniversal.identifier == "ios-arm64_x86_64-simulator")
        #expect(ArchSlice.simulatorUniversal.platform == "Simulator (arm64 + x86_64)")
    }

    @Test("Custom arch slice")
    func customSlice() {
        let slice = ArchSlice(identifier: "macos-arm64", platform: "macOS")
        #expect(slice.identifier == "macos-arm64")
        #expect(slice.platform == "macOS")
    }

    @Test("ArchSlice hashable conformance")
    func sliceHashable() {
        let s1 = ArchSlice.arm64Device
        let s2 = ArchSlice.simulatorUniversal
        let s3 = ArchSlice.arm64Device
        let set: Set<ArchSlice> = [s1, s2, s3]
        #expect(set.count == 2)
    }
}
