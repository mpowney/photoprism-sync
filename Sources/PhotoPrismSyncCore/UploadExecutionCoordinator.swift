import Foundation

public enum UploadExecutionCoordinator {
    public static func execute(
        items: [AssetDescriptor],
        exportResources: @Sendable (AssetDescriptor) async throws -> [URL],
        uploadResources: @Sendable (AssetDescriptor, [URL]) async throws -> Void,
        finalize: @Sendable () async throws -> Void,
        cleanup: @Sendable ([URL]) async -> Void = { _ in }
    ) async throws {
        for item in items {
            let fileURLs = try await exportResources(item)
            do {
                try await uploadResources(item, fileURLs)
            } catch {
                await cleanup(fileURLs)
                throw error
            }
            await cleanup(fileURLs)
        }

        if !items.isEmpty {
            try await finalize()
        }
    }
}
