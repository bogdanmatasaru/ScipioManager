import Testing
import Foundation
@testable import ScipioManager

@Suite("HMAC Key Loader Extended Tests")
struct HMACKeyLoaderExtTests {

    @Test("HMACKey Codable round-trip")
    func codableRoundTrip() throws {
        let original = HMACKey(accessKeyId: "GOOG123", secretAccessKey: "secret456")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HMACKey.self, from: data)
        #expect(decoded.accessKeyId == "GOOG123")
        #expect(decoded.secretAccessKey == "secret456")
    }

    @Test("LoadError description for no credentials")
    func noCredentialsDescription() {
        let err = HMACKeyLoader.LoadError.noCredentials(searchedPath: "/some/path")
        #expect(err.localizedDescription.contains("/some/path"))
        #expect(err.localizedDescription.contains("SCIPIO_GCS_HMAC"))
    }

    @Test("LoadError description for invalid JSON")
    func invalidJSONDescription() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad format"])
        let err = HMACKeyLoader.LoadError.invalidJSON(path: "/test/file.json", underlying: underlying)
        #expect(err.localizedDescription.contains("/test/file.json"))
    }

    @Test("CredentialSource raw values")
    func credentialSourceRawValues() {
        #expect(HMACKeyLoader.CredentialSource.environmentVariables.rawValue == "Environment Variables")
        #expect(HMACKeyLoader.CredentialSource.jsonFile.rawValue == "JSON File (gcs-hmac.json)")
        #expect(HMACKeyLoader.CredentialSource.none.rawValue == "Not Found")
    }

    @Test("Credential check for nonexistent path returns none")
    func credentialCheckNonexistent() {
        let path = URL(fileURLWithPath: "/tmp/no-such-\(UUID()).json")
        let source = HMACKeyLoader.credentialsAvailable(at: path)
        #expect(source == .none)
    }

    @Test("Load from incomplete JSON throws invalidJSON")
    func loadIncompleteJSON() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("hmac-incomplete-\(UUID()).json")
        try "{ \"accessKeyId\": \"test\" }".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        #expect(throws: HMACKeyLoader.LoadError.self) {
            try HMACKeyLoader.load(from: tempFile)
        }
    }

    @Test("Load from non-JSON file throws invalidJSON")
    func loadNonJSON() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("hmac-bad-\(UUID()).json")
        try "not json at all".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        #expect(throws: HMACKeyLoader.LoadError.self) {
            try HMACKeyLoader.load(from: tempFile)
        }
    }

    @Test("Load from valid JSON succeeds")
    func loadValidJSON() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("hmac-valid-\(UUID()).json")
        let json = """
        {"accessKeyId": "GOOG1ETEST", "secretAccessKey": "testsecret"}
        """
        try json.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let key = try HMACKeyLoader.load(from: tempFile)
        #expect(key.accessKeyId == "GOOG1ETEST")
        #expect(key.secretAccessKey == "testsecret")
    }

    @Test("Credential source detects existing JSON file")
    func credentialSourceJSON() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("hmac-source-\(UUID()).json")
        try "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let source = HMACKeyLoader.credentialsAvailable(at: tempFile)
        #expect(source == .jsonFile)
    }
}
