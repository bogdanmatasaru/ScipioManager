import Foundation

/// Parses and modifies Scipio's Build/Package.swift.
struct PackageParser: Sendable {

    // MARK: - Parsing

    /// Parse all dependencies from a Package.swift file.
    static func parseDependencies(from fileURL: URL) throws -> [ParsedDependency] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return parseDependencies(from: content)
    }

    /// Parse dependencies from Package.swift content string.
    static func parseDependencies(from content: String) -> [ParsedDependency] {
        var dependencies: [ParsedDependency] = []

        // Match .package(url: "...", exact: "...") and .package(url: "...", revision: "...")
        // and .package(url: "...", from: "...")
        let packagePattern = #/\.package\(\s*url:\s*"([^"]+)"\s*,\s*(exact|revision|from|branch):\s*"([^"]+)"\s*\)/#

        for match in content.matches(of: packagePattern) {
            let url = String(match.1)
            let versionType = String(match.2)
            let version = String(match.3)
            let packageName = extractPackageName(from: url)
            let isCustomFork = url.contains("bogdanmatasaru") || url.contains("alinfarcas")

            dependencies.append(ParsedDependency(
                url: url,
                version: version,
                versionType: ParsedDependency.VersionType(rawValue: versionType) ?? .exact,
                packageName: packageName,
                products: [],
                isCustomFork: isCustomFork
            ))
        }

        // Now find products for each package
        let productPattern = #/\.product\(\s*name:\s*"([^"]+)"\s*,\s*package:\s*"([^"]+)"\s*\)/#
        var productsByPackage: [String: [String]] = [:]

        for match in content.matches(of: productPattern) {
            let productName = String(match.1)
            let packageRef = String(match.2)
            productsByPackage[packageRef, default: []].append(productName)
        }

        // Merge products into dependencies
        return dependencies.map { dep in
            var updated = dep
            // Try matching by package name
            let products = productsByPackage[dep.packageName] ?? []
            updated = ParsedDependency(
                url: dep.url,
                version: dep.version,
                versionType: dep.versionType,
                packageName: dep.packageName,
                products: products,
                isCustomFork: dep.isCustomFork
            )
            return updated
        }
    }

    // MARK: - Modification

    /// Add a new dependency to Package.swift.
    static func addDependency(
        to fileURL: URL,
        url: String,
        version: String,
        versionType: ParsedDependency.VersionType = .exact,
        productName: String,
        section: String = "Other"
    ) throws {
        var content = try String(contentsOf: fileURL, encoding: .utf8)

        // Build the package line
        let packageLine: String
        switch versionType {
        case .exact:
            packageLine = "        .package(url: \"\(url)\", exact: \"\(version)\"),"
        case .revision:
            packageLine = "        .package(url: \"\(url)\", revision: \"\(version)\"),"
        case .from:
            packageLine = "        .package(url: \"\(url)\", from: \"\(version)\"),"
        case .branch:
            packageLine = "        .package(url: \"\(url)\", branch: \"\(version)\"),"
        }

        // Find insertion point for the package dependency (before the closing `],` of dependencies array)
        let packageName = extractPackageName(from: url)
        let productLine = "                .product(name: \"\(productName)\", package: \"\(packageName)\"),"

        // Insert package dependency before the last entry in dependencies
        if let range = content.range(of: "    ],\n    targets:") {
            content.insert(contentsOf: "\n\(packageLine)\n", at: range.lowerBound)
        }

        // Insert product dependency before the closing `],` of ScipioBuildDummy's dependencies
        if let range = content.range(of: "            ],\n            path: \"Sources/Dummy\"") {
            content.insert(contentsOf: "\n\(productLine)\n", at: range.lowerBound)
        }

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Remove a dependency from Package.swift.
    static func removeDependency(from fileURL: URL, packageURL: String, productNames: [String]) throws {
        var content = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = content.components(separatedBy: .newlines)

        // Remove .package(url: "...") lines matching the URL
        lines.removeAll { line in
            line.contains(".package(url: \"\(packageURL)\"")
        }

        // Remove .product(name: "...") lines matching product names
        for product in productNames {
            lines.removeAll { line in
                line.contains(".product(name: \"\(product)\"")
            }
        }

        content = lines.joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Update a dependency version in Package.swift.
    static func updateVersion(
        in fileURL: URL,
        packageURL: String,
        newVersion: String
    ) throws {
        var content = try String(contentsOf: fileURL, encoding: .utf8)

        // Find the line with this package URL and replace the version
        let escapedURL = NSRegularExpression.escapedPattern(for: packageURL)
        let pattern = "(\\.package\\(url:\\s*\"\(escapedURL)\"\\s*,\\s*(?:exact|from):\\s*\")([^\"]+)(\"\\))"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)

        content = regex.stringByReplacingMatches(
            in: content,
            range: range,
            withTemplate: "$1\(newVersion)$3"
        )

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Utilities

    /// Extract the package name from a GitHub URL.
    static func extractPackageName(from url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleaned.components(separatedBy: "/").last ?? url
    }
}
