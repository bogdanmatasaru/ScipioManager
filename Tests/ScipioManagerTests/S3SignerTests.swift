import Testing
import Foundation
@testable import ScipioManager

@Suite("S3 Signer Tests")
struct S3SignerTests {

    let signer = S3Signer(
        accessKeyId: "GOOG1ETEST",
        secretAccessKey: "testSecretKey12345",
        region: "auto"
    )

    @Test("Signs request with correct Authorization header format")
    func signatureFormat() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/test-bucket?list-type=2")!)
        request.httpMethod = "GET"

        let fixedDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 2, day: 14,
            hour: 12, minute: 0, second: 0
        ).date!

        signer.sign(&request, date: fixedDate)

        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
        #expect(auth!.hasPrefix("AWS4-HMAC-SHA256 Credential=GOOG1ETEST/"))
        #expect(auth!.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))
        #expect(auth!.contains("Signature="))
    }

    @Test("Sets required x-amz headers")
    func requiredHeaders() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket")!)
        request.httpMethod = "GET"
        signer.sign(&request)

        #expect(request.value(forHTTPHeaderField: "x-amz-date") != nil)
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") != nil)
        #expect(request.value(forHTTPHeaderField: "Host") != nil)
    }

    @Test("Produces consistent signatures for same input")
    func deterministicSignature() {
        let date = Date(timeIntervalSince1970: 1_000_000)

        var req1 = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket/key")!)
        req1.httpMethod = "GET"
        signer.sign(&req1, date: date)

        var req2 = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket/key")!)
        req2.httpMethod = "GET"
        signer.sign(&req2, date: date)

        #expect(req1.value(forHTTPHeaderField: "Authorization") == req2.value(forHTTPHeaderField: "Authorization"))
    }

    @Test("Different methods produce different signatures")
    func methodAffectsSignature() {
        let date = Date(timeIntervalSince1970: 1_000_000)

        var getReq = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket/key")!)
        getReq.httpMethod = "GET"
        signer.sign(&getReq, date: date)

        var deleteReq = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket/key")!)
        deleteReq.httpMethod = "DELETE"
        signer.sign(&deleteReq, date: date)

        #expect(getReq.value(forHTTPHeaderField: "Authorization") != deleteReq.value(forHTTPHeaderField: "Authorization"))
    }

    @Test("Payload hash is e3b0c44... for empty body (SHA256 of empty string)")
    func emptyPayloadHash() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket")!)
        request.httpMethod = "GET"
        signer.sign(&request)

        let hash = request.value(forHTTPHeaderField: "x-amz-content-sha256")
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
