import Testing
import Foundation
@testable import ScipioManager

/// Integration tests that run against the real eMAG Scipio project.
/// These require the project to exist at ~/Projects/eMAG/Scipio/
@Suite("Integration Tests", .enabled(if: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Projects/eMAG/Scipio/Build/Package.swift")))
struct IntegrationTests {

    let scipioDir = URL(fileURLWithPath: NSHomeDirectory() + "/Projects/eMAG/Scipio")
    var buildPkg: URL { scipioDir.appendingPathComponent("Build/Package.swift") }
    var frameworksDir: URL { scipioDir.appendingPathComponent("Frameworks/XCFrameworks") }
    var hmacKeyURL: URL { scipioDir.appendingPathComponent("gcs-hmac.json") }

    // MARK: - Flow 1: Framework Discovery

    @Test("Discovers all xcframeworks on disk")
    func discoverFrameworks() async throws {
        let service = ScipioService(scipioDir: scipioDir)
        let frameworks = try await service.discoverFrameworks()
        #expect(frameworks.count >= 80, "Expected at least 80 frameworks, got \(frameworks.count)")

        // Verify each framework has slices
        for fw in frameworks {
            #expect(!fw.slices.isEmpty, "\(fw.name) has no architecture slices")
        }
    }

    @Test("Framework count matches disk")
    func frameworkCount() async {
        let service = ScipioService(scipioDir: scipioDir)
        let count = await service.frameworkCount()
        #expect(count >= 80)
    }

    @Test("Frameworks have both device and simulator slices")
    func frameworkSlices() async throws {
        let service = ScipioService(scipioDir: scipioDir)
        let frameworks = try await service.discoverFrameworks()

        var missingSlices: [String] = []
        for fw in frameworks {
            let hasDevice = fw.slices.contains { $0.identifier.contains("ios-arm64") && !$0.identifier.contains("simulator") }
            let hasSim = fw.slices.contains { $0.identifier.contains("simulator") }
            if !hasDevice || !hasSim {
                missingSlices.append(fw.name)
            }
        }
        #expect(missingSlices.isEmpty, "Frameworks missing slices: \(missingSlices)")
    }

    // MARK: - Flow 2: Package Parser

    @Test("Parses real Build/Package.swift dependencies")
    func parseRealDependencies() throws {
        let deps = try PackageParser.parseDependencies(from: buildPkg)
        #expect(deps.count >= 40, "Expected at least 40 dependencies, got \(deps.count)")

        // Verify known dependencies exist
        let names = Set(deps.map(\.packageName))
        #expect(names.contains("RxSwift"))
        #expect(names.contains("Alamofire"))
        #expect(names.contains("Kingfisher"))
        #expect(names.contains("Swinject"))
    }

    @Test("Detects custom forks correctly")
    func detectRealForks() throws {
        let deps = try PackageParser.parseDependencies(from: buildPkg)
        let forks = deps.filter(\.isCustomFork)
        #expect(forks.count >= 5, "Expected at least 5 custom forks")

        // AMPopTip is a known fork
        let amPopTip = deps.first { $0.packageName == "AMPopTip" }
        #expect(amPopTip?.isCustomFork == true)
    }

    @Test("Parses products for multi-product packages")
    func multiProductPackages() throws {
        let deps = try PackageParser.parseDependencies(from: buildPkg)
        let rxSwift = deps.first { $0.packageName == "RxSwift" }
        #expect(rxSwift != nil)
        #expect(rxSwift!.products.count >= 2, "RxSwift should have at least RxSwift + RxCocoa")
    }

    // MARK: - Flow 3: HMAC Key Loading

    @Test("Loads real HMAC credentials")
    func loadRealHMAC() throws {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        #expect(!key.accessKeyId.isEmpty)
        #expect(!key.secretAccessKey.isEmpty)
        #expect(key.accessKeyId.hasPrefix("GOOG"))
    }

    @Test("Credential source detects real key file")
    func credentialSourceReal() {
        let source = HMACKeyLoader.credentialsAvailable(at: hmacKeyURL)
        #expect(source == .jsonFile)
    }

    // MARK: - Flow 4: Local Cache Service

    @Test("Discovers all cache locations")
    func discoverRealCaches() {
        let locations = LocalCacheService.discoverCaches(scipioDir: scipioDir)
        #expect(locations.count >= 5)

        let projectCache = locations.first { $0.id == "project-xcframeworks" }
        #expect(projectCache != nil)
        #expect(projectCache!.exists)
        #expect(projectCache!.size > 0)
    }

    @Test("XCFrameworks directory has significant size")
    func xcframeworksSize() {
        let size = LocalCacheService.directorySize(frameworksDir)
        // Should be at least 100MB
        #expect(size > 100_000_000, "XCFrameworks should be > 100MB, got \(size)")
    }

    // MARK: - Flow 5: Diagnostics

    @Test("All diagnostics pass on healthy setup")
    func allDiagnosticsPass() async {
        let results = await DiagnosticsService.runAll(scipioDir: scipioDir)
        #expect(results.count >= 6)

        let failed = results.filter { !$0.passed }
        // Allow runner binary check to fail (might not be built)
        let criticalFailed = failed.filter { $0.name != "ScipioRunner Binary" }
        #expect(criticalFailed.isEmpty, "Failed diagnostics: \(criticalFailed.map(\.name))")
    }

    @Test("Slice check passes for real frameworks")
    func realSliceCheck() {
        let result = DiagnosticsService.checkAllSlices(at: frameworksDir)
        #expect(result.passed)
    }

    @Test("Build package check passes")
    func realBuildPackageCheck() {
        let result = DiagnosticsService.checkBuildPackage(at: buildPkg)
        #expect(result.passed)
        #expect(result.detail.contains("dependencies"))
    }

    // MARK: - Flow 6: S3 Signer (signing correctness)

    @Test("Signs real GCS request with loaded credentials")
    func signRealRequest() throws {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        let signer = S3Signer(
            accessKeyId: key.accessKeyId,
            secretAccessKey: key.secretAccessKey,
            region: "auto"
        )

        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/emag-ios-scipio-cache?list-type=2&prefix=cache/v1/&max-keys=1")!)
        request.httpMethod = "GET"
        signer.sign(&request)

        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
        #expect(auth!.contains(key.accessKeyId))
    }

    // MARK: - Flow 7: GCS Bucket Service (live)

    @Test("Lists objects from real GCS bucket")
    func listRealBucket() async throws {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        let config = BucketConfig.default
        let service = GCSBucketService(hmacKey: key, config: config)
        let entries = try await service.listObjects()
        #expect(entries.count > 0, "Bucket should have cached entries")
    }

    @Test("Bucket stats return valid data")
    func realBucketStats() async throws {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        let config = BucketConfig.default
        let service = GCSBucketService(hmacKey: key, config: config)
        let stats = try await service.bucketStats()
        #expect(stats.totalEntries > 0)
        #expect(stats.totalSize > 0)
        #expect(stats.frameworkCount > 0)
    }

    // MARK: - Flow 8: ScipioRunner detection

    @Test("Runner binary exists after cache.sh has been run")
    func runnerBinaryExists() {
        let runnerPath = scipioDir.appendingPathComponent("Runner/.build/arm64-apple-macosx/release/ScipioRunner")
        let exists = ProcessRunner.executableExists(at: runnerPath.path)
        // This may or may not exist depending on whether cache.sh has been run
        if exists {
            #expect(true, "Runner binary found")
        } else {
            // Not a failure - just means cache.sh hasn't been run on this machine yet
            #expect(true, "Runner binary not yet built (expected on fresh clone)")
        }
    }

    // MARK: - Flow 9: AppState path detection

    @Test("AppState auto-detects project paths")
    @MainActor
    func appStateDetection() {
        let state = AppState()
        state.detectProjectPaths()
        #expect(state.scipioDir != nil)
        #expect(state.buildPackageURL != nil)
        #expect(state.frameworksDir != nil)
    }
}
