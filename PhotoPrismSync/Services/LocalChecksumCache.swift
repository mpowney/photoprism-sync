import CryptoKit
import Foundation
import Photos

/// Computes and persists SHA1 checksums for local photo library assets so they match PhotoPrism's file `Hash`.
actor LocalChecksumCache {
    static let shared = LocalChecksumCache()

    private struct Entry: Codable {
        let modifiedAt: Date
        let sha1: String
    }

    private var entries: [String: Entry]
    private let storeURL: URL

    init(storeURL: URL = LocalChecksumCache.defaultStoreURL()) {
        self.storeURL = storeURL
        entries = LocalChecksumCache.load(from: storeURL)
    }

    /// Returns the cached SHA1 for `asset` if the asset hasn't changed since it was last hashed, otherwise computes and caches it.
    func checksum(for asset: PHAsset, resource: PHAssetResource) async throws -> String {
        let key = asset.localIdentifier
        let modifiedAt = asset.modificationDate ?? asset.creationDate ?? .distantPast

        if let cached = entries[key], cached.modifiedAt == modifiedAt {
            return cached.sha1
        }

        let sha1 = try await computeSHA1(for: resource)
        entries[key] = Entry(modifiedAt: modifiedAt, sha1: sha1)
        persist()
        return sha1
    }

    private func computeSHA1(for resource: PHAssetResource) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var hasher = Insecure.SHA1()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                hasher.update(data: chunk)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let digest = hasher.finalize()
                    continuation.resume(returning: digest.map { String(format: "%02x", $0) }.joined())
                }
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func load(from storeURL: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func defaultStoreURL() -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cachesDirectory.appendingPathComponent("LocalChecksumCache.json")
    }
}
