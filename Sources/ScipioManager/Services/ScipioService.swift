import Foundation

/// Service for invoking ScipioRunner and cache.sh operations.
actor ScipioService {
    private let scipioDir: URL
    private let runnerBinaryPath: URL
    private let cacheScriptPath: URL
    private let runnerDir: URL
    private let buildDir: URL
    private let frameworksDir: URL

    init(scipioDir: URL) {
        self.scipioDir = scipioDir
        self.runnerBinaryPath = scipioDir
            .appendingPathComponent("Runner/.build/arm64-apple-macosx/release/ScipioRunner")
        self.cacheScriptPath = scipioDir.appendingPathComponent("Scripts/cache.sh")
        self.runnerDir = scipioDir.appendingPathComponent("Runner")
        self.buildDir = scipioDir.appendingPathComponent("Build")
        self.frameworksDir = scipioDir.appendingPathComponent("Frameworks/XCFrameworks")
    }

    enum SyncMode: String, Sendable {
        case producerAndConsumer = "Producer + Consumer"
        case consumerOnly = "Consumer Only"
    }

    // MARK: - Runner Management

    /// Check if the Runner binary exists and is executable.
    var runnerExists: Bool {
        ProcessRunner.executableExists(at: runnerBinaryPath.path)
    }

    /// Build the ScipioRunner binary.
    func buildRunner(
        onOutput: @escaping @Sendable (String, LogLine.Stream) -> Void
    ) async throws {
        onOutput("[BUILD] Compiling ScipioRunner...", .stdout)

        let exitCode = try await ProcessRunner.stream(
            "/usr/bin/swift",
            arguments: ["build", "--configuration", "release", "--package-path", runnerDir.path],
            onOutput: onOutput
        )

        guard exitCode == 0 else {
            throw ScipioError.runnerBuildFailed(exitCode: exitCode)
        }

        onOutput("[BUILD] ScipioRunner compiled successfully", .stdout)
    }

    // MARK: - Sync Operations

    /// Run Scipio sync (build + cache or consumer-only).
    func sync(
        mode: SyncMode,
        verbose: Bool = false,
        onOutput: @escaping @Sendable (String, LogLine.Stream) -> Void
    ) async throws -> SyncResult {
        // Ensure runner exists
        if !runnerExists {
            onOutput("[INFO] Runner binary not found, building...", .stdout)
            try await buildRunner(onOutput: onOutput)
        }

        var args: [String] = []
        if mode == .consumerOnly {
            args.append("--consumer-only")
        }
        if verbose {
            args.append("--verbose")
        }

        let startTime = Date()
        onOutput("[SYNC] Starting Scipio (\(mode.rawValue))...", .stdout)

        let exitCode = try await ProcessRunner.stream(
            runnerBinaryPath.path,
            arguments: args,
            workingDirectory: scipioDir,
            environment: ["SCIPIO_DIR": scipioDir.path],
            onOutput: onOutput
        )

        let elapsed = Date().timeIntervalSince(startTime)

        guard exitCode == 0 else {
            throw ScipioError.syncFailed(exitCode: exitCode)
        }

        // Count frameworks
        let count = frameworkCount()

        return SyncResult(
            frameworkCount: count,
            elapsed: elapsed,
            mode: mode
        )
    }

    // MARK: - Framework Discovery

    /// Count xcframeworks on disk.
    func frameworkCount() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: frameworksDir,
            includingPropertiesForKeys: nil
        ) else { return 0 }

        return contents.filter { $0.pathExtension == "xcframework" }.count
    }

    /// Discover all xcframeworks on disk with metadata.
    func discoverFrameworks() throws -> [FrameworkInfo] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: frameworksDir,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "xcframework" }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                let slices = discoverSlices(at: url)
                let size = directorySize(url)
                return FrameworkInfo(
                    name: name,
                    slices: slices,
                    sizeBytes: size
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func discoverSlices(at xcframeworkURL: URL) -> [ArchSlice] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: xcframeworkURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "Info.plist" }
            .map { dir in
                let id = dir.lastPathComponent
                let platform: String
                if id.contains("simulator") {
                    platform = "Simulator"
                } else if id.contains("arm64") {
                    platform = "Device (arm64)"
                } else {
                    platform = id
                }
                return ArchSlice(identifier: id, platform: platform)
            }
    }

    private func directorySize(_ url: URL) -> Int64 {
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

    // MARK: - Errors

    enum ScipioError: Error, LocalizedError {
        case runnerBuildFailed(exitCode: Int32)
        case syncFailed(exitCode: Int32)

        var errorDescription: String? {
            switch self {
            case .runnerBuildFailed(let code): return "ScipioRunner build failed (exit code \(code))"
            case .syncFailed(let code): return "Scipio sync failed (exit code \(code))"
            }
        }
    }

    struct SyncResult: Sendable {
        let frameworkCount: Int
        let elapsed: TimeInterval
        let mode: SyncMode

        var elapsedFormatted: String {
            let seconds = Int(elapsed)
            if seconds < 60 { return "\(seconds)s" }
            return "\(seconds / 60)m \(seconds % 60)s"
        }
    }
}
