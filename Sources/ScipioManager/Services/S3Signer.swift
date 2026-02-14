import Foundation
import CryptoKit

/// AWS Signature V4 signer for S3-compatible APIs (GCS with HMAC keys).
struct S3Signer: Sendable {
    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let service: String = "s3"

    /// Sign a URLRequest with AWS Signature V4.
    func sign(_ request: inout URLRequest, date: Date = Date()) {
        guard let url = request.url,
              let host = url.host else { return }

        let method = request.httpMethod ?? "GET"
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone, .withDashSeparatorInDate]
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let amzDate = amzDateString(date)
        let dateStamp = dateStampString(date)
        let payloadHash = sha256Hex(request.httpBody ?? Data())

        // Set required headers
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        // Canonical headers (sorted)
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)",
        ].joined(separator: "\n") + "\n"

        // Canonical URI and query
        let canonicalURI = url.path.isEmpty ? "/" : url.path
        let canonicalQueryString = Self.canonicalQueryString(from: url)

        // Canonical request
        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        // String to sign
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(canonicalRequest.data(using: .utf8)!),
        ].joined(separator: "\n")

        // Signing key derivation
        let signingKey = deriveSigningKey(dateStamp: dateStamp)

        // Signature
        let signature = hmacSHA256(key: signingKey, data: stringToSign.data(using: .utf8)!).hexString

        // Authorization header
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Private

    /// Build the canonical query string per AWS SigV4 spec.
    /// Reads the raw percent-encoded query from the URL, splits, sorts, and joins.
    /// The caller is responsible for pre-encoding values with s3Encode().
    private static func canonicalQueryString(from url: URL) -> String {
        // Use the raw query string which should already be percent-encoded
        guard let rawQuery = url.query, !rawQuery.isEmpty else {
            return ""
        }
        return rawQuery
            .split(separator: "&")
            .sorted()
            .joined(separator: "&")
    }

    private func deriveSigningKey(dateStamp: String) -> SymmetricKey {
        let kDate = hmacSHA256(
            key: SymmetricKey(data: "AWS4\(secretAccessKey)".data(using: .utf8)!),
            data: dateStamp.data(using: .utf8)!
        )
        let kRegion = hmacSHA256(key: kDate, data: region.data(using: .utf8)!)
        let kService = hmacSHA256(key: kRegion, data: service.data(using: .utf8)!)
        return hmacSHA256(key: kService, data: "aws4_request".data(using: .utf8)!)
    }

    private func hmacSHA256(key: SymmetricKey, data: Data) -> SymmetricKey {
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return SymmetricKey(data: Data(signature))
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    private func amzDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private func dateStampString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

// MARK: - Extensions

extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension SymmetricKey {
    var hexString: String {
        withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }
}
