import Testing
import Foundation
@testable import ScipioManager

@Suite("Package Parser Modification Tests")
struct PackageParserModifyTests {

    // Create a minimal Package.swift template that matches real patterns
    let templatePackage = """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "ScipioBuild",
        platforms: [.iOS(.v15)],
        dependencies: [
            .package(url: "https://github.com/ReactiveX/RxSwift.git", exact: "6.10.1"),
            .package(url: "https://github.com/Alamofire/Alamofire.git", exact: "5.11.1"),
        ],
        targets: [
            .target(
                name: "ScipioBuildDummy",
                dependencies: [
                    .product(name: "RxSwift", package: "RxSwift"),
                    .product(name: "Alamofire", package: "Alamofire"),
                ],
                path: "Sources/Dummy"
            ),
        ]
    )
    """

    private func createTempFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScipioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("Package.swift")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("Add dependency inserts package and product")
    func addDependency() throws {
        let url = try createTempFile(content: templatePackage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try PackageParser.addDependency(
            to: url,
            url: "https://github.com/onevcat/Kingfisher.git",
            version: "8.2.0",
            productName: "Kingfisher"
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("Kingfisher.git"))
        #expect(content.contains("8.2.0"))
        #expect(content.contains(".product(name: \"Kingfisher\""))

        let deps = PackageParser.parseDependencies(from: content)
        let kf = deps.first { $0.packageName == "Kingfisher" }
        #expect(kf != nil)
        #expect(kf?.version == "8.2.0")
    }

    @Test("Add dependency with from version type")
    func addDependencyFrom() throws {
        let url = try createTempFile(content: templatePackage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try PackageParser.addDependency(
            to: url,
            url: "https://github.com/SDWebImage/SDWebImage.git",
            version: "5.0.0",
            versionType: .from,
            productName: "SDWebImage"
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("from: \"5.0.0\""))
    }

    @Test("Add dependency with revision type")
    func addDependencyRevision() throws {
        let url = try createTempFile(content: templatePackage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try PackageParser.addDependency(
            to: url,
            url: "https://github.com/foo/bar.git",
            version: "abc123",
            versionType: .revision,
            productName: "Bar"
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("revision: \"abc123\""))
    }

    @Test("Add dependency with branch type")
    func addDependencyBranch() throws {
        let url = try createTempFile(content: templatePackage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try PackageParser.addDependency(
            to: url,
            url: "https://github.com/foo/baz.git",
            version: "main",
            versionType: .branch,
            productName: "Baz"
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("branch: \"main\""))
    }

    @Test("Remove dependency removes package and product lines")
    func removeDependency() throws {
        let url = try createTempFile(content: templatePackage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try PackageParser.removeDependency(
            from: url,
            packageURL: "https://github.com/Alamofire/Alamofire.git",
            productNames: ["Alamofire"]
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.contains("Alamofire.git"))
        #expect(!content.contains(".product(name: \"Alamofire\""))

        // RxSwift should still be there
        #expect(content.contains("RxSwift.git"))
    }

    @Test("Update version changes exact version")
    func updateVersion() throws {
        let url = try createTempFile(content: templatePackage)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try PackageParser.updateVersion(
            in: url,
            packageURL: "https://github.com/ReactiveX/RxSwift.git",
            newVersion: "6.11.0"
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("6.11.0"))
        #expect(!content.contains("6.10.1"))
    }

    @Test("Parse from: version type")
    func parseFromVersion() {
        let pkg = """
        .package(url: "https://github.com/foo/bar.git", from: "3.0.0"),
        """
        let deps = PackageParser.parseDependencies(from: pkg)
        #expect(deps.count == 1)
        #expect(deps[0].versionType == .from)
        #expect(deps[0].version == "3.0.0")
    }

    @Test("Parse branch version type")
    func parseBranch() {
        let pkg = """
        .package(url: "https://github.com/foo/bar.git", branch: "develop"),
        """
        let deps = PackageParser.parseDependencies(from: pkg)
        #expect(deps.count == 1)
        #expect(deps[0].versionType == .branch)
        #expect(deps[0].version == "develop")
    }

    @Test("Parse empty content returns empty")
    func parseEmpty() {
        let deps = PackageParser.parseDependencies(from: "")
        #expect(deps.isEmpty)
    }

    @Test("Parse content with no dependencies")
    func parseNoDeps() {
        let content = "let package = Package(name: \"Empty\", targets: [])"
        let deps = PackageParser.parseDependencies(from: content)
        #expect(deps.isEmpty)
    }

    @Test("Throws for missing file")
    func missingFile() {
        let badURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID()).swift")
        #expect(throws: Error.self) {
            try PackageParser.parseDependencies(from: badURL)
        }
    }

    @Test("Extract package name edge cases")
    func packageNameEdgeCases() {
        #expect(PackageParser.extractPackageName(from: "https://github.com/a/b") == "b")
        #expect(PackageParser.extractPackageName(from: "https://github.com/a/b.git") == "b")
        #expect(PackageParser.extractPackageName(from: "b.git") == "b")
        #expect(PackageParser.extractPackageName(from: "") == "")
    }
}
