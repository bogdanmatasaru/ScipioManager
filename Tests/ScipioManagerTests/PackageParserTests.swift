import Testing
import Foundation
@testable import ScipioManager

@Suite("Package Parser Tests")
struct PackageParserTests {

    let samplePackage = """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "ScipioBuild",
        platforms: [.iOS(.v15)],
        dependencies: [
            .package(url: "https://github.com/ReactiveX/RxSwift.git", exact: "6.10.1"),
            .package(url: "https://github.com/Alamofire/Alamofire.git", exact: "5.11.1"),
            .package(url: "https://github.com/bogdanmatasaru/AMPopTip.git", exact: "4.5.4"),
            .package(url: "https://github.com/bogdanmatasaru/ClusterKit", revision: "be4c9991358b"),
        ],
        targets: [
            .target(
                name: "ScipioBuildDummy",
                dependencies: [
                    .product(name: "RxSwift", package: "RxSwift"),
                    .product(name: "RxCocoa", package: "RxSwift"),
                    .product(name: "Alamofire", package: "Alamofire"),
                    .product(name: "AMPopTip", package: "AMPopTip"),
                    .product(name: "ClusterKit", package: "ClusterKit"),
                ],
                path: "Sources/Dummy"
            ),
        ]
    )
    """

    @Test("Parses exact version dependencies")
    func parseExact() {
        let deps = PackageParser.parseDependencies(from: samplePackage)
        let rxSwift = deps.first { $0.packageName == "RxSwift" }
        #expect(rxSwift != nil)
        #expect(rxSwift?.version == "6.10.1")
        #expect(rxSwift?.versionType == .exact)
    }

    @Test("Parses revision dependencies")
    func parseRevision() {
        let deps = PackageParser.parseDependencies(from: samplePackage)
        let clusterKit = deps.first { $0.packageName == "ClusterKit" }
        #expect(clusterKit != nil)
        #expect(clusterKit?.version == "be4c9991358b")
        #expect(clusterKit?.versionType == .revision)
    }

    @Test("Detects custom forks")
    func detectForks() {
        let deps = PackageParser.parseDependencies(from: samplePackage)
        let amPopTip = deps.first { $0.packageName == "AMPopTip" }
        #expect(amPopTip?.isCustomFork == true)

        let alamofire = deps.first { $0.packageName == "Alamofire" }
        #expect(alamofire?.isCustomFork == false)
    }

    @Test("Finds correct product count")
    func productCount() {
        let deps = PackageParser.parseDependencies(from: samplePackage)
        // RxSwift has 2 products: RxSwift and RxCocoa
        let rxSwift = deps.first { $0.packageName == "RxSwift" }
        #expect(rxSwift?.products.count == 2)
        #expect(rxSwift?.products.contains("RxSwift") == true)
        #expect(rxSwift?.products.contains("RxCocoa") == true)
    }

    @Test("Parses all dependencies")
    func totalCount() {
        let deps = PackageParser.parseDependencies(from: samplePackage)
        #expect(deps.count == 4)
    }

    @Test("Extracts package name from URL")
    func packageNameExtraction() {
        #expect(PackageParser.extractPackageName(from: "https://github.com/ReactiveX/RxSwift.git") == "RxSwift")
        #expect(PackageParser.extractPackageName(from: "https://github.com/Alamofire/Alamofire.git") == "Alamofire")
        #expect(PackageParser.extractPackageName(from: "https://github.com/bogdanmatasaru/AMPopTip") == "AMPopTip")
        #expect(PackageParser.extractPackageName(from: "https://github.com/foo/bar-baz.git") == "bar-baz")
    }

    @Test("Display version formatting")
    func displayVersion() {
        let exact = ParsedDependency(url: "", version: "1.0.0", versionType: .exact, packageName: "", products: [], isCustomFork: false)
        #expect(exact.displayVersion == "1.0.0")

        let revision = ParsedDependency(url: "", version: "abcdef123456789", versionType: .revision, packageName: "", products: [], isCustomFork: false)
        #expect(revision.displayVersion == "abcdef123456")

        let from = ParsedDependency(url: "", version: "2.0.0", versionType: .from, packageName: "", products: [], isCustomFork: false)
        #expect(from.displayVersion == ">= 2.0.0")
    }
}
