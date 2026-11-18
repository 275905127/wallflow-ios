import SwiftUI
import ImageIO

struct Gallery: View {
    @State private var library = SourceLibrary()
    @State private var managing = false

    var body: some View {
        GalleryFeed(source: library.selected) { managing = true }
            // Replace request, paging, and preview state even when an edit keeps the UUID.
            .id(library.selected.map(GallerySourceKey.init))
            .sheet(isPresented: $managing) { SourceManager(library: library) }
    }
}

// FeedSource equality includes the configuration; hashing just the UUID is sufficient.
private struct GallerySourceKey: Hashable {
    let source: FeedSource
    init(_ source: FeedSource) { self.source = source }
    func hash(into hasher: inout Hasher) { hasher.combine(source.id) }
}

private struct WallhavenSearch {
    let components: URLComponents
    let initialQuery: String
    let initialPage: Int

    init?(_ source: FeedSource?) {
        guard let source, source.kind == .json,
              let parts = URLComponents(string: source.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "wallhaven.cc",
              parts.percentEncodedPath == "/api/v1/search", parts.user == nil, parts.password == nil else { return nil }
        components = parts
        let parameters = parts.queryItems ?? []
        initialQuery = parameters.first { $0.name == "q" }?.value ?? ""
        initialPage = max(1, Int(parameters.first { $0.name == "page" }?.value ?? "") ?? 1)
    }

    func endpoint(query: String, page: Int) throws -> String {
        var parts = components
        var parameters = parts.percentEncodedQueryItems ?? []
        parameters.removeAll { ["q", "page"].contains($0.name.removingPercentEncoding ?? $0.name) }
        if !query.isEmpty {
            // Wallhaven's query parser treats a literal '+' as a space.
            var encoder = URLComponents()
            encoder.queryItems = [URLQueryItem(name: "q", value: query)]
            guard var item = encoder.percentEncodedQueryItems?.first else { throw URLError(.badURL) }
            item.value = item.value?.replacingOccurrences(of: "+", with: "%2B")
            parameters.append(item)
        }
        parameters.append(URLQueryItem(name: "page", value: String(page)))
        parts.percentEncodedQueryItems = parameters
        guard let url = parts.url else { throw URLError(.badURL) }
        return url.absoluteString
    }
}

private struct GalleryFeed: View {
    let source: FeedSource?
    let manage: () -> Void
    let search: WallhavenSearch?
    @State private var draft: String
    @State private var query: String
    @State private var page: Int
    @FocusState private var editing: Bool
    @State private var revision: UUID? = UUID()
    @State private var lastSuccess: (query: String, page: Int)?

    init(source: FeedSource?, manage: @escaping () -> Void) {
        self.source = source
        self.manage = manage
        let search = WallhavenSearch(source)
        self.search = search
        _draft = State(initialValue: search?.initialQuery ?? "")
        _query = State(initialValue: search?.initialQuery ?? "")
        _page = State(initialValue: search?.initialPage ?? 1)
    }
    @State private var items: [WallItem] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var preview: WallItem?

    var body: some View {
        ScrollView {
            if search != nil { searchControls }
            if source == nil {
                ContentUnavailableView {
                    Label("尚未接入图源", systemImage: "photo.stack")
                } description: { Text("一键接入 Wallhaven，或添加自定义接口来浏览壁纸。") } actions: {
                    Button("接入图源", action: manage).buttonStyle(.borderedProminent)
                }
            } else if let failure {
                ContentUnavailableView {
                    Label("图源加载失败", systemImage: "exclamationmark.triangle")
                } description: { Text(failure) } actions: { Button("重试", action: reload) }
            } else if loading {
                ProgressView("正在载入壁纸…").padding(.top, 64)
            } else if revision == nil && lastSuccess == nil {
                ContentUnavailableView {
                    Label("已取消加载", systemImage: "pause.circle")
                } actions: { Button("重新加载", action: reload) }
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("暂无壁纸", systemImage: "photo.on.rectangle")
                } description: {
                    if search != nil { Text(page > 1 ? "本页没有结果，可返回上一页或更换关键词。" : "换个关键词试试，或清空搜索以浏览全部壁纸。") }
                } actions: { Button("重新加载", action: reload) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { preview = item } label: {
                            Rectangle().fill(.quaternary).aspectRatio(0.75, contentMode: .fit)
                                .overlay { GalleryThumb(url: item.thumb).id(item.thumb) }
                                .clipShape(.rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看第 \(index + 1) 张壁纸")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .safeAreaBar(edge: .top) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("映壁").font(.title.bold()).accessibilityAddTraits(.isHeader)
                    Text(source?.name ?? "壁纸图库").font(.subheadline).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let source {
                    let random = source.kind == .random
                    Button(random ? "换一张" : "刷新", systemImage: random ? "shuffle" : "arrow.clockwise", action: reload)
                        .disabled(loading)
                }
                Button("管理图源", systemImage: "slider.horizontal.3", action: manage)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task(id: revision) { [revision] in
            guard let revision, var request = source else { return }
            do {
                if let search { request.endpoint = try search.endpoint(query: query, page: page) }
                let result = try await FeedLoader.load(request)
                guard !Task.isCancelled, revision == self.revision else { return }
                items = result
                lastSuccess = (query, page)
            } catch {
                guard !Task.isCancelled, revision == self.revision else { return }
                failure = error.localizedDescription
            }
            loading = false
        }
        .fullScreenCover(item: $preview) { item in GalleryPreview(url: item.full) }
    }

    private var searchControls: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("搜索 Wallhaven 壁纸", text: $draft)
                    .textFieldStyle(.roundedBorder).focused($editing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit(submitSearch)
                Button("搜索", systemImage: "magnifyingglass", action: submitSearch)
                    .labelStyle(.iconOnly)
            }
            HStack {
                Button("上一页", systemImage: "chevron.left") { turnPage(-1) }
                    .labelStyle(.iconOnly).disabled(page <= 1)
                Text("第 \(page) 页").monospacedDigit()
                Button("下一页", systemImage: "chevron.right") { turnPage(1) }
                    .labelStyle(.iconOnly).disabled(loading || failure != nil || items.isEmpty || page == Int.max)
                Spacer()
                if loading { Button("取消加载", action: cancelLoad) }
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func submitSearch() {
        editing = false
        query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        page = 1
        reload()
    }

    private func turnPage(_ delta: Int) {
        editing = false
        draft = query
        page += delta
        reload()
    }

    private func cancelLoad() {
        revision = nil
        loading = false
        failure = nil
        if let lastSuccess {
            query = lastSuccess.query
            draft = lastSuccess.query
            page = lastSuccess.page
        }
    }

    private func reload() {
        failure = nil
        loading = true
        revision = UUID()
    }
}

private struct GalleryThumb: View {
    let url: URL
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            } else { ProgressView() }
        }
        .task(id: url) {
            guard image == nil else { return }
            do {
                let result = try await GalleryImages.shared.read(url, maxPixel: 640)
                try Task.checkCancellation()
                image = result
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

private struct GalleryPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .accessibilityLabel("壁纸大图")
                } else if let failure {
                    ContentUnavailableView {
                        Label("无法打开大图", systemImage: "photo")
                    } description: { Text(failure) } actions: {
                        Button("重试") { self.failure = nil; attempt += 1 }
                    }
                } else { ProgressView("正在载入大图…") }
            }
            .navigationTitle("壁纸预览").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
                if let image {
                    ToolbarItem(placement: .primaryAction) {
                        let picture = Image(decorative: image, scale: 1)
                        ShareLink(item: picture, preview: SharePreview("映壁壁纸", image: picture)) {
                            Label("分享图片", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: attempt) {
            do {
                let result = try await GalleryImages.shared.read(url, maxPixel: nil)
                try Task.checkCancellation()
                image = result
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }
}

// Keep synchronous file IO and ImageIO decoding off the main actor.
private actor GalleryImages {
    static let shared = GalleryImages()

    func read(_ url: URL, maxPixel: Int?) async throws -> CGImage {
        try Task.checkCancellation()
        let source: CGImageSource?
        if url.isFileURL {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        try Task.checkCancellation()
        guard let source else { throw URLError(.cannotDecodeContentData) }
        var options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceShouldCacheImmediately: true]
        if let maxPixel { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }
}
