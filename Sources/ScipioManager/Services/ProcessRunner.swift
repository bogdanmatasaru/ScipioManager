import Foundation

/// Generic async wrapper around Foundation.Process with live output streaming.
struct ProcessRunner: Sendable {

    struct Output: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Run a command and collect all output.
    static func run(
        _ executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let wd = workingDirectory {
                process.currentDirectoryURL = wd
            }
            if let env = environment {
                process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            continuation.resume(returning: Output(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            ))
        }
    }

    /// Run a command and stream output lines as they arrive.
    static func stream(
        _ executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        onOutput: @escaping @Sendable (String, LogLine.Stream) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let wd = workingDirectory {
                process.currentDirectoryURL = wd
            }
            if let env = environment {
                process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                    onOutput(line, .stdout)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                    onOutput(line, .stderr)
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Check if an executable exists at the given path.
    static func executableExists(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
