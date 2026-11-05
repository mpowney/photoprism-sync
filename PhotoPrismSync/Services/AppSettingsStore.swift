import Foundation
import SwiftUI

enum TimestampFilterPreset: String, Codable, CaseIterable, Identifiable {
    case custom
    case oneMonth
    case twoMonths
    case threeMonths
    case fourMonths
    case fiveMonths
    case sixMonths
    case oneYear
    case twoYears

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .custom: "Custom"
        case .oneMonth: "More than one month old"
        case .twoMonths: "More than two months old"
        case .threeMonths: "More than three months old"
        case .fourMonths: "More than four months old"
        case .fiveMonths: "More than five months old"
        case .sixMonths: "More than six months old"
        case .oneYear: "More than one year old"
        case .twoYears: "More than two years old"
        }
    }

    var offset: (component: Calendar.Component, value: Int)? {
        switch self {
        case .custom: nil
        case .oneMonth: (.month, 1)
        case .twoMonths: (.month, 2)
        case .threeMonths: (.month, 3)
        case .fourMonths: (.month, 4)
        case .fiveMonths: (.month, 5)
        case .sixMonths: (.month, 6)
        case .oneYear: (.year, 1)
        case .twoYears: (.year, 2)
        }
    }
}

struct TimestampFilterSettings: Codable, Equatable {
    var isEnabled: Bool
    var preset: TimestampFilterPreset
    var startDate: Date
    var endDate: Date
    var customStartDate: Date
    var customEndDate: Date

    init(now: Date = .now) {
        let startDate = Self.earliestDate()
        isEnabled = false
        preset = .custom
        self.startDate = startDate
        endDate = now
        customStartDate = startDate
        customEndDate = now
    }

    var photoTimestampRange: PhotoTimestampRange {
        PhotoTimestampRange(startDate: startDate, endDate: endDate)
    }

    mutating func select(_ preset: TimestampFilterPreset, relativeTo now: Date = .now, calendar: Calendar = .current) {
        self.preset = preset
        guard let offset = preset.offset else {
            startDate = customStartDate
            endDate = customEndDate
            return
        }

        startDate = Self.earliestDate(calendar: calendar)
        endDate = calendar.date(byAdding: offset.component, value: -offset.value, to: now) ?? now
    }

    mutating func setStartDate(_ date: Date) {
        preset = .custom
        startDate = max(date, Self.earliestDate())
        if endDate < startDate {
            endDate = startDate
        }
        customStartDate = startDate
        customEndDate = endDate
    }

    mutating func setEndDate(_ date: Date) {
        preset = .custom
        endDate = max(date, startDate)
        customStartDate = startDate
        customEndDate = endDate
    }

    private static func earliestDate(calendar: Calendar = .current) -> Date {
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = calendar.timeZone
        return gregorianCalendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    }
}

struct PhotoPrismServerSettings: Equatable {
    var baseURLString: String = ""
    var username: String = ""
    var password: String = ""

    var normalizedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate) else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let normalizedPath = (components?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"

        return components?.url
    }

    var isComplete: Bool {
        normalizedBaseURL != nil && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
}

final class AppSettingsStore: @unchecked Sendable {
    static let shared = AppSettingsStore()

    private enum Keys {
        static let service = "com.mpowney.photoprismsync"
        static let baseURL = "photoprism.base-url"
        static let username = "photoprism.username"
        static let password = "photoprism.password"
        static let timestampFilter = "sync.timestamp-filter"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func load() -> PhotoPrismServerSettings {
        PhotoPrismServerSettings(
            baseURLString: defaults.string(forKey: Keys.baseURL) ?? "",
            username: defaults.string(forKey: Keys.username) ?? "",
            password: (try? keychain.string(forKey: Keys.password, service: Keys.service)) ?? ""
        )
    }

    func save(_ settings: PhotoPrismServerSettings) throws {
        defaults.set(settings.baseURLString, forKey: Keys.baseURL)
        defaults.set(settings.username, forKey: Keys.username)
        try keychain.setString(settings.password, forKey: Keys.password, service: Keys.service)
    }

    func loadTimestampFilter(relativeTo now: Date = .now) -> TimestampFilterSettings {
        var filter = defaults.data(forKey: Keys.timestampFilter)
            .flatMap { try? JSONDecoder().decode(TimestampFilterSettings.self, from: $0) }
            ?? TimestampFilterSettings(now: now)
        if filter.preset != .custom {
            filter.select(filter.preset, relativeTo: now)
        }
        saveTimestampFilter(filter)
        return filter
    }

    func saveTimestampFilter(_ filter: TimestampFilterSettings) {
        guard let data = try? JSONEncoder().encode(filter) else { return }
        defaults.set(data, forKey: Keys.timestampFilter)
    }
}
