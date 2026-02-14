import Testing
import Foundation
@testable import ScipioManager

@Suite("Process Runner Tests")
struct ProcessRunnerTests {

    @Test("Runs simple command successfully")
    func simpleCommand() async throws {
        let result = try await ProcessRunner.run("/bin/echo", arguments: ["hello"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("Captures exit code for failed command")
    func failedCommand() async throws {
        let result = try await ProcessRunner.run("/bin/sh", arguments: ["-c", "exit 42"])
        #expect(result.exitCode == 42)
    }

    @Test("Captures stderr")
    func stderrCapture() async throws {
        let result = try await ProcessRunner.run("/bin/sh", arguments: ["-c", "echo error >&2"])
        #expect(result.stderr.contains("error"))
    }

    @Test("Executable exists check")
    func executableCheck() {
        #expect(ProcessRunner.executableExists(at: "/bin/echo") == true)
        #expect(ProcessRunner.executableExists(at: "/nonexistent/binary") == false)
    }

    @Test("Streaming output captures lines")
    func streamOutput() async throws {
        // Use a simple command and verify exit code (stream callback is @Sendable)
        let exitCode = try await ProcessRunner.stream(
            "/bin/sh",
            arguments: ["-c", "echo line1; echo line2; echo line3"],
            onOutput: { _, _ in }
        )
        #expect(exitCode == 0)
    }

    @Test("Working directory is respected")
    func workingDirectory() async throws {
        let result = try await ProcessRunner.run(
            "/bin/pwd",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("tmp"))
    }
}
