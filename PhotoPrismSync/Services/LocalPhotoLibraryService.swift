import Foundation
import Photos
import UIKit

final class LocalPhotoLibraryService: @unchecked Sendable {
    static let shared = LocalPhotoLibraryService()

    private let imageManager = PHCachingImageManager()

    func requestAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard newStatus == .authorized || newStatus == .limited else {
                throw PhotoLibraryError.accessDenied
            }
        default:
            throw PhotoLibraryError.accessDenied
        }
    }

    func fetchLibraryItems(needsChecksum: Bool = false) async throws -> [AssetDescriptor] {
        try await requestAccess()

        let fetchResult = PHAsset.fetchAssets(with: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        var items: [AssetDescriptor] = []
        items.reserveCapacity(assets.count)
        for asset in assets {
            items.append(await descriptor(for: asset, needsChecksum: needsChecksum))
        }

        return items
    }

    func requestThumbnail(for localIdentifier: String, targetSize: CGSize) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            var didResume = false
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error

                guard !didResume else { return }

                if let image, !isDegraded {
                    didResume = true
                    continuation.resume(returning: image)
                } else if error != nil || isCancelled || !isDegraded {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func exportOriginalResources(forLocalIdentifier localIdentifier: String) async throws -> [URL] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw PhotoLibraryError.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else {
            throw PhotoLibraryError.assetNotFound
        }

        var fileURLs: [URL] = []
        for resource in resources where shouldExport(resource: resource) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(resource.originalFilename)

            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try await write(resource: resource, to: url)
            fileURLs.append(url)
        }

        return fileURLs
    }

    func deleteAssets(localIdentifiers: [String]) async throws {
        try await requestAccess()

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard fetchResult.count > 0 else { return }

        try await performPhotoLibraryChanges {
            PHAssetChangeRequest.deleteAssets(fetchResult)
        }
    }

    func saveDownloadedAsset(data: Data, filename: String, capturedAt: Date?, mediaKind: MediaKind) async throws {
        try await requestAddOnlyAccess()

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDirectory.appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        try await performPhotoLibraryChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            creationRequest.creationDate = capturedAt
            creationRequest.addResource(with: self.resourceType(for: mediaKind, filename: filename), fileURL: fileURL, options: options)
        }
    }

    private func requestAddOnlyAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                throw PhotoLibraryError.accessDenied
            }
        default:
            throw PhotoLibraryError.accessDenied
        }
    }

    private func descriptor(for asset: PHAsset, needsChecksum: Bool = false) async -> AssetDescriptor {
        let resources = PHAssetResource.assetResources(for: asset)
        let primaryResource = resources.first(where: { $0.type == .fullSizePhoto || $0.type == .photo || $0.type == .video || $0.type == .pairedVideo }) ?? resources.first
        let filename = primaryResource?.originalFilename ?? asset.localIdentifier
        let size = resources.reduce(into: Int64(0)) { partialResult, resource in
            partialResult += Int64((resource.value(forKey: "fileSize") as? CLong) ?? 0)
        }

        var checksums: Set<String> = []
        if needsChecksum, let primaryResource,
           let checksum = try? await LocalChecksumCache.shared.checksum(for: asset, resource: primaryResource)
        {
            checksums = [checksum]
        }

        return AssetDescriptor(
            id: asset.localIdentifier,
            source: .local,
            filename: filename,
            capturedAt: asset.creationDate,
            mediaKind: mediaKind(for: asset),
            sizeBytes: size,
            checksums: checksums
        )
    }

    private func mediaKind(for asset: PHAsset) -> MediaKind {
        if asset.mediaType == .video {
            return .video
        }
        if asset.mediaSubtypes.contains(.photoLive) {
            return .livePhoto
        }
        return .photo
    }

    private func resourceType(for mediaKind: MediaKind, filename: String) -> PHAssetResourceType {
        switch mediaKind {
        case .video:
            return .video
        case .livePhoto:
            return filename.lowercased().hasSuffix(".mov") ? .video : .photo
        case .photo:
            return .photo
        }
    }

    private func shouldExport(resource: PHAssetResource) -> Bool {
        switch resource.type {
        case .photo, .fullSizePhoto, .video, .fullSizeVideo, .pairedVideo:
            return true
        default:
            return false
        }
    }

    private func write(resource: PHAssetResource, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: nil) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func performPhotoLibraryChanges(_ changeBlock: @escaping @Sendable () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changeBlock) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibraryError.unknown)
                }
            }
        }
    }
}

enum PhotoLibraryError: LocalizedError {
    case accessDenied
    case assetNotFound
    case unknown

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photo library access is required."
        case .assetNotFound:
            return "A selected photo could not be loaded."
        case .unknown:
            return "The photo library operation failed."
        }
    }
}
