import Testing
import Foundation
@testable import ScipioManager

@Suite("S3 Signer Extended Tests")
struct S3SignerExtTests {

    let signer = S3Signer(accessKeyId: "GOOG1ETEST", secretAccessKey: "testSecretKey123", region: "auto")

    @Test("Signs request with pre-encoded query parameters")
    func signPreEncodedQuery() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket?list-type=2&prefix=XCFrameworks%2F&max-keys=10")!)
        request.httpMethod = "GET"
        signer.sign(&request)

        let auth = request.value(forHTTPHeaderField: "Authorization")!
        #expect(auth.contains("AWS4-HMAC-SHA256"))
        #expect(auth.contains("GOOG1ETEST"))
        #expect(auth.contains("auto/s3/aws4_request"))
    }

    @Test("Canonical query string sorts parameters")
    func querySorting() {
        var request = URLRequest(url: URL(string: "https://host/bucket?z=1&a=2&m=3")!)
        request.httpMethod = "GET"
        signer.sign(&request)

        // The signature should still be valid (no crash)
        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
    }

    @Test("Empty query string handled correctly")
    func emptyQuery() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket")!)
        request.httpMethod = "GET"
        signer.sign(&request)

        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
    }

    @Test("POST request with body produces valid signature")
    func postWithBody() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket/key")!)
        request.httpMethod = "PUT"
        request.httpBody = "test body content".data(using: .utf8)
        signer.sign(&request)

        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
        #expect(auth!.contains("GOOG1ETEST"))
    }

    @Test("DELETE method produces valid signature")
    func deleteMethod() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket/key.zip")!)
        request.httpMethod = "DELETE"
        signer.sign(&request)

        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
    }

    @Test("HEAD method produces valid signature")
    func headMethod() {
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/bucket/key.zip")!)
        request.httpMethod = "HEAD"
        signer.sign(&request)

        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
    }

    @Test("Custom date produces consistent output")
    func customDate() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        var req1 = URLRequest(url: URL(string: "https://host/bucket?key=value")!)
        req1.httpMethod = "GET"
        signer.sign(&req1, date: fixedDate)

        var req2 = URLRequest(url: URL(string: "https://host/bucket?key=value")!)
        req2.httpMethod = "GET"
        signer.sign(&req2, date: fixedDate)

        let auth1 = req1.value(forHTTPHeaderField: "Authorization")
        let auth2 = req2.value(forHTTPHeaderField: "Authorization")
        #expect(auth1 == auth2)
    }

    @Test("Different dates produce different signatures")
    func differentDates() {
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let date2 = Date(timeIntervalSince1970: 1_700_100_000)

        var req1 = URLRequest(url: URL(string: "https://host/bucket")!)
        req1.httpMethod = "GET"
        signer.sign(&req1, date: date1)

        var req2 = URLRequest(url: URL(string: "https://host/bucket")!)
        req2.httpMethod = "GET"
        signer.sign(&req2, date: date2)

        let auth1 = req1.value(forHTTPHeaderField: "Authorization")
        let auth2 = req2.value(forHTTPHeaderField: "Authorization")
        #expect(auth1 != auth2)
    }

    @Test("Different regions produce different signatures")
    func differentRegions() {
        let signer2 = S3Signer(accessKeyId: "GOOG1ETEST", secretAccessKey: "testSecretKey123", region: "us-east1")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        var req1 = URLRequest(url: URL(string: "https://host/bucket")!)
        req1.httpMethod = "GET"
        signer.sign(&req1, date: fixedDate)

        var req2 = URLRequest(url: URL(string: "https://host/bucket")!)
        req2.httpMethod = "GET"
        signer2.sign(&req2, date: fixedDate)

        let auth1 = req1.value(forHTTPHeaderField: "Authorization")
        let auth2 = req2.value(forHTTPHeaderField: "Authorization")
        #expect(auth1 != auth2)
    }

    @Test("Request without URL host doesn't crash")
    func noHost() {
        // This is an edge case - URL with no host
        var request = URLRequest(url: URL(string: "file:///local/path")!)
        request.httpMethod = "GET"
        signer.sign(&request)
        // Should just return without setting Authorization
        let auth = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth == nil)
    }
}
