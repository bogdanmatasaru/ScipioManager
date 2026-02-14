import Foundation

/// Service for interacting with GCS bucket via S3-compatible XML API.
actor GCSBucketService {
    private let signer: S3Signer
    private let bucketName: String
    private let endpoint: URL
    private let prefix: String
    private let session: URLSession

    init(hmacKey: HMACKey, config: BucketConfig) {
        self.signer = S3Signer(
            accessKeyId: hmacKey.accessKeyId,
            secretAccessKey: hmacKey.secretAccessKey,
            region: config.region
        )
        self.bucketName = config.bucketName
        self.endpoint = URL(string: config.endpoint)!
        self.prefix = config.storagePrefix
        self.session = URLSession(configuration: .default)
    }

    // MARK: - List Objects

    /// List all objects in the bucket under the configured prefix.
    func listObjects(prefix customPrefix: String? = nil) async throws -> [CacheEntry] {
        var allEntries: [CacheEntry] = []
        var continuationToken: String? = nil

        repeat {
            let (entries, nextToken) = try await listObjectsPage(
                prefix: customPrefix ?? prefix,
                continuationToken: continuationToken
            )
            allEntries.append(contentsOf: entries)
            continuationToken = nextToken
        } while continuationToken != nil

        return allEntries
    }

    private func listObjectsPage(
        prefix: String,
        continuationToken: String? = nil
    ) async throws -> ([CacheEntry], String?) {
        // Build the URL with percent-encoded query for proper S3 signing
        var parts = [
            "list-type=2",
            "max-keys=1000",
            "prefix=\(Self.s3Encode(prefix))",
        ]
        if let token = continuationToken {
            parts.append("continuation-token=\(Self.s3Encode(token))")
        }
        let query = parts.sorted().joined(separator: "&")
        let urlString = "\(endpoint.absoluteString)/\(bucketName)?\(query)"
        guard let url = URL(string: urlString) else {
            throw GCSError.listFailed(statusCode: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        signer.sign(&request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GCSError.listFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return parseListResponse(data)
    }

    // MARK: - Delete Object

    /// Delete a single object from the bucket.
    func deleteObject(key: String) async throws {
        let encodedKey = Self.s3EncodePath(key)
        let urlString = "\(endpoint.absoluteString)/\(bucketName)/\(encodedKey)"
        guard let url = URL(string: urlString) else {
            throw GCSError.deleteFailed(key: key, statusCode: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        signer.sign(&request)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GCSError.deleteFailed(
                key: key,
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
    }

    /// Delete multiple objects.
    func deleteObjects(keys: [String]) async throws -> (deleted: Int, failed: Int) {
        var deleted = 0
        var failed = 0
        for key in keys {
            do {
                try await deleteObject(key: key)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        return (deleted, failed)
    }

    /// Delete all entries for a specific framework.
    func deleteFrameworkEntries(frameworkName: String) async throws -> Int {
        let entries = try await listObjects(prefix: "\(prefix)\(frameworkName)/")
        let result = try await deleteObjects(keys: entries.map(\.key))
        return result.deleted
    }

    /// Delete all entries older than a given date.
    func deleteStaleEntries(olderThan date: Date) async throws -> Int {
        let allEntries = try await listObjects()
        let stale = allEntries.filter { $0.lastModified < date }
        let result = try await deleteObjects(keys: stale.map(\.key))
        return result.deleted
    }

    // MARK: - Head Object

    /// Check if an object exists and return its metadata.
    func headObject(key: String) async throws -> (exists: Bool, size: Int64) {
        let encodedKey = Self.s3EncodePath(key)
        let urlString = "\(endpoint.absoluteString)/\(bucketName)/\(encodedKey)"
        guard let url = URL(string: urlString) else { return (false, 0) }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        signer.sign(&request)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return (false, 0)
        }

        if httpResponse.statusCode == 200 {
            let size = Int64(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
            return (true, size)
        }
        return (false, 0)
    }

    // MARK: - Bucket Stats

    func bucketStats() async throws -> BucketStats {
        let entries = try await listObjects()
        let totalSize = entries.reduce(Int64(0)) { $0 + $1.size }
        let grouped = Dictionary(grouping: entries) { $0.frameworkName }
        return BucketStats(
            totalEntries: entries.count,
            totalSize: totalSize,
            frameworkCount: grouped.count,
            entries: entries
        )
    }

    // MARK: - URL Encoding

    /// AWS SigV4-compliant percent encoding for query parameter values.
    private static func s3Encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Percent-encode a path component, preserving `/`.
    private static func s3EncodePath(_ value: String) -> String {
        value.components(separatedBy: "/")
            .map { s3Encode($0) }
            .joined(separator: "/")
    }

    // MARK: - XML Parsing

    private func parseListResponse(_ data: Data) -> ([CacheEntry], String?) {
        let parser = S3ListResponseParser(data: data)
        return (parser.entries, parser.nextContinuationToken)
    }

    // MARK: - Errors

    enum GCSError: Error, LocalizedError {
        case listFailed(statusCode: Int)
        case deleteFailed(key: String, statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .listFailed(let code): return "Failed to list bucket objects (HTTP \(code))"
            case .deleteFailed(let key, let code): return "Failed to delete \(key) (HTTP \(code))"
            }
        }
    }
}

struct BucketStats: Sendable {
    let totalEntries: Int
    let totalSize: Int64
    let frameworkCount: Int
    let entries: [CacheEntry]

    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

// MARK: - S3 XML Response Parser

final class S3ListResponseParser: NSObject, XMLParserDelegate {
    var entries: [CacheEntry] = []
    var nextContinuationToken: String?

    private var currentElement = ""
    private var currentKey = ""
    private var currentSize: Int64 = 0
    private var currentLastModified = Date()
    private var currentETag = ""
    private var textBuffer = ""
    private var inContents = false

    private nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = element
        textBuffer = ""
        if element == "Contents" {
            inContents = true
            currentKey = ""
            currentSize = 0
            currentLastModified = Date()
            currentETag = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if inContents {
            switch element {
            case "Key": currentKey = text
            case "Size": currentSize = Int64(text) ?? 0
            case "LastModified":
                currentLastModified = Self.dateFormatter.date(from: text) ?? Date()
            case "ETag": currentETag = text.replacingOccurrences(of: "\"", with: "")
            case "Contents":
                inContents = false
                entries.append(CacheEntry(
                    key: currentKey,
                    size: currentSize,
                    lastModified: currentLastModified,
                    etag: currentETag
                ))
            default: break
            }
        } else if element == "NextContinuationToken" {
            nextContinuationToken = text
        }
    }
}
