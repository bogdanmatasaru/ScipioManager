import Testing
import Foundation
@testable import ScipioManager

/// Integration tests that run against a real Scipio project.
/// These require the project to exist with a valid scipio-manager.json config.
/// Enable by setting SCIPIO_INTEGRATION_TEST_DIR environment variable.
@Suite("Integration Tests", .enabled(if: {
    if let dir = ProcessInfo.processInfo.environment["SCIPIO_INTEGRATION_TEST_DIR"] {
        return FileManager.default.fileExists(atPath: dir + "/Build/Package.swift")
    }
    return false
}()))
struct IntegrationTests {

    var scipioDir: URL {
        let path = ProcessInfo.processInfo.environment["SCIPIO_INTEGRATION_TEST_DIR"] ?? "/tmp"
        return URL(fileURLWithPath: path)
    }
    var buildPkg: URL { scipioDir.appendingPathComponent("Build/Package.swift") }
    var frameworksDir: URL { scipioDir.appendingPathComponent("Frameworks/XCFrameworks") }
    var hmacKeyURL: URL { scipioDir.appendingPathComponent("gcs-hmac.json") }

    // MARK: - Flow 1: Framework Discovery

    @Test("Discovers all xcframeworks on disk")
    func discoverFrameworks() async throws {
        let service = ScipioService(scipioDir: scipioDir)
        let frameworks = try await service.discoverFrameworks()
        #expect(frameworks.count > 0, "Expected frameworks, got \(frameworks.count)")

        // Verify each framework has slices
        for fw in frameworks {
            #expect(!fw.slices.isEmpty, "\(fw.name) has no architecture slices")
        }
    }

    @Test("Framework count matches disk")
    func frameworkCount() async {
        let service = ScipioService(scipioDir: scipioDir)
        let count = await service.frameworkCount()
        #expect(count > 0)
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
        #expect(deps.count > 0, "Expected dependencies, got \(deps.count)")
    }

    @Test("Parses products for multi-product packages")
    func multiProductPackages() throws {
        let deps = try PackageParser.parseDependencies(from: buildPkg)
        let multiProduct = deps.first { $0.products.count >= 2 }
        #expect(multiProduct != nil, "Should have at least one multi-product package")
    }

    // MARK: - Flow 3: HMAC Key Loading

    @Test("Loads real HMAC credentials")
    func loadRealHMAC() throws {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        #expect(!key.accessKeyId.isEmpty)
        #expect(!key.secretAccessKey.isEmpty)
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

    // MARK: - Flow 6: S3 Signer

    @Test("Signs real GCS request with loaded credentials")
    func signRealRequest() throws {
        let key = try HMACKeyLoader.load(from: hmacKeyURL)
        let signer = S3Signer(
            accessKeyId: key.accessKeyId,
            secretAccessKey: key.secretAccessKey,
            region: "auto"
        )

        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/test-bucket?list-type=2&max-keys=1")!)
        request.httpMethod = "GET"
        signer.sign(&request)

        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
        #expect(auth!.contains(key.accessKeyId))
    }
}
