import Foundation

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
}
