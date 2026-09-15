import Foundation
import Testing
@testable import PhotoPrismSyncCore

private final class UploadExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var uploadedStorage: [String] = []
    private var finalizeCountStorage = 0
    private var cleanedCountStorage = 0

    var uploaded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return uploadedStorage
    }

    var finalizeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return finalizeCountStorage
    }

    var cleanedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cleanedCountStorage
    }

    func recordUpload(_ id: String) {
        lock.lock()
        uploadedStorage.append(id)
        lock.unlock()
    }

    func recordFinalize() {
        lock.lock()
        finalizeCountStorage += 1
        lock.unlock()
    }

    func recordCleanup() {
        lock.lock()
        cleanedCountStorage += 1
        lock.unlock()
    }
}

@Suite struct CriteriaEvaluatorTests {
    @Test func filtersByAgeAndMediaSelection() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldPhoto = AssetDescriptor(
            id: "1",
            source: .local,
            filename: "old.jpg",
            capturedAt: now.addingTimeInterval(-60 * 60 * 24 * 45),
            mediaKind: .photo,
            sizeBytes: 100
        )
        let newVideo = AssetDescriptor(
            id: "2",
            source: .local,
            filename: "new.mov",
            capturedAt: now.addingTimeInterval(-60 * 60 * 24 * 5),
            mediaKind: .video,
            sizeBytes: 200
        )

        let criteria = SyncCriteria(
            ageRule: AgeRule(value: 30, unit: .days),
            mediaSelection: MediaSelection(includePhotos: true, includeLivePhotos: false, includeVideos: false),
            avoidDuplicates: false,
            duplicateCriteria: []
        )

        let result = CriteriaEvaluator.filter(sourceItems: [oldPhoto, newVideo], criteria: criteria, now: now)

        #expect(result == [oldPhoto])
    }

    @Test func excludesDuplicatesWhenAnySelectedCriterionMatches() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let localItems = [
            AssetDescriptor(id: "1", source: .local, filename: "IMG_0001.HEIC", capturedAt: timestamp, mediaKind: .photo, sizeBytes: 100),
            AssetDescriptor(id: "2", source: .local, filename: "IMG_0002.HEIC", capturedAt: timestamp.addingTimeInterval(-10), mediaKind: .photo, sizeBytes: 100),
            AssetDescriptor(id: "3", source: .local, filename: "IMG_0003.HEIC", capturedAt: timestamp.addingTimeInterval(-20), mediaKind: .photo, sizeBytes: 100),
        ]
        let remoteItems = [
            AssetDescriptor(id: "r1", source: .remote, filename: "img_0001.heic", capturedAt: timestamp.addingTimeInterval(-500), mediaKind: .photo, sizeBytes: 100),
            AssetDescriptor(id: "r2", source: .remote, filename: "another.heic", capturedAt: timestamp.addingTimeInterval(-20), mediaKind: .photo, sizeBytes: 100),
        ]
        let criteria = SyncCriteria(
            ageRule: nil,
            mediaSelection: .all,
            avoidDuplicates: true,
            duplicateCriteria: [.filename, .photoTimestamp]
        )

        let result = CriteriaEvaluator.filter(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems, now: timestamp)

        #expect(result.map(\.id) == ["2"])
    }

    @Test func defaultsDuplicateCriteriaToAllSupportedRules() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let localItem = AssetDescriptor(id: "1", source: .local, filename: "dup.jpg", capturedAt: timestamp, mediaKind: .photo, sizeBytes: 100)
        let remoteItem = AssetDescriptor(id: "r1", source: .remote, filename: "dup.jpg", capturedAt: nil, mediaKind: .photo, sizeBytes: 100)
        let criteria = SyncCriteria(ageRule: nil, mediaSelection: .all, avoidDuplicates: true, duplicateCriteria: [])

        let result = CriteriaEvaluator.filter(sourceItems: [localItem], criteria: criteria, duplicateReferenceItems: [remoteItem], now: timestamp)

        #expect(result.isEmpty)
    }

    @Test func matchesRemoteItemsByPhotoPrismOriginalFilename() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let localItem = AssetDescriptor(id: "1", source: .local, filename: "IMG_1234.HEIC", capturedAt: timestamp, mediaKind: .photo, sizeBytes: 100)
        let remoteItem = AssetDescriptor(
            id: "r1",
            source: .remote,
            filename: "2023-01-02-030405-abcdef.heic",
            originalFilename: "img_1234.heic",
            capturedAt: nil,
            mediaKind: .photo,
            sizeBytes: 100
        )
        let criteria = SyncCriteria(ageRule: nil, mediaSelection: .all, avoidDuplicates: true, duplicateCriteria: [.filename])

        let result = CriteriaEvaluator.filter(sourceItems: [localItem], criteria: criteria, duplicateReferenceItems: [remoteItem], now: timestamp)

        #expect(result.isEmpty)
    }

    @Test func matchesByChecksumRegardlessOfFilenameOrTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let localItem = AssetDescriptor(
            id: "1",
            source: .local,
            filename: "IMG_1234.HEIC",
            capturedAt: timestamp,
            mediaKind: .photo,
            sizeBytes: 100,
            checksum: "ABCDEF0123456789"
        )
        let remoteItem = AssetDescriptor(
            id: "r1",
            source: .remote,
            filename: "2023-01-02-030405-abcdef.heic",
            capturedAt: timestamp.addingTimeInterval(-9999),
            mediaKind: .photo,
            sizeBytes: 100,
            checksum: "abcdef0123456789"
        )
        let criteria = SyncCriteria(ageRule: nil, mediaSelection: .all, avoidDuplicates: true, duplicateCriteria: [.checksum])

        let result = CriteriaEvaluator.filter(sourceItems: [localItem], criteria: criteria, duplicateReferenceItems: [remoteItem], now: timestamp)

        #expect(result.isEmpty)
    }

    @Test func checksumCriterionNeverMatchesWhenChecksumIsMissing() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let localItem = AssetDescriptor(id: "1", source: .local, filename: "same-name.heic", capturedAt: timestamp, mediaKind: .photo, sizeBytes: 100)
        let remoteItem = AssetDescriptor(id: "r1", source: .remote, filename: "same-name.heic", capturedAt: timestamp, mediaKind: .photo, sizeBytes: 100)
        let criteria = SyncCriteria(ageRule: nil, mediaSelection: .all, avoidDuplicates: true, duplicateCriteria: [.checksum])

        let result = CriteriaEvaluator.filter(sourceItems: [localItem], criteria: criteria, duplicateReferenceItems: [remoteItem], now: timestamp)

        #expect(result.map(\.id) == ["1"])
    }

    @Test func matchingDuplicatesReturnsOnlyItemsPresentInReferenceSet() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let localItems = [
            AssetDescriptor(id: "1", source: .local, filename: "keep.heic", capturedAt: timestamp, mediaKind: .photo, sizeBytes: 100),
            AssetDescriptor(id: "2", source: .local, filename: "delete.heic", capturedAt: timestamp.addingTimeInterval(-60), mediaKind: .photo, sizeBytes: 100),
        ]
        let remoteItems = [
            AssetDescriptor(id: "r1", source: .remote, filename: "delete.heic", capturedAt: timestamp.addingTimeInterval(-600), mediaKind: .photo, sizeBytes: 100),
        ]
        let criteria = SyncCriteria(ageRule: nil, mediaSelection: .all, avoidDuplicates: true, duplicateCriteria: [.filename])

        let result = CriteriaEvaluator.matchingDuplicates(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems, now: timestamp)

        #expect(result.map(\.id) == ["2"])
    }

    @Test func matchingDuplicatesFallsBackToAllRulesWhenDuplicateOptionsAreImplicit() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let localItems = [
            AssetDescriptor(id: "1", source: .local, filename: "same-name.heic", capturedAt: timestamp, mediaKind: .photo, sizeBytes: 100),
        ]
        let remoteItems = [
            AssetDescriptor(id: "r1", source: .remote, filename: "same-name.heic", capturedAt: nil, mediaKind: .photo, sizeBytes: 100),
        ]
        let criteria = SyncCriteria(ageRule: nil, mediaSelection: .all, avoidDuplicates: false, duplicateCriteria: [])

        let result = CriteriaEvaluator.matchingDuplicates(sourceItems: localItems, criteria: criteria, duplicateReferenceItems: remoteItems, now: timestamp)

        #expect(result.map(\.id) == ["1"])
    }

    @Test func uploadExecutionCoordinatorReportsFinalizationFailureWithUploadedCount() async throws {
        struct SampleError: Error {}

        let item = AssetDescriptor(id: "1", source: .local, filename: "item.heic", capturedAt: nil, mediaKind: .photo, sizeBytes: 10)

        do {
            try await UploadExecutionCoordinator.execute(
                items: [item],
                exportResources: { _ in [URL(fileURLWithPath: "/tmp/item.heic")] },
                uploadResources: { _, _ in },
                finalize: { throw SampleError() }
            )
            Issue.record("Expected finalization failure")
        } catch let error as UploadExecutionCoordinatorError {
            if case let .finalizationFailed(uploadedCount, underlyingError) = error {
                #expect(uploadedCount == 1)
                #expect(underlyingError is SampleError)
            } else {
                Issue.record("Unexpected upload execution error")
            }
        }
    }

    @Test func uploadExecutionCoordinatorFinalizesOnlyWhenItemsExist() async throws {
        let item = AssetDescriptor(id: "1", source: .local, filename: "item.heic", capturedAt: nil, mediaKind: .photo, sizeBytes: 10)
        let recorder = UploadExecutionRecorder()

        try await UploadExecutionCoordinator.execute(
            items: [item],
            exportResources: { _ in [URL(fileURLWithPath: "/tmp/item.heic")] },
            uploadResources: { asset, _ in recorder.recordUpload(asset.id) },
            finalize: { recorder.recordFinalize() },
            cleanup: { _ in recorder.recordCleanup() }
        )

        #expect(recorder.uploaded == ["1"])
        #expect(recorder.finalizeCount == 1)
        #expect(recorder.cleanedCount == 1)

        let emptyRecorder = UploadExecutionRecorder()

        try await UploadExecutionCoordinator.execute(
            items: [],
            exportResources: { _ in [URL(fileURLWithPath: "/tmp/item.heic")] },
            uploadResources: { asset, _ in emptyRecorder.recordUpload(asset.id) },
            finalize: { emptyRecorder.recordFinalize() },
            cleanup: { _ in emptyRecorder.recordCleanup() }
        )

        #expect(emptyRecorder.uploaded.isEmpty)
        #expect(emptyRecorder.finalizeCount == 0)
        #expect(emptyRecorder.cleanedCount == 0)
    }
}
