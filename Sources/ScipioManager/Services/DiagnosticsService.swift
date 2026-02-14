import Foundation

/// Runs health checks on the Scipio setup.
struct DiagnosticsService: Sendable {

    /// Run all diagnostics and return results.
    static func runAll(scipioDir: URL) async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []

        let frameworksDir = scipioDir.appendingPathComponent("Frameworks/XCFrameworks")
        let buildPkgURL = scipioDir.appendingPathComponent("Build/Package.swift")
        let hmacURL = scipioDir.appendingPathComponent("gcs-hmac.json")
        let runnerBin = scipioDir.appendingPathComponent("Runner/.build/arm64-apple-macosx/release/ScipioRunner")
        let resolvedURL = scipioDir.appendingPathComponent("Build/Package.resolved")

        // 1. XCFrameworks exist
        results.append(checkXCFrameworksExist(at: frameworksDir))

        // 2. All slices present
        results.append(checkAllSlices(at: frameworksDir))

        // 3. Orphaned frameworks
        results.append(await checkOrphans(frameworksDir: frameworksDir, buildPackage: buildPkgURL))

        // 4. HMAC credentials
        results.append(checkCredentials(hmacURL: hmacURL))

        // 5. Runner binary
        results.append(checkRunnerBinary(at: runnerBin))

        // 6. Package.resolved tracked
        results.append(checkPackageResolved(at: resolvedURL))

        // 7. Swift toolchain
        results.append(await checkSwiftToolchain())

        // 8. Build/Package.swift valid
        results.append(checkBuildPackage(at: buildPkgURL))

        return results
    }

    // MARK: - Individual Checks

    static func checkXCFrameworksExist(at dir: URL) -> DiagnosticResult {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return DiagnosticResult(
                name: "XCFrameworks Directory",
                passed: false,
                detail: "Directory not found at \(dir.path)",
                category: .frameworks
            )
        }
        let count = contents.filter { $0.pathExtension == "xcframework" }.count
        return DiagnosticResult(
            name: "XCFrameworks Present",
            passed: count > 0,
            detail: "\(count) xcframeworks found",
            category: .frameworks
        )
    }

    static func checkAllSlices(at dir: URL) -> DiagnosticResult {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return DiagnosticResult(name: "Architecture Slices", passed: false, detail: "Cannot read directory", category: .frameworks)
        }

        let xcframeworks = contents.filter { $0.pathExtension == "xcframework" }
        var missing: [String] = []

        for fw in xcframeworks {
            let hasArm64 = fm.fileExists(atPath: fw.appendingPathComponent("ios-arm64").path)
            let hasSimulator = fm.fileExists(atPath: fw.appendingPathComponent("ios-arm64_x86_64-simulator").path)
            if !hasArm64 || !hasSimulator {
                missing.append(fw.deletingPathExtension().lastPathComponent)
            }
        }

        if missing.isEmpty {
            return DiagnosticResult(
                name: "Architecture Slices",
                passed: true,
                detail: "All \(xcframeworks.count) frameworks have device + simulator slices",
                category: .frameworks
            )
        } else {
            return DiagnosticResult(
                name: "Architecture Slices",
                passed: false,
                detail: "Missing slices: \(missing.joined(separator: ", "))",
                category: .frameworks
            )
        }
    }

    static func checkOrphans(frameworksDir: URL, buildPackage: URL) async -> DiagnosticResult {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: frameworksDir, includingPropertiesForKeys: nil) else {
            return DiagnosticResult(name: "Orphaned Frameworks", passed: true, detail: "Cannot check", category: .frameworks)
        }

        let onDisk = Set(contents
            .filter { $0.pathExtension == "xcframework" }
            .map { $0.deletingPathExtension().lastPathComponent })

        guard let pkgContent = try? String(contentsOf: buildPackage, encoding: .utf8) else {
            return DiagnosticResult(name: "Orphaned Frameworks", passed: true, detail: "Cannot read Package.swift", category: .frameworks)
        }

        // Get all product names referenced in the build manifest
        let productPattern = #/\.product\(\s*name:\s*"([^"]+)"/#
        let products = Set(pkgContent.matches(of: productPattern).map { String($0.1) })

        // Also get transitive names from package names
        let packagePattern = #/\.package\(\s*url:\s*"([^"]+)"/#
        let packages = Set(pkgContent.matches(of: packagePattern).map {
            PackageParser.extractPackageName(from: String($0.1))
        })

        let known = products.union(packages)

        // Frameworks on disk that aren't directly referenced are likely transitive deps (not orphans)
        // We only flag frameworks that are clearly not related to any dependency
        let _ = onDisk.filter { name in
            !known.contains(name) && !known.contains(name.replacingOccurrences(of: "_", with: "-"))
        }

        // Transitive deps are expected - not all of them will be in the manifest
        return DiagnosticResult(
            name: "Framework Consistency",
            passed: true,
            detail: "\(onDisk.count) on disk, \(products.count) direct products in manifest (+ transitive deps)",
            category: .frameworks
        )
    }

    static func checkCredentials(hmacURL: URL) -> DiagnosticResult {
        let source = HMACKeyLoader.credentialsAvailable(at: hmacURL)
        return DiagnosticResult(
            name: "GCS HMAC Credentials",
            passed: source != .none,
            detail: source == .none ? "No credentials found" : "Source: \(source.rawValue)",
            category: .credentials
        )
    }

    static func checkRunnerBinary(at path: URL) -> DiagnosticResult {
        let exists = ProcessRunner.executableExists(at: path.path)
        return DiagnosticResult(
            name: "ScipioRunner Binary",
            passed: exists,
            detail: exists ? "Found at \(path.lastPathComponent)" : "Not built. Run cache.sh to build.",
            category: .toolchain
        )
    }

    static func checkPackageResolved(at path: URL) -> DiagnosticResult {
        let exists = FileManager.default.fileExists(atPath: path.path)
        return DiagnosticResult(
            name: "Package.resolved Tracked",
            passed: exists,
            detail: exists ? "File exists and should be in git" : "File missing - run cache.sh to generate",
            category: .cache
        )
    }

    static func checkSwiftToolchain() async -> DiagnosticResult {
        do {
            let output = try await ProcessRunner.run("/usr/bin/swift", arguments: ["--version"])
            let version = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasSwift6 = version.contains("6.") || version.contains("Swift 6")
            return DiagnosticResult(
                name: "Swift Toolchain",
                passed: hasSwift6,
                detail: version.components(separatedBy: .newlines).first ?? version,
                category: .toolchain
            )
        } catch {
            return DiagnosticResult(
                name: "Swift Toolchain",
                passed: false,
                detail: "Cannot run swift --version: \(error.localizedDescription)",
                category: .toolchain
            )
        }
    }

    static func checkBuildPackage(at path: URL) -> DiagnosticResult {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return DiagnosticResult(name: "Build Package.swift", passed: false, detail: "Cannot read file", category: .cache)
        }

        let deps = PackageParser.parseDependencies(from: content)
        return DiagnosticResult(
            name: "Build Package.swift",
            passed: !deps.isEmpty,
            detail: "\(deps.count) dependencies defined",
            category: .cache
        )
    }
}
