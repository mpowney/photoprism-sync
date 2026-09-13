import SwiftUI
import UIKit

struct PreviewGridView: View {
    let items: [AssetDescriptor]
    let formattedSize: (Int64) -> String

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            AssetThumbnailView(item: item)
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(item.filename)
                                .font(.caption)
                                .lineLimit(2)
                            Text(formattedSize(item.sizeBytes))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AssetThumbnailView: View {
    let item: AssetDescriptor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.15))

            switch item.source {
            case .local:
                LocalAssetThumbnailView(localIdentifier: item.id)
            case .remote:
                if let previewURL = item.previewURL {
                    RemoteAssetThumbnailView(url: previewURL)
                } else {
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct LocalAssetThumbnailView: View {
    let localIdentifier: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task(id: localIdentifier) {
            image = await LocalPhotoLibraryService.shared.requestThumbnail(for: localIdentifier, targetSize: CGSize(width: 300, height: 300))
        }
    }
}

private struct RemoteAssetThumbnailView: View {
    let url: URL
    @StateObject private var loader: RemoteThumbnailLoader

    init(url: URL) {
        self.url = url
        _loader = StateObject(wrappedValue: RemoteThumbnailLoader(url: url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loader.isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await loader.load()
        }
    }
}

@MainActor
private final class RemoteThumbnailLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false

    private let url: URL
    private let session: URLSession

    init(url: URL) {
        self.url = url
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func load() async {
        guard image == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, _) = try await session.data(for: request)
            image = UIImage(data: data)
        } catch {
            image = nil
        }
    }
}
