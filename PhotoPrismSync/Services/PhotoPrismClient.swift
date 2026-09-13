import Foundation

struct PhotoPrismSessionInfo {
    let userUID: String
}

final class PhotoPrismClient {
    static let shared = PhotoPrismClient()

    private var cachedSession: AuthenticatedPhotoPrismSession?
    private let jsonDecoder = JSONDecoder()

    func validateConnection(using settings: PhotoPrismServerSettings) async throws {
        _ = try await signIn(using: settings, forceRefresh: true)
    }

    func sessionInfo(using settings: PhotoPrismServerSettings) async throws -> PhotoPrismSessionInfo {
        let session = try await signIn(using: settings)
        return PhotoPrismSessionInfo(userUID: session.userUID)
    }

    func fetchLibraryItems(using settings: PhotoPrismServerSettings) async throws -> [AssetDescriptor] {
        var session = try await signIn(using: settings)
        let pageSize = 500
        var offset = 0
        var items: [AssetDescriptor] = []

        while true {
            var components = URLComponents(url: session.apiBaseURL.appendingPathComponent("photos"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "count", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "merged", value: "true"),
                URLQueryItem(name: "order", value: "oldest"),
            ]

            guard let url = components?.url else {
                throw PhotoPrismClientError.invalidServerURL
            }

            let (data, response) = try await sendAuthorizedRequest(url: url, method: "GET", session: session)
            session = session.updatingTokens(from: response)
            cachedSession = session

            let photos = try jsonDecoder.decode([RemotePhoto].self, from: data)
            if photos.isEmpty {
                break
            }

            items.append(contentsOf: photos.compactMap { $0.assetDescriptor(using: session) })

            if photos.count < pageSize {
                break
            }

            offset += pageSize
        }

        return items
    }

    func downloadOriginal(for item: AssetDescriptor, using settings: PhotoPrismServerSettings) async throws -> Data {
        let session = try await signIn(using: settings)
        guard let url = item.downloadURL else {
            throw PhotoPrismClientError.missingDownloadURL
        }

        let request = authorizedRequest(url: url, method: "GET", session: session)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, payload: data)
        return data
    }

    func uploadOriginals(
        fileURLs: [URL],
        userUID: String,
        uploadToken: String,
        using settings: PhotoPrismServerSettings
    ) async throws {
        let session = try await signIn(using: settings)
        let url = session.apiBaseURL
            .appendingPathComponent("users")
            .appendingPathComponent(userUID)
            .appendingPathComponent("upload")
            .appendingPathComponent(uploadToken)

        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyURL = try createMultipartBodyFile(for: fileURLs, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = authorizedRequest(url: url, method: "POST", session: session)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        try validate(response: response, payload: nil)
    }

    func processUploadedOriginals(userUID: String, uploadToken: String, using settings: PhotoPrismServerSettings) async throws {
        let session = try await signIn(using: settings)
        let url = session.apiBaseURL
            .appendingPathComponent("users")
            .appendingPathComponent(userUID)
            .appendingPathComponent("upload")
            .appendingPathComponent(uploadToken)

        let body = try JSONSerialization.data(withJSONObject: ["albums": []])
        var request = authorizedRequest(url: url, method: "PUT", session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try validate(response: response, payload: data)
    }

    private func signIn(using settings: PhotoPrismServerSettings, forceRefresh: Bool = false) async throws -> AuthenticatedPhotoPrismSession {
        guard let baseURL = settings.normalizedBaseURL else {
            throw PhotoPrismClientError.invalidServerURL
        }

        if !forceRefresh,
           let cachedSession,
           cachedSession.cacheKey == AuthenticatedPhotoPrismSession.cacheKey(for: settings)
        {
            return cachedSession
        }

        let apiBaseURL = apiBaseURL(from: baseURL)
        let loginURL = apiBaseURL.appendingPathComponent("session")
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": settings.username,
            "password": settings.password,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, payload: data)

        let payload = try jsonDecoder.decode(SessionResponse.self, from: data)
        let signedInSession = try AuthenticatedPhotoPrismSession(payload: payload, settings: settings, fallbackBaseURL: baseURL)
        cachedSession = signedInSession
        return signedInSession
    }

    private func apiBaseURL(from baseURL: URL) -> URL {
        if baseURL.path.hasSuffix("/api/v1") {
            return baseURL
        }

        return baseURL.appendingPathComponent("api").appendingPathComponent("v1")
    }

    private func authorizedRequest(url: URL, method: String, session: AuthenticatedPhotoPrismSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + session.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func sendAuthorizedRequest(url: URL, method: String, session: AuthenticatedPhotoPrismSession) async throws -> (Data, HTTPURLResponse) {
        let request = authorizedRequest(url: url, method: method, session: session)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoPrismClientError.invalidResponse
        }
        try validate(response: httpResponse, payload: data)
        return (data, httpResponse)
    }

    private func validate(response: URLResponse, payload: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoPrismClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = payload.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PhotoPrismClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func createMultipartBodyFile(for fileURLs: [URL], boundary: String) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: bodyURL)
        defer { try? handle.close() }

        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            let header = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType(for: fileURL))\r\n\r\n".utf8)
            try handle.write(contentsOf: header)
            try appendContents(of: fileURL, to: handle)
            try handle.write(contentsOf: Data("\r\n".utf8))
        }

        try handle.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
        return bodyURL
    }

    private func appendContents(of fileURL: URL, to handle: FileHandle) throws {
        let sourceHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? sourceHandle.close() }

        while let chunk = try sourceHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "heic", "heif":
            return "image/heic"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "mov":
            return "video/quicktime"
        case "mp4", "m4v":
            return "video/mp4"
        default:
            return "application/octet-stream"
        }
    }
}

enum PhotoPrismClientError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case missingAccessToken
    case missingUserUID
    case missingDownloadURL
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The PhotoPrism URL is invalid."
        case .invalidResponse:
            return "The PhotoPrism server returned an invalid response."
        case .missingAccessToken:
            return "PhotoPrism did not return an access token."
        case .missingUserUID:
            return "PhotoPrism did not return the signed-in user identifier."
        case .missingDownloadURL:
            return "A PhotoPrism photo did not include a download URL."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                return "PhotoPrism request failed (\(statusCode)): \(message)"
            }
            return "PhotoPrism request failed with status \(statusCode)."
        }
    }
}

private struct AuthenticatedPhotoPrismSession {
    let cacheKey: String
    let accessToken: String
    let userUID: String
    let apiBaseURL: URL
    let contentBaseURL: URL
    let previewToken: String
    let downloadToken: String

    static func cacheKey(for settings: PhotoPrismServerSettings) -> String {
        [settings.normalizedBaseURL?.absoluteString ?? "", settings.username, settings.password].joined(separator: "\u{0}")
    }

    init(payload: SessionResponse, settings: PhotoPrismServerSettings, fallbackBaseURL: URL) throws {
        let token = payload.accessToken ?? payload.legacyAccessToken
        guard let token, !token.isEmpty else {
            throw PhotoPrismClientError.missingAccessToken
        }

        guard let userUID = payload.user?.resolvedUID, !userUID.isEmpty else {
            throw PhotoPrismClientError.missingUserUID
        }

        cacheKey = Self.cacheKey(for: settings)
        accessToken = token
        self.userUID = userUID
        apiBaseURL = payload.config?.resolvedAPIURL(relativeTo: fallbackBaseURL) ?? fallbackBaseURL.appendingPathComponent("api").appendingPathComponent("v1")
        contentBaseURL = payload.config?.resolvedContentURL(relativeTo: fallbackBaseURL) ?? fallbackBaseURL
        previewToken = payload.config?.previewToken ?? "public"
        downloadToken = payload.config?.downloadToken ?? "public"
    }

    func updatingTokens(from response: HTTPURLResponse) -> AuthenticatedPhotoPrismSession {
        AuthenticatedPhotoPrismSession(
            cacheKey: cacheKey,
            accessToken: accessToken,
            userUID: userUID,
            apiBaseURL: apiBaseURL,
            contentBaseURL: contentBaseURL,
            previewToken: response.value(forHTTPHeaderField: "X-Preview-Token") ?? previewToken,
            downloadToken: response.value(forHTTPHeaderField: "X-Download-Token") ?? downloadToken
        )
    }

    private init(
        cacheKey: String,
        accessToken: String,
        userUID: String,
        apiBaseURL: URL,
        contentBaseURL: URL,
        previewToken: String,
        downloadToken: String
    ) {
        self.cacheKey = cacheKey
        self.accessToken = accessToken
        self.userUID = userUID
        self.apiBaseURL = apiBaseURL
        self.contentBaseURL = contentBaseURL
        self.previewToken = previewToken
        self.downloadToken = downloadToken
    }
}

private struct SessionResponse: Decodable {
    let accessToken: String?
    let legacyAccessToken: String?
    let user: SessionUser?
    let config: SessionConfig?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case legacyAccessToken = "id"
        case user
        case config
    }
}

private struct SessionUser: Decodable {
    let resolvedUID: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        resolvedUID = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("UID"))
            ?? container.decodeIfPresent(String.self, forKey: DynamicCodingKey("uid"))
    }
}

private struct SessionConfig: Decodable {
    let apiUri: String?
    let contentUri: String?
    let previewToken: String?
    let downloadToken: String?

    enum CodingKeys: String, CodingKey {
        case apiUri
        case contentUri
        case previewToken
        case downloadToken
    }

    func resolvedAPIURL(relativeTo baseURL: URL) -> URL? {
        resolveURL(from: apiUri, relativeTo: baseURL)
    }

    func resolvedContentURL(relativeTo baseURL: URL) -> URL? {
        resolveURL(from: contentUri, relativeTo: baseURL)
    }

    private func resolveURL(from value: String?, relativeTo baseURL: URL) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}

private struct RemotePhoto: Decodable {
    let uid: String?
    let type: String?
    let takenAt: String?
    let takenAtLocal: String?
    let hash: String?
    let fileName: String?
    let originalName: String?
    let name: String?
    let files: [RemoteFile]

    enum CodingKeys: String, CodingKey {
        case uid = "UID"
        case type = "Type"
        case takenAt = "TakenAt"
        case takenAtLocal = "TakenAtLocal"
        case hash = "Hash"
        case fileName = "FileName"
        case originalName = "OriginalName"
        case name = "Name"
        case files = "Files"
    }

    func assetDescriptor(using session: AuthenticatedPhotoPrismSession) -> AssetDescriptor? {
        guard let uid, !uid.isEmpty else { return nil }

        let preferredFile = files.first(where: { $0.primary == true }) ?? files.first
        let filename = preferredFile?.bestName ?? [originalName, fileName, name].first(where: { !($0 ?? "").isEmpty }) ?? uid
        let fileHash = preferredFile?.hash ?? hash
        let mediaKind = MediaKind(remoteType: type, isVideo: preferredFile?.isVideo == true)
        let previewURL = fileHash.flatMap {
            session.contentBaseURL
                .appendingPathComponent("t")
                .appendingPathComponent($0)
                .appendingPathComponent(session.previewToken)
                .appendingPathComponent("tile_500")
        }
        let downloadURL = fileHash.flatMap {
            var components = URLComponents(url: session.apiBaseURL.appendingPathComponent("dl").appendingPathComponent($0), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "t", value: session.downloadToken)]
            return components?.url
        }

        return AssetDescriptor(
            id: uid,
            source: .remote,
            filename: filename,
            capturedAt: DateParser.parse(takenAt) ?? DateParser.parse(takenAtLocal),
            mediaKind: mediaKind,
            sizeBytes: Int64(preferredFile?.size ?? 0),
            previewURL: previewURL,
            downloadURL: downloadURL
        )
    }
}

private struct RemoteFile: Decodable {
    let originalName: String?
    let name: String?
    let hash: String?
    let size: Int?
    let primary: Bool?
    let isVideo: Bool?

    enum CodingKeys: String, CodingKey {
        case originalName = "OriginalName"
        case name = "Name"
        case hash = "Hash"
        case size = "Size"
        case primary = "Primary"
        case isVideo = "Video"
    }

    var bestName: String {
        [originalName, name].first(where: { !($0 ?? "").isEmpty }) ?? UUID().uuidString
    }
}

private enum DateParser {
    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601Standard = ISO8601DateFormatter()

    static let localFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return iso8601Fractional.date(from: value)
            ?? iso8601Standard.date(from: value)
            ?? localFormatters.lazy.compactMap { $0.date(from: value) }.first
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension MediaKind {
    init(remoteType: String?, isVideo: Bool) {
        let normalizedType = remoteType?.lowercased() ?? ""
        if isVideo || normalizedType == "video" {
            self = .video
        } else if normalizedType == "live" {
            self = .livePhoto
        } else {
            self = .photo
        }
    }
}
