import SwiftUI
import ImageIO

struct Gallery: View {
    @State private var library = SourceLibrary()
    @State private var selection: WallFlowTab = .gallery

    var body: some View {
        TabView(selection: $selection) {
            Tab("图库", systemImage: "photo.on.rectangle", value: WallFlowTab.gallery) {
                NavigationStack {
                    GalleryFeed(source: library.selected) { selection = .sources }
                }
                // Changing the selection or editing its fields also clears any old preview.
                .id(library.selected.map(GallerySourceKey.init))
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            Tab("图源", systemImage: "network", value: WallFlowTab.sources) {
                SourceManager(library: library) { selection = .gallery }
            }
            Tab("设置", systemImage: "gearshape", value: WallFlowTab.settings) {
                NativeSettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

private enum WallFlowTab: Hashable {
    case gallery, sources, settings
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

    var body: some View {
        List {
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
                Section(source?.name ?? "壁纸") {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            GalleryPreview(url: item.full)
                        } label: {
                            HStack(spacing: 12) {
                                GalleryThumb(url: item.thumb)
                                    .id(item.thumb)
                                    .frame(width: 76, height: 100)
                                    .clipped()
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("壁纸 \(index + 1)")
                                        .font(.headline)
                                    Text(item.full.host ?? source?.name ?? "在线图源")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text("查看大图")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if visibleItems.isEmpty {
                        ContentUnavailableView.search(text: draft)
                    }
                }
            }
            if search != nil { pagingControls }
        }
        .listStyle(.plain)
        .navigationTitle("映壁")
        .navigationSubtitle(source?.name ?? "选择在线图源")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $draft, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: search != nil ? "搜索 Wallhaven 壁纸" : "筛选本页图片地址")
        .onSubmit(of: .search, submitSearch)
        .onChange(of: draft) { previous, value in
            if search != nil && value.isEmpty && !previous.isEmpty && !query.isEmpty {
                submitSearch()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("图源", systemImage: "slider.horizontal.3", action: manage)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(source?.kind == .random ? "换一张" : "刷新",
                       systemImage: source?.kind == .random ? "shuffle" : "arrow.clockwise", action: reload)
                    .disabled(loading || source == nil)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
    }

    private var visibleItems: [WallItem] {
        guard search == nil, !draft.isEmpty else { return items }
        return items.filter { $0.full.absoluteString.localizedCaseInsensitiveContains(draft) }
    }

    private var pagingControls: some View {
        Section("分页") {
            LabeledContent("当前页", value: String(page))
            Button("上一页", systemImage: "chevron.left") { turnPage(-1) }
                .disabled(page <= 1 || loading)
            Button("下一页", systemImage: "chevron.right") { turnPage(1) }
                .disabled(loading || failure != nil || items.isEmpty || page == Int.max)
            if loading { Button("取消加载", systemImage: "xmark.circle", action: cancelLoad) }
        }
    }

    private func submitSearch() {
        guard search != nil else { return }
        query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        page = 1
        reload()
    }

    private func turnPage(_ delta: Int) {
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
    @State private var image: CGImage?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        Group {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("壁纸预览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let image {
                ToolbarItem(placement: .primaryAction) {
                    let picture = Image(decorative: image, scale: 1)
                    ShareLink(item: picture, preview: SharePreview("映壁壁纸", image: picture)) {
                        Label("分享图片", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
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
