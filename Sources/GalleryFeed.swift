import SwiftUI

struct GalleryFeed: View {
    let source: FeedSource?
    let sources: [FeedSource]
    let select: (FeedSource) -> Void
    let manage: () -> Void

    @State private var model: GalleryFeedModel
    @State private var draft: String
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var availableWidth: CGFloat = 0
    @State private var randomPreview: (url: URL, image: CGImage)?
    @State private var randomPreviewFailed = false
    @Namespace private var previewTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private let margin: CGFloat = 12
    private let spacing: CGFloat = 8

    init(source: FeedSource?, sources: [FeedSource], select: @escaping (FeedSource) -> Void, manage: @escaping () -> Void) {
        self.source = source
        self.sources = sources
        self.select = select
        self.manage = manage
        let model = GalleryFeedModel(source: source)
        _model = State(initialValue: model)
        _draft = State(initialValue: model.search?.initialQuery ?? "")
    }

    var body: some View {
        browsingContent
            .navigationTitle("映壁")
            .navigationSubtitle(source?.name ?? "在线壁纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sourceMenu }
                if let source {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(source.kind == .random ? "换一张" : "刷新",
                               systemImage: source.kind == .random ? "shuffle" : "arrow.clockwise",
                               action: model.reload)
                            .disabled(model.isLoading && model.pending?.appending != true)
                    }
                }
            }
            .navigationDestination(for: WallItem.self) { item in
                if reduceMotion {
                    GalleryPreview(item: item)
                } else {
                    GalleryPreview(item: item)
                        .navigationTransition(.zoom(sourceID: item.id, in: previewTransition))
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .task { await model.ensureLoaded() }
            .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var browsingContent: some View {
        if model.search != nil {
            feedScroll
                .refreshable { await model.refresh() }
                .searchable(text: $draft, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: "搜索 Wallhaven 壁纸")
                .onSubmit(of: .search) { model.submit(draft) }
                .onChange(of: draft) { previous, value in
                    if value.isEmpty && !previous.isEmpty { model.clearSearchIfNeeded() }
                }
                .scrollDismissesKeyboard(.interactively)
        } else if source?.kind == .json {
            feedScroll
                .refreshable { await model.refresh() }
                .searchable(text: $draft, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: "筛选本页图片地址")
                .scrollDismissesKeyboard(.interactively)
        } else if source != nil {
            feedScroll.refreshable { await model.refresh() }
        } else {
            feedScroll
        }
    }

    private var visibleItems: [WallItem] {
        guard let items = model.displayed?.items else { return [] }
        let filter = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source?.kind == .json, model.search == nil, !filter.isEmpty else { return items }
        return items.filter { $0.full.absoluteString.localizedCaseInsensitiveContains(filter) }
    }

    private var feedScroll: some View {
        let items = visibleItems
        return ScrollView {
            VStack(spacing: 16) {
                if !items.isEmpty {
                    if model.isLoading && model.pending?.appending != true {
                        ProgressView("正在更新壁纸…")
                    }
                    if source?.kind == .random, let item = items.first {
                        randomLink(to: item)
                    } else if availableWidth > 0 {
                        waterfall(items)
                    }
                    pagination
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, margin)
            .padding(.vertical, 12)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .scrollPosition($scrollPosition)
        .onChange(of: model.resetID) { scrollPosition.scrollTo(edge: .top) }
        .overlay { emptyState(hasVisibleItems: !items.isEmpty) }
        .alert("无法更新壁纸", isPresented: Binding(
            get: { model.displayed != nil && model.failure?.request.appending == false },
            set: { if !$0 { model.dismissFailure() } }
        ), presenting: model.failure) { failure in
            Button("重试") { model.retry(failure) }
            Button("好", role: .cancel) { }
        } message: { failure in
            Text(failure.message)
        }
    }

    private func waterfall(_ items: [WallItem]) -> some View {
        let width = max(1, min(availableWidth - 2 * margin, 1160))
        let count = typeSize.isAccessibilitySize || width < 280 ? 1 : min(5, max(2, Int((width + spacing) / 190)))
        let columnWidth = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        let columns = MasonryColumns.make(items: items, count: count, columnWidth: Double(columnWidth), spacing: Double(spacing))
        return HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(columns[column]) { entry in
                        NavigationLink(value: entry.item) {
                            AsyncImage(url: entry.item.thumb) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill().accessibilityIgnoresInvertColors()
                                case .failure:
                                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                                default:
                                    ProgressView()
                                }
                            }
                            .frame(width: columnWidth, height: columnWidth / CGFloat(entry.aspectRatio))
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                            .clipShape(.rect(cornerRadius: 10))
                            .matchedTransitionSource(id: entry.item.id, in: previewTransition)
                            .accessibilityHidden(true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("壁纸 \(entry.number)"))
                        .accessibilityValue(Text(entry.item.resolution ?? ""))
                    }
                }
                .frame(width: columnWidth)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func randomLink(to item: WallItem) -> some View {
        NavigationLink(value: item) {
            Group {
                if let randomPreview, randomPreview.url == item.id {
                    Image(decorative: randomPreview.image, scale: 1)
                        .resizable().scaledToFit().accessibilityIgnoresInvertColors()
                } else if randomPreviewFailed {
                    ContentUnavailableView("无法载入缩略图", systemImage: "photo.badge.exclamationmark")
                } else {
                    ProgressView("正在载入图片…").padding()
                }
            }
            .frame(maxWidth: 480, maxHeight: 680)
            .clipShape(.rect(cornerRadius: 10))
            .matchedTransitionSource(id: item.id, in: previewTransition)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("预览随机壁纸")
        .task(id: item.id) {
            randomPreviewFailed = false
            do {
                let image = try await GalleryImages.shared.read(item.thumb, maxPixel: 1200)
                try Task.checkCancellation()
                randomPreview = (item.id, image)
            } catch {
                if !Task.isCancelled { randomPreviewFailed = true }
            }
        }
    }

    @ViewBuilder
    private var pagination: some View {
        if model.search != nil {
            if model.pending?.appending == true {
                ProgressView("正在加载更多…").padding(.vertical, 12)
            } else if let failure = model.failure, failure.request.appending {
                VStack {
                    Text(failure.message).font(.footnote).foregroundStyle(.secondary)
                    Button("重试加载更多", systemImage: "arrow.clockwise") { model.retry(failure) }
                        .buttonStyle(.bordered)
                }
            } else if !model.isLoading && model.hasMore {
                Button("加载更多", systemImage: "arrow.down") { model.loadMore() }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 8)
                    .onScrollVisibilityChange(threshold: 0.6) { visible in
                        if visible { model.loadMore() }
                    }
            } else if !model.isLoading {
                Text("已浏览全部结果").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func emptyState(hasVisibleItems: Bool) -> some View {
        if source == nil {
            ContentUnavailableView {
                Label("接入图源", systemImage: "photo.stack")
            } description: {
                Text("选择已适配的网站，或接入自己的 HTTPS 图片接口。")
            } actions: {
                Button("浏览图源", action: manage).buttonStyle(.borderedProminent)
            }
        } else if !hasVisibleItems {
            if let failure = model.failure, model.displayed == nil {
                ContentUnavailableView {
                    Label("无法载入壁纸", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.message)
                } actions: {
                    Button("重试") { model.retry(failure) }.buttonStyle(.bordered)
                }
            } else if model.isLoading || model.displayed == nil {
                ProgressView("正在载入壁纸…")
            } else if model.search == nil, source?.kind == .json, model.displayed?.items.isEmpty == false {
                ContentUnavailableView.search(text: draft)
            } else if !model.appliedQuery.isEmpty {
                ContentUnavailableView.search(text: model.appliedQuery)
            } else {
                ContentUnavailableView("暂无壁纸", systemImage: "photo.on.rectangle",
                                       description: Text("下拉刷新，或切换其他图源。"))
            }
        }
    }

    private var sourceMenu: some View {
        Menu("图源", systemImage: "network") {
            Section {
                Picker("当前图源", selection: Binding(
                    get: { source?.id ?? SiteCatalog.wallhaven.id },
                    set: { id in if let candidate = sources.first(where: { $0.id == id }) { select(candidate) } }
                )) {
                    ForEach(sources) { candidate in
                        Text(candidate.name).tag(candidate.id)
                    }
                }
                .pickerStyle(.inline)
            }
            Button("管理图源", systemImage: "slider.horizontal.3", action: manage)
        }
    }
}
