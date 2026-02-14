import Testing
import Foundation
@testable import ScipioManager

/// Thread-safe wrapper for collecting values from Sendable closures.
final class LockIsolated<Value: Sendable>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) { _value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}

@Suite("Process Runner Extended Tests")
struct ProcessRunnerExtTests {

    @Test("Run with custom environment variables")
    func customEnv() async throws {
        let output = try await ProcessRunner.run(
            "/usr/bin/env",
            environment: ["SCIPIO_TEST_VAR": "hello_world"]
        )
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("SCIPIO_TEST_VAR=hello_world"))
    }

    @Test("Run with arguments")
    func runWithArgs() async throws {
        let output = try await ProcessRunner.run("/bin/echo", arguments: ["hello", "world"])
        #expect(output.exitCode == 0)
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
    }

    @Test("Stderr captured separately")
    func stderrCapture() async throws {
        let output = try await ProcessRunner.run("/bin/sh", arguments: ["-c", "echo error >&2"])
        #expect(output.stderr.contains("error"))
    }

    @Test("Exit code for false command")
    func falseCommand() async throws {
        let output = try await ProcessRunner.run("/usr/bin/false")
        #expect(output.exitCode != 0)
    }

    @Test("Executable exists for known binary")
    func knownBinary() {
        #expect(ProcessRunner.executableExists(at: "/bin/sh") == true)
        #expect(ProcessRunner.executableExists(at: "/usr/bin/swift") == true)
    }

    @Test("Executable not found for fake path")
    func fakeBinary() {
        #expect(ProcessRunner.executableExists(at: "/nonexistent/binary") == false)
    }

    @Test("Executable not found for nonexistent path")
    func nonexistentPath() {
        #expect(ProcessRunner.executableExists(at: "/tmp/no-such-binary-\(UUID())") == false)
    }

    @Test("Stream returns correct exit code for success")
    func streamExitCodeSuccess() async throws {
        let exitCode = try await ProcessRunner.stream(
            "/usr/bin/true"
        ) { _, _ in }
        #expect(exitCode == 0)
    }

    @Test("Stream returns correct exit code for failure")
    func streamExitCodeFailure() async throws {
        let exitCode = try await ProcessRunner.stream(
            "/usr/bin/false"
        ) { _, _ in }
        #expect(exitCode != 0)
    }

    @Test("Run with working directory")
    func runWorkingDir() async throws {
        let output = try await ProcessRunner.run(
            "/bin/pwd",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("tmp"))
    }

    @Test("Run with merged environment")
    func runMergedEnv() async throws {
        let output = try await ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "echo $TEST_CUSTOM_VAR"],
            environment: ["TEST_CUSTOM_VAR": "custom_value"]
        )
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("custom_value"))
    }

    @Test("Output struct properties")
    func outputStruct() {
        let output = ProcessRunner.Output(exitCode: 42, stdout: "out\n", stderr: "err\n")
        #expect(output.exitCode == 42)
        #expect(output.stdout == "out\n")
        #expect(output.stderr == "err\n")
    }
}
