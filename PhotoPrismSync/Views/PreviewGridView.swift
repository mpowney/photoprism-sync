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
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil

        do {
            let (data, _) = try await URLSession(configuration: configuration).data(for: request)
            image = UIImage(data: data)
        } catch {
            image = nil
        }
    }
}
