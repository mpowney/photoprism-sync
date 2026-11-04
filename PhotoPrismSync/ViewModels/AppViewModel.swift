import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    enum PrimaryAction: String, CaseIterable, Identifiable {
        case upload
        case download
        case delete

        var id: String { rawValue }

        var title: String {
            switch self {
            case .upload: "Upload"
            case .download: "Download"
            case .delete: "Delete"
            }
        }
    }

    enum DeleteMode: String, CaseIterable, Identifiable {
        case foundInPhotoPrism
        case olderThan

        var id: String { rawValue }

        var title: String {
            switch self {
            case .foundInPhotoPrism: "Delete photos found in PhotoPrism"
            case .olderThan: "Delete photos older than…"
            }
        }
    }

    enum ConnectionStatus: Equatable {
        case testing
        case success(String)
        case failure(String)
    }

    @Published var settings: PhotoPrismServerSettings
    @Published var selectedAction: PrimaryAction = .upload
    @Published var deleteMode: DeleteMode = .foundInPhotoPrism
    @Published var criteria = SyncCriteria()
    @Published var calculationSnapshot: CalculationSnapshot?
    @Published var isCalculating = false
    @Published var isExecuting = false
    @Published var isTestingConnection = false
    @Published var connectionStatus: ConnectionStatus?
    @Published var progressMessage = ""
    @Published var completedItems = 0
    @Published var totalItems = 0
    @Published var noticeMessage = ""
    @Published var errorMessage: String?
    @Published var isShowingPreview = false

    private let settingsStore: AppSettingsStore
    private let photoPrismClient: PhotoPrismClient
    private let photoLibrary: LocalPhotoLibraryService

    init(
        settingsStore: AppSettingsStore = .shared,
        photoPrismClient: PhotoPrismClient = .shared,
        photoLibrary: LocalPhotoLibraryService = .shared
    ) {
        self.settingsStore = settingsStore
        self.photoPrismClient = photoPrismClient
        self.photoLibrary = photoLibrary
        settings = settingsStore.load()
    }

    var currentAction: SyncAction {
        switch selectedAction {
        case .upload: .upload
        case .download: .download
        case .delete: deleteMode == .foundInPhotoPrism ? .deleteFoundInPhotoPrism : .deleteOlderThan
        }
    }

    var executeButtonTitle: String {
        switch currentAction {
        case .upload: "Upload photos"
        case .download: "Download photos"
        case .deleteFoundInPhotoPrism, .deleteOlderThan: "Delete photos"
        }
    }

    var requiresServerConfiguration: Bool {
        switch currentAction {
        case .upload, .download, .deleteFoundInPhotoPrism:
            true
        case .deleteOlderThan:
            effectiveCriteria.avoidDuplicates
        }
    }

    var previewItems: [AssetDescriptor] {
        calculationSnapshot?.items ?? []
    }

    var effectiveCriteria: SyncCriteria {
        var working = criteria

        switch currentAction {
        case .deleteFoundInPhotoPrism:
            working.ageRule = nil
            working.avoidDuplicates = true
            if working.duplicateCriteria.isEmpty {
                working.duplicateCriteria = Set(DuplicateCriterion.allCases)
            }
        case .upload, .download, .deleteOlderThan:
            break
        }

        if !working.mediaSelection.includePhotos,
           !working.mediaSelection.includeLivePhotos,
           !working.mediaSelection.includeVideos
        {
            working.mediaSelection = .all
        }

        return working
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            noticeMessage = "PhotoPrism settings saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        guard !isTestingConnection else { return }
        isTestingConnection = true
        connectionStatus = .testing
        defer { isTestingConnection = false }

        do {
            try await photoPrismClient.validateConnection(using: settings)
            let message = "Successfully signed in to PhotoPrism."
            connectionStatus = .success(message)
            noticeMessage = message
        } catch {
            let message = error.localizedDescription
            connectionStatus = .failure(message)
            errorMessage = message
        }
    }

    func invalidateCalculation() {
        calculationSnapshot = nil
        completedItems = 0
        totalItems = 0
        progressMessage = ""
        connectionStatus = nil
    }

    func calculateSelection() async {
        guard !isCalculating, !isExecuting else { return }
        guard validateConfigurationIfNeeded() else { return }

        isCalculating = true
        progressMessage = "Calculating matching items…"
        defer { isCalculating = false }

        do {
            let criteria = effectiveCriteria
            let needsChecksum = criteria.effectiveDuplicateCriteria.contains(.checksum)
            let snapshot: CalculationSnapshot
            var remoteFetchDiagnostics: LibraryFetchResult?
            var duplicateCount = 0

            switch currentAction {
            case .upload:
                let localItems = try await photoLibrary.fetchLibraryItems(needsChecksum: needsChecksum)
                let remoteItems = criteria.avoidDuplicates ? try await photoPrismClient.fetchLibraryItems(using: settings) : []
                duplicateCount = CriteriaEvaluator.matchingDuplicates(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems).count
                let matching = CriteriaEvaluator.filter(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems)
                snapshot = CalculationSnapshot(action: .upload, criteria: criteria, items: sorted(matching))
            case .download:
                let fetchResult = try await photoPrismClient.fetchLibraryItemsWithDiagnostics(using: settings) { [weak self] pageCount, rawDecodedCount in
                    Task { @MainActor in
                        self?.progressMessage = "Fetching from server… \(rawDecodedCount) found across \(pageCount) page(s)…"
                    }
                }
                remoteFetchDiagnostics = fetchResult
                let localItems = criteria.avoidDuplicates ? try await photoLibrary.fetchLibraryItems(needsChecksum: needsChecksum) : []
                duplicateCount = CriteriaEvaluator.matchingDuplicates(sourceItems: fetchResult.items, criteria: criteria, duplicateReferenceItems: localItems).count
                let matching = CriteriaEvaluator.filter(sourceItems: fetchResult.items, criteria: criteria, duplicateReferenceItems: localItems)
                snapshot = CalculationSnapshot(action: .download, criteria: criteria, items: sorted(matching))
            case .deleteFoundInPhotoPrism:
                let localItems = try await photoLibrary.fetchLibraryItems(needsChecksum: needsChecksum)
                let remoteItems = try await photoPrismClient.fetchLibraryItems(using: settings)
                let matching = CriteriaEvaluator.matchingDuplicates(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems)
                snapshot = CalculationSnapshot(action: .deleteFoundInPhotoPrism, criteria: criteria, items: sorted(matching))
            case .deleteOlderThan:
                let localItems = try await photoLibrary.fetchLibraryItems(needsChecksum: needsChecksum)
                let remoteItems = criteria.avoidDuplicates ? try await photoPrismClient.fetchLibraryItems(using: settings) : []
                let matching = CriteriaEvaluator.filter(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems)
                snapshot = CalculationSnapshot(action: .deleteOlderThan, criteria: criteria, items: sorted(matching))
            }

            calculationSnapshot = snapshot
            totalItems = snapshot.summary.itemCount
            completedItems = 0
            if let fetchResult = remoteFetchDiagnostics {
                let dropNote = fetchResult.droppedCount > 0 ? ", \(fetchResult.droppedCount) skipped (missing ID/hash)" : ""
                let duplicateNote = criteria.avoidDuplicates ? " There are \(duplicateCount) duplicates that will not be downloaded." : ""
                progressMessage = "Fetched \(fetchResult.rawDecodedCount) from server across \(fetchResult.pageCount) page(s)\(dropNote); \(snapshot.summary.itemCount) match your criteria.\(duplicateNote)"
            } else if snapshot.action == .upload {
                progressMessage = "Calculated \(snapshot.summary.itemCount) matching items. There are \(duplicateCount) duplicates that will not be uploaded."
            } else if snapshot.action == .deleteFoundInPhotoPrism || snapshot.action == .deleteOlderThan {
                progressMessage = "Calculated \(snapshot.summary.itemCount) matching items that will be deleted from your iPhone."
            } else {
                progressMessage = snapshot.summary.itemCount == 0 ? "No matching items found." : "Calculated \(snapshot.summary.itemCount) matching items."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func executeCalculatedSelection() async {
        guard !isCalculating, !isExecuting else { return }
        guard let snapshot = calculationSnapshot else { return }
        guard validateConfigurationIfNeeded() else { return }

        isExecuting = true
        totalItems = snapshot.items.count
        completedItems = 0
        progressMessage = "Preparing…"
        defer { isExecuting = false }

        do {
            switch snapshot.action {
            case .upload:
                try await executeUpload(snapshot)
            case .download:
                try await executeDownload(snapshot)
            case .deleteFoundInPhotoPrism, .deleteOlderThan:
                try await executeDelete(snapshot)
            }

            noticeMessage = successMessage(for: snapshot.action, count: snapshot.items.count)
            progressMessage = noticeMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func formattedSize(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func executeUpload(_ snapshot: CalculationSnapshot) async throws {
        let uploadToken = UUID().uuidString
        let sessionInfo = try await photoPrismClient.sessionInfo(using: settings)

        try await UploadExecutionCoordinator.execute(
            items: snapshot.items,
            exportResources: { item in
                await MainActor.run { self.progressMessage = "Uploading \(item.filename)…" }
                return try await self.photoLibrary.exportOriginalResources(forLocalIdentifier: item.id)
            },
            uploadResources: { item, fileURLs in
                try await self.photoPrismClient.uploadOriginals(
                    fileURLs: fileURLs,
                    userUID: sessionInfo.userUID,
                    uploadToken: uploadToken,
                    using: settings
                )
                await MainActor.run { self.completedItems += 1 }
            },
            finalize: {
                await MainActor.run { self.progressMessage = "Finalizing PhotoPrism import…" }
                try await self.photoPrismClient.processUploadedOriginals(userUID: sessionInfo.userUID, uploadToken: uploadToken, using: settings)
            },
            cleanup: { fileURLs in
                self.cleanupTemporaryFiles(fileURLs)
            }
        )
    }

    private func executeDownload(_ snapshot: CalculationSnapshot) async throws {
        for item in snapshot.items {
            progressMessage = "Downloading \(item.filename)…"
            let data = try await photoPrismClient.downloadOriginal(for: item, using: settings)
            try await photoLibrary.saveDownloadedAsset(data: data, filename: item.filename, capturedAt: item.capturedAt, mediaKind: importMediaKind(forDownloadedItem: item))
            completedItems += 1
        }
    }

    private func executeDelete(_ snapshot: CalculationSnapshot) async throws {
        progressMessage = "Deleting photos from the device…"
        try await photoLibrary.deleteAssets(localIdentifiers: snapshot.items.map(\.id))
        completedItems = snapshot.items.count
    }

    private func validateConfigurationIfNeeded() -> Bool {
        let trimmedURL = settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresServerConfiguration || !trimmedURL.isEmpty {
            guard !trimmedURL.isEmpty else {
                if currentAction == .deleteOlderThan && effectiveCriteria.avoidDuplicates {
                    errorMessage = "Configure PhotoPrism credentials to compare delete candidates against remote duplicates."
                } else {
                    errorMessage = "Enter the PhotoPrism URL, username, and password first."
                }
                return false
            }

            guard settings.normalizedBaseURL != nil else {
                errorMessage = "Enter a valid PhotoPrism server URL."
                return false
            }
        }

        guard !requiresServerConfiguration || settings.isComplete else {
            if currentAction == .deleteOlderThan && effectiveCriteria.avoidDuplicates {
                errorMessage = "Configure PhotoPrism credentials to compare delete candidates against remote duplicates."
            } else {
                errorMessage = "Enter the PhotoPrism URL, username, and password first."
            }
            return false
        }
        return true
    }

    private func sorted(_ items: [AssetDescriptor]) -> [AssetDescriptor] {
        items.sorted {
            switch ($0.capturedAt, $1.capturedAt) {
            case let (lhs?, rhs?):
                if lhs != rhs { return lhs < rhs }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
        }
    }

    private func importMediaKind(forDownloadedItem item: AssetDescriptor) -> MediaKind {
        guard item.mediaKind == .livePhoto else { return item.mediaKind }
        let videoExtensions = ["mov", "mp4", "m4v"]
        let fileExtension = URL(fileURLWithPath: item.filename).pathExtension.lowercased()
        return videoExtensions.contains(fileExtension) ? .video : .photo
    }

    nonisolated private func cleanupTemporaryFiles(_ fileURLs: [URL]) {
        let directories = Set(fileURLs.map { $0.deletingLastPathComponent() })
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func successMessage(for action: SyncAction, count: Int) -> String {
        switch action {
        case .upload: "Uploaded \(count) photos to PhotoPrism."
        case .download: "Downloaded \(count) photos to the device."
        case .deleteFoundInPhotoPrism, .deleteOlderThan: "Deleted \(count) photos from the device."
        }
    }
}
