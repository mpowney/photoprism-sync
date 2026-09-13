import Foundation
import Testing
@testable import PhotoPrismSyncCore

private actor UploadExecutionRecorder {
    private(set) var uploaded: [String] = []
    private(set) var finalizeCount = 0
    private(set) var cleanedCount = 0

    func recordUpload(_ id: String) {
        uploaded.append(id)
    }

    func recordFinalize() {
        finalizeCount += 1
    }

    func recordCleanup() {
        cleanedCount += 1
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

    @Test func uploadExecutionCoordinatorFinalizesOnlyWhenItemsExist() async throws {
        let item = AssetDescriptor(id: "1", source: .local, filename: "item.heic", capturedAt: nil, mediaKind: .photo, sizeBytes: 10)
        let recorder = UploadExecutionRecorder()

        try await UploadExecutionCoordinator.execute(
            items: [item],
            exportResources: { _ in [URL(fileURLWithPath: "/tmp/item.heic")] },
            uploadResources: { asset, _ in await recorder.recordUpload(asset.id) },
            finalize: { await recorder.recordFinalize() },
            cleanup: { _ in await recorder.recordCleanup() }
        )

        #expect(await recorder.uploaded == ["1"])
        #expect(await recorder.finalizeCount == 1)
        #expect(await recorder.cleanedCount == 1)

        let emptyRecorder = UploadExecutionRecorder()

        try await UploadExecutionCoordinator.execute(
            items: [],
            exportResources: { _ in [URL(fileURLWithPath: "/tmp/item.heic")] },
            uploadResources: { asset, _ in await emptyRecorder.recordUpload(asset.id) },
            finalize: { await emptyRecorder.recordFinalize() },
            cleanup: { _ in await emptyRecorder.recordCleanup() }
        )

        #expect(await emptyRecorder.uploaded.isEmpty)
        #expect(await emptyRecorder.finalizeCount == 0)
        #expect(await emptyRecorder.cleanedCount == 0)
    }
}
