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

    @Published var settings: PhotoPrismServerSettings
    @Published var selectedAction: PrimaryAction = .upload
    @Published var deleteMode: DeleteMode = .foundInPhotoPrism
    @Published var criteria = SyncCriteria()
    @Published var calculationSnapshot: CalculationSnapshot?
    @Published var isCalculating = false
    @Published var isExecuting = false
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
        do {
            try await photoPrismClient.validateConnection(using: settings)
            noticeMessage = "Successfully signed in to PhotoPrism."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invalidateCalculation() {
        calculationSnapshot = nil
        completedItems = 0
        totalItems = 0
        progressMessage = ""
    }

    func calculateSelection() async {
        guard !isCalculating, !isExecuting else { return }
        guard validateConfigurationIfNeeded() else { return }

        isCalculating = true
        progressMessage = "Calculating matching items…"
        defer { isCalculating = false }

        do {
            let criteria = effectiveCriteria
            let snapshot: CalculationSnapshot

            switch currentAction {
            case .upload:
                let localItems = try await photoLibrary.fetchLibraryItems()
                let remoteItems = criteria.avoidDuplicates ? try await photoPrismClient.fetchLibraryItems(using: settings) : []
                let matching = CriteriaEvaluator.filter(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems)
                snapshot = CalculationSnapshot(action: .upload, criteria: criteria, items: sorted(matching))
            case .download:
                let remoteItems = try await photoPrismClient.fetchLibraryItems(using: settings)
                let localItems = criteria.avoidDuplicates ? try await photoLibrary.fetchLibraryItems() : []
                let matching = CriteriaEvaluator.filter(sourceItems: remoteItems, criteria: criteria, duplicateReferenceItems: localItems)
                snapshot = CalculationSnapshot(action: .download, criteria: criteria, items: sorted(matching))
            case .deleteFoundInPhotoPrism:
                let localItems = try await photoLibrary.fetchLibraryItems()
                let remoteItems = try await photoPrismClient.fetchLibraryItems(using: settings)
                let matching = CriteriaEvaluator.matchingDuplicates(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems)
                snapshot = CalculationSnapshot(action: .deleteFoundInPhotoPrism, criteria: criteria, items: sorted(matching))
            case .deleteOlderThan:
                let localItems = try await photoLibrary.fetchLibraryItems()
                let remoteItems = criteria.avoidDuplicates ? try await photoPrismClient.fetchLibraryItems(using: settings) : []
                let matching = CriteriaEvaluator.filter(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems)
                snapshot = CalculationSnapshot(action: .deleteOlderThan, criteria: criteria, items: sorted(matching))
            }

            calculationSnapshot = snapshot
            totalItems = snapshot.summary.itemCount
            completedItems = 0
            progressMessage = snapshot.summary.itemCount == 0 ? "No matching items found." : "Calculated \(snapshot.summary.itemCount) matching items."
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
                progressMessage = "Uploading \(item.filename)…"
                return try await photoLibrary.exportOriginalResources(forLocalIdentifier: item.id)
            },
            uploadResources: { item, fileURLs in
                try await photoPrismClient.uploadOriginals(
                    fileURLs: fileURLs,
                    userUID: sessionInfo.userUID,
                    uploadToken: uploadToken,
                    using: settings
                )
                completedItems += 1
            },
            finalize: {
                progressMessage = "Finalizing PhotoPrism import…"
                try await photoPrismClient.processUploadedOriginals(userUID: sessionInfo.userUID, uploadToken: uploadToken, using: settings)
            },
            cleanup: { fileURLs in
                cleanupTemporaryFiles(fileURLs)
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

    private func cleanupTemporaryFiles(_ fileURLs: [URL]) {
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
