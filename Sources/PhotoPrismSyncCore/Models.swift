import Foundation

public enum MediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo
    case livePhoto
    case video

    public var id: String { rawValue }
}

public enum TimeUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case days
    case weeks
    case months
    case years

    public var id: String { rawValue }
}

public struct AgeRule: Codable, Equatable, Hashable, Sendable {
    public var value: Int
    public var unit: TimeUnit

    public init(value: Int = 30, unit: TimeUnit = .days) {
        self.value = value
        self.unit = unit
    }

    public func cutoffDate(relativeTo date: Date, calendar: Calendar = .current) -> Date? {
        guard value > 0 else { return nil }

        let component: Calendar.Component = switch unit {
        case .days: .day
        case .weeks: .weekOfYear
        case .months: .month
        case .years: .year
        }

        return calendar.date(byAdding: component, value: -value, to: date)
    }
}

public enum DuplicateCriterion: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case filename
    case photoTimestamp

    public var id: String { rawValue }
}

public struct MediaSelection: Codable, Equatable, Hashable, Sendable {
    public var includePhotos: Bool
    public var includeLivePhotos: Bool
    public var includeVideos: Bool

    public init(includePhotos: Bool = true, includeLivePhotos: Bool = true, includeVideos: Bool = true) {
        self.includePhotos = includePhotos
        self.includeLivePhotos = includeLivePhotos
        self.includeVideos = includeVideos
    }

    public static let all = MediaSelection()

    public func matches(_ kind: MediaKind) -> Bool {
        switch kind {
        case .photo:
            includePhotos
        case .livePhoto:
            includeLivePhotos
        case .video:
            includeVideos
        }
    }
}

public struct SyncCriteria: Codable, Equatable, Sendable {
    public var ageRule: AgeRule?
    public var mediaSelection: MediaSelection
    public var avoidDuplicates: Bool
    public var duplicateCriteria: Set<DuplicateCriterion>

    public init(
        ageRule: AgeRule? = AgeRule(),
        mediaSelection: MediaSelection = .all,
        avoidDuplicates: Bool = false,
        duplicateCriteria: Set<DuplicateCriterion> = []
    ) {
        self.ageRule = ageRule
        self.mediaSelection = mediaSelection
        self.avoidDuplicates = avoidDuplicates
        self.duplicateCriteria = duplicateCriteria
    }

    public var effectiveDuplicateCriteria: Set<DuplicateCriterion> {
        guard avoidDuplicates else { return [] }
        return duplicateCriteria.isEmpty ? Set(DuplicateCriterion.allCases) : duplicateCriteria
    }
}

public enum SyncAction: String, Codable, Identifiable, Sendable {
    case upload
    case download
    case deleteFoundInPhotoPrism
    case deleteOlderThan

    public var id: String { rawValue }
}

public enum AssetSource: String, Codable, Equatable, Sendable {
    case local
    case remote
}

public struct AssetDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var source: AssetSource
    public var filename: String
    public var capturedAt: Date?
    public var mediaKind: MediaKind
    public var sizeBytes: Int64
    public var previewURL: URL?
    public var downloadURL: URL?

    public init(
        id: String,
        source: AssetSource = .local,
        filename: String,
        capturedAt: Date?,
        mediaKind: MediaKind,
        sizeBytes: Int64,
        previewURL: URL? = nil,
        downloadURL: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.filename = filename
        self.capturedAt = capturedAt
        self.mediaKind = mediaKind
        self.sizeBytes = sizeBytes
        self.previewURL = previewURL
        self.downloadURL = downloadURL
    }
}

public struct SelectionSummary: Codable, Equatable, Sendable {
    public var itemCount: Int
    public var totalBytes: Int64

    public init(itemCount: Int, totalBytes: Int64) {
        self.itemCount = itemCount
        self.totalBytes = totalBytes
    }

    public init(items: [AssetDescriptor]) {
        self.itemCount = items.count
        self.totalBytes = items.reduce(into: 0) { $0 += $1.sizeBytes }
    }
}

public struct CalculationSnapshot: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var action: SyncAction
    public var criteria: SyncCriteria
    public var items: [AssetDescriptor]

    public init(
        createdAt: Date = .now,
        action: SyncAction,
        criteria: SyncCriteria,
        items: [AssetDescriptor]
    ) {
        self.createdAt = createdAt
        self.action = action
        self.criteria = criteria
        self.items = items
    }

    public var summary: SelectionSummary {
        SelectionSummary(items: items)
    }
}
