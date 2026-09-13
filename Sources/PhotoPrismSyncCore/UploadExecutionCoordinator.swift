import Foundation

public enum UploadExecutionCoordinatorError: LocalizedError {
    case finalizationFailed(uploadedCount: Int, underlyingError: Error)

    public var errorDescription: String? {
        switch self {
        case let .finalizationFailed(uploadedCount, underlyingError):
            return "Uploaded \(uploadedCount) item(s), but PhotoPrism finalization failed: \(underlyingError.localizedDescription)"
        }
    }
}

public enum UploadExecutionCoordinator {
    public static func execute(
        items: [AssetDescriptor],
        exportResources: @Sendable (AssetDescriptor) async throws -> [URL],
        uploadResources: @Sendable (AssetDescriptor, [URL]) async throws -> Void,
        finalize: @Sendable () async throws -> Void,
        cleanup: @Sendable ([URL]) async -> Void = { _ in }
    ) async throws {
        var uploadedCount = 0

        for item in items {
            let fileURLs = try await exportResources(item)
            do {
                try await uploadResources(item, fileURLs)
            } catch {
                await cleanup(fileURLs)
                throw error
            }
            await cleanup(fileURLs)
            uploadedCount += 1
        }

        if !items.isEmpty {
            do {
                try await finalize()
            } catch {
                throw UploadExecutionCoordinatorError.finalizationFailed(uploadedCount: uploadedCount, underlyingError: error)
            }
        }
    }
}
