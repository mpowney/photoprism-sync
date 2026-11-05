import SwiftUI
import UIKit

struct PreviewGridView: View {
    let items: [AssetDescriptor]
    let formattedSize: (Int64) -> String
    let onSync: ([AssetDescriptor]) -> Void
    let syncButtonTitle: String
    var isDestructive = false
    var showsDoneButton = true
    var showsSyncBar = true
    var emptyTitle: LocalizedStringKey = "No Matching Items"
    var emptyDescription: LocalizedStringKey = "Adjust your criteria and calculate again."

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedIDs: Set<String> = []
    @State private var detailItem: AssetDescriptor?
    @State private var isSelecting = false

    private var selectedItems: [AssetDescriptor] {
        items.filter { selectedIDs.contains($0.id) }
    }

    private var selectedSize: Int64 {
        selectedItems.reduce(into: 0) { $0 += $1.sizeBytes }
    }

    var body: some View {
        GeometryReader { proxy in
            let columnCount = columnCount(for: proxy.size.width)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)

            ScrollView {
                if items.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "photo",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(items) { item in
                            Button {
                                if isSelecting {
                                    toggleSelection(for: item)
                                } else {
                                    detailItem = item
                                }
                            } label: {
                                AssetThumbnailView(item: item)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(alignment: .topTrailing) {
                                        mediaBadge(for: item)
                                    }
                                    .overlay(alignment: .topLeading) {
                                        if selectedIDs.contains(item.id) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .blue)
                                                .padding(6)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(selectionLabel(for: item))
                            .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
                            .contextMenu {
                                Button {
                                    detailItem = item
                                } label: {
                                    Label("View Details", systemImage: "info.circle")
                                }
                                Button {
                                    toggleSelection(for: item)
                                } label: {
                                    Label(
                                        selectedIDs.contains(item.id) ? String(localized: "Deselect") : String(localized: "Select"),
                                        systemImage: selectedIDs.contains(item.id) ? "checkmark.circle" : "circle"
                                    )
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
        .navigationTitle("\(items.count) Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? String(localized: "Done") : String(localized: "Select")) {
                    isSelecting.toggle()
                }
                .disabled(items.isEmpty)
            }
            if isSelecting {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("Select All") {
                            selectedIDs = Set(items.map(\.id))
                        }
                        Button("Deselect All") {
                            selectedIDs.removeAll()
                        }
                    } label: {
                        Label("Selection Options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsSyncBar {
                selectionBar
            }
        }
        .onAppear {
            selectedIDs = Set(items.map(\.id))
        }
        .onChange(of: items) { _, updatedItems in
            let validIDs = Set(updatedItems.map(\.id))
            selectedIDs = selectedIDs.intersection(validIDs)
        }
        .fullScreenCover(item: $detailItem) { item in
            AssetDetailPager(
                items: items,
                initialItem: item,
                selectedIDs: $selectedIDs,
                formattedSize: formattedSize
            )
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedItems.count) selected")
                    .font(.subheadline.weight(.semibold))
                Text(formattedSize(selectedSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button {
                onSync(selectedItems)
            } label: {
                Text(syncButtonTitle)
                    .frame(minWidth: 88)
            }
            .buttonStyle(.borderedProminent)
            .tint(isDestructive ? .red : nil)
            .disabled(selectedItems.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func mediaBadge(for item: AssetDescriptor) -> some View {
        switch item.mediaKind {
        case .photo:
            EmptyView()
        case .livePhoto:
            Label("LIVE", systemImage: "livephoto")
                .labelStyle(.titleOnly)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
                .accessibilityLabel("Live Photo")
        case .video:
            Label("VIDEO", systemImage: "video")
                .labelStyle(.titleOnly)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
                .accessibilityLabel("Video")
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        guard horizontalSizeClass == .regular else { return 3 }
        let suggestedCount = max(2, Int(width / 150))
        return suggestedCount.isMultiple(of: 2) ? suggestedCount : suggestedCount - 1
    }

    private func toggleSelection(for item: AssetDescriptor) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func selectionLabel(for item: AssetDescriptor) -> String {
        "\(selectedIDs.contains(item.id) ? String(localized: "Selected") : String(localized: "Not selected")), \(item.filename), \(formattedSize(item.sizeBytes))"
    }
}

private struct AssetThumbnailView: View {
    let item: AssetDescriptor

    var body: some View {
        ZStack {
            Rectangle()
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
        .clipped()
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
            image = await LocalPhotoLibraryService.shared.requestThumbnail(
                for: localIdentifier,
                targetSize: CGSize(width: 300, height: 300)
            )
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

private func mediaKindTitle(_ kind: MediaKind) -> String {
    switch kind {
    case .photo: String(localized: "Photo")
    case .livePhoto: String(localized: "Live Photo")
    case .video: String(localized: "Video")
    }
}

private struct AssetDetailPager: View {
    let items: [AssetDescriptor]
    let initialItem: AssetDescriptor
    @Binding var selectedIDs: Set<String>
    let formattedSize: (Int64) -> String

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String
    @State private var isShowingInfo = false

    init(
        items: [AssetDescriptor],
        initialItem: AssetDescriptor,
        selectedIDs: Binding<Set<String>>,
        formattedSize: @escaping (Int64) -> String
    ) {
        self.items = items
        self.initialItem = initialItem
        _selectedIDs = selectedIDs
        self.formattedSize = formattedSize
        _currentID = State(initialValue: initialItem.id)
    }

    private var currentItem: AssetDescriptor {
        items.first(where: { $0.id == currentID }) ?? initialItem
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentID) {
                ForEach(items) { item in
                    AssetDetailImage(item: item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(.black)
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    Text(currentItem.filename)
                        .font(.headline)
                        .lineLimit(1)
                    Text(formattedSize(currentItem.sizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if selectedIDs.contains(currentItem.id) {
                            selectedIDs.remove(currentItem.id)
                        } else {
                            selectedIDs.insert(currentItem.id)
                        }
                    } label: {
                        Label(
                            selectedIDs.contains(currentItem.id) ? String(localized: "Deselect") : String(localized: "Select"),
                            systemImage: selectedIDs.contains(currentItem.id) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isShowingInfo = true
                    } label: {
                        Label("Info", systemImage: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingInfo) {
                NavigationStack {
                    List {
                        LabeledContent("Filename", value: currentItem.filename)
                        LabeledContent("Size", value: formattedSize(currentItem.sizeBytes))
                        LabeledContent("Type", value: mediaKindTitle(currentItem.mediaKind))
                        if let capturedAt = currentItem.capturedAt {
                            LabeledContent("Date", value: capturedAt.formatted(date: .long, time: .shortened))
                        }
                    }
                    .navigationTitle("Photo Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingInfo = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct AssetDetailImage: View {
    let item: AssetDescriptor
    @State private var image: UIImage?
    @State private var zoomScale = 1.0

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(zoomScale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    zoomScale = min(max(value.magnification, 1), 4)
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(duration: 0.25)) {
                                        zoomScale = min(max(zoomScale, 1), 4)
                                    }
                                }
                        )
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: item.id) {
                await loadImage()
            }
        }
        .background(.black)
    }

    private func loadImage() async {
        switch item.source {
        case .local:
            image = await LocalPhotoLibraryService.shared.requestThumbnail(
                for: item.id,
                targetSize: CGSize(width: 2400, height: 2400)
            )
        case .remote:
            guard let url = item.previewURL else { return }
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                let configuration = URLSessionConfiguration.ephemeral
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.urlCache = nil
                let (data, _) = try await URLSession(configuration: configuration).data(for: request)
                image = UIImage(data: data)
            } catch {
                image = nil
            }
        }
    }
}

struct PreviewPanelView: View {
    enum Mode: Hashable {
        case changes
        case matched
    }

    let items: [AssetDescriptor]
    let matchedItems: [AssetDescriptor]
    let formattedSize: (Int64) -> String
    let onSync: ([AssetDescriptor]) -> Void
    let syncButtonTitle: String
    var isDestructive = false
    var showsDoneButton = true

    @State private var mode: Mode = .changes

    var body: some View {
        VStack(spacing: 0) {
            Picker("Preview", selection: $mode) {
                (isDestructive ? Text("Selected for Deletion") : Text("Not Synced"))
                    .tag(Mode.changes)
                Text("Synced").tag(Mode.matched)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch mode {
            case .changes:
                PreviewGridView(
                    items: items,
                    formattedSize: formattedSize,
                    onSync: onSync,
                    syncButtonTitle: syncButtonTitle,
                    isDestructive: isDestructive,
                    showsDoneButton: showsDoneButton
                )
            case .matched:
                PreviewGridView(
                    items: matchedItems,
                    formattedSize: formattedSize,
                    onSync: { _ in },
                    syncButtonTitle: syncButtonTitle,
                    showsDoneButton: showsDoneButton,
                    showsSyncBar: false,
                    emptyTitle: "No Matched Items",
                    emptyDescription: "No photos were found in both locations."
                )
            }
        }
        .onAppear {
            if items.isEmpty { mode = .matched }
        }
        .onChange(of: items.isEmpty) { _, isEmpty in
            if isEmpty { mode = .matched }
        }
    }

}
