// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScipioManager",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ScipioManager", targets: ["ScipioManager"]),
    ],
    targets: [
        .executableTarget(
            name: "ScipioManager",
            path: "Sources/ScipioManager"
        ),
        .testTarget(
            name: "ScipioManagerTests",
            dependencies: ["ScipioManager"],
            path: "Tests/ScipioManagerTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
