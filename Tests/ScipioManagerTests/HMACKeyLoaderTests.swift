import Testing
import Foundation
@testable import ScipioManager

@Suite("HMAC Key Loader Tests")
struct HMACKeyLoaderTests {

    @Test("Loads from valid JSON file")
    func loadFromJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyFile = tempDir.appendingPathComponent("gcs-hmac.json")
        let json = """
        { "accessKeyId": "GOOG1ETEST", "secretAccessKey": "secret123" }
        """
        try json.write(to: keyFile, atomically: true, encoding: .utf8)

        let key = try HMACKeyLoader.load(from: keyFile)
        #expect(key.accessKeyId == "GOOG1ETEST")
        #expect(key.secretAccessKey == "secret123")
    }

    @Test("Throws for missing file")
    func missingFile() {
        let fakePath = URL(fileURLWithPath: "/nonexistent/gcs-hmac.json")
        #expect(throws: HMACKeyLoader.LoadError.self) {
            try HMACKeyLoader.load(from: fakePath)
        }
    }

    @Test("Throws for invalid JSON")
    func invalidJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyFile = tempDir.appendingPathComponent("gcs-hmac.json")
        try "not valid json".write(to: keyFile, atomically: true, encoding: .utf8)

        #expect(throws: HMACKeyLoader.LoadError.self) {
            try HMACKeyLoader.load(from: keyFile)
        }
    }

    @Test("Credential source detects JSON file")
    func credentialSourceJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyFile = tempDir.appendingPathComponent("gcs-hmac.json")
        try "{}".write(to: keyFile, atomically: true, encoding: .utf8)

        let source = HMACKeyLoader.credentialsAvailable(at: keyFile)
        #expect(source == .jsonFile)
    }

    @Test("Credential source returns none for missing file")
    func credentialSourceNone() {
        let fakePath = URL(fileURLWithPath: "/nonexistent/gcs-hmac.json")
        let source = HMACKeyLoader.credentialsAvailable(at: fakePath)
        #expect(source == .none)
    }
}
