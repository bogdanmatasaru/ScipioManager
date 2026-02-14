import Foundation

/// HMAC key pair for GCS S3-compatible API authentication.
struct HMACKey: Codable, Sendable {
    let accessKeyId: String
    let secretAccessKey: String
}

/// Loads HMAC credentials from JSON file or environment variables.
struct HMACKeyLoader: Sendable {

    enum LoadError: Error, LocalizedError {
        case noCredentials(searchedPath: String)
        case invalidJSON(path: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noCredentials(let path):
                return "No HMAC credentials found. Searched: \(path) and environment variables SCIPIO_GCS_HMAC_ACCESS_KEY / SCIPIO_GCS_HMAC_SECRET_KEY"
            case .invalidJSON(let path, let err):
                return "Failed to parse HMAC key file at \(path): \(err.localizedDescription)"
            }
        }
    }

    /// Load HMAC keys with priority: environment variables > JSON file.
    static func load(from filePath: URL) throws -> HMACKey {
        // Priority 1: Environment variables
        if let access = ProcessInfo.processInfo.environment["SCIPIO_GCS_HMAC_ACCESS_KEY"],
           let secret = ProcessInfo.processInfo.environment["SCIPIO_GCS_HMAC_SECRET_KEY"],
           !access.isEmpty, !secret.isEmpty {
            return HMACKey(accessKeyId: access, secretAccessKey: secret)
        }

        // Priority 2: JSON file
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw LoadError.noCredentials(searchedPath: filePath.path)
        }

        do {
            let data = try Data(contentsOf: filePath)
            return try JSONDecoder().decode(HMACKey.self, from: data)
        } catch let error as DecodingError {
            throw LoadError.invalidJSON(path: filePath.path, underlying: error)
        }
    }

    /// Check if credentials are available without loading them.
    static func credentialsAvailable(at filePath: URL) -> CredentialSource {
        if let access = ProcessInfo.processInfo.environment["SCIPIO_GCS_HMAC_ACCESS_KEY"],
           let secret = ProcessInfo.processInfo.environment["SCIPIO_GCS_HMAC_SECRET_KEY"],
           !access.isEmpty, !secret.isEmpty {
            return .environmentVariables
        }
        if FileManager.default.fileExists(atPath: filePath.path) {
            return .jsonFile
        }
        return .none
    }

    enum CredentialSource: String, Sendable {
        case environmentVariables = "Environment Variables"
        case jsonFile = "JSON File (gcs-hmac.json)"
        case none = "Not Found"
    }
}
