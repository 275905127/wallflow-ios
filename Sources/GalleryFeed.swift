import SwiftUI

struct GalleryFeed: View {
    let source: FeedSource?
    let sources: [FeedSource]
    let select: (FeedSource) -> Void
    let manage: () -> Void

    @State private var model: GalleryFeedModel
    @State private var draft: String
    @Namespace private var previewTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        browsingList
            .navigationTitle("映壁")
            .navigationSubtitle(source?.name ?? "在线壁纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sourceMenu }
                if model.search != nil {
                    ToolbarItem(placement: .topBarTrailing) { pageMenu }
                } else if let source {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(source.kind == .random ? "换一张" : "刷新",
                               systemImage: source.kind == .random ? "shuffle" : "arrow.clockwise",
                               action: model.reload)
                            .disabled(model.isLoading)
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
    private var browsingList: some View {
        if model.search != nil {
            feedList
                .refreshable { await model.refresh() }
                .searchable(text: $draft, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: "搜索 Wallhaven 壁纸")
                .onSubmit(of: .search) { model.submit(draft) }
                .onChange(of: draft) { previous, value in
                    if value.isEmpty && !previous.isEmpty { model.clearSearchIfNeeded() }
                }
                .scrollDismissesKeyboard(.interactively)
        } else if source?.kind == .json {
            feedList
                .refreshable { await model.refresh() }
                .searchable(text: $draft, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: "筛选本页图片地址")
                .scrollDismissesKeyboard(.interactively)
        } else if source != nil {
            feedList.refreshable { await model.refresh() }
        } else {
            feedList
        }
    }

    private var visibleItems: [WallItem] {
        guard let items = model.displayed?.feed.items else { return [] }
        let filter = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source?.kind == .json, model.search == nil, !filter.isEmpty else { return items }
        return items.filter { $0.full.absoluteString.localizedCaseInsensitiveContains(filter) }
    }

    private var feedList: some View {
        let items = visibleItems
        let isRandom = source?.kind == .random
        return ScrollViewReader { proxy in
            List {
                if !items.isEmpty {
                    if model.isLoading {
                        ProgressView("正在更新壁纸…")
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            GalleryRow(item: item, name: isRandom ? "随机壁纸" : "壁纸 \(index + 1)",
                                       isRandom: isRandom, transition: previewTransition)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay { emptyState(hasVisibleItems: !items.isEmpty) }
            .onChange(of: model.displayed?.request) { previous, _ in
                if previous != nil, let id = items.first?.id {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            .alert("无法更新壁纸", isPresented: Binding(
                get: { model.displayed != nil && model.failure != nil },
                set: { if !$0 { model.dismissFailure() } }
            ), presenting: model.failure) { failure in
                Button("重试") { model.retry(failure) }
                Button("好", role: .cancel) { }
            } message: { failure in
                Text(failure.message)
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
            } else if model.isLoading || (model.displayed == nil && !model.cancelled) {
                ProgressView("正在载入壁纸…")
            } else if model.cancelled {
                ContentUnavailableView {
                    Label("已取消加载", systemImage: "pause.circle")
                } actions: {
                    Button("重新加载", action: model.reload).buttonStyle(.bordered)
                }
            } else if model.search == nil, source?.kind == .json, model.displayed?.feed.items.isEmpty == false {
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
            if !sources.isEmpty {
                Section("已接入的图源") {
                    ForEach(sources) { candidate in
                        Button {
                            select(candidate)
                        } label: {
                            if candidate.id == source?.id {
                                Label(candidate.name, systemImage: "checkmark")
                            } else {
                                Text(candidate.name)
                            }
                        }
                        .accessibilityAddTraits(candidate.id == source?.id ? .isSelected : [])
                    }
                }
            }
            Button("管理图源", systemImage: "slider.horizontal.3", action: manage)
        }
    }

    private var pageMenu: some View {
        Menu("分页", systemImage: "ellipsis.circle") {
            Section {
                Button("上一页", systemImage: "chevron.left") { model.turnPage(-1) }
                    .disabled(!model.canGoBack)
                Button("下一页", systemImage: "chevron.right") { model.turnPage(1) }
                    .disabled(!model.canGoForward)
            } header: {
                if let last = model.lastPage {
                    Text("第 \(model.currentPage) 页（共 \(last) 页）")
                } else {
                    Text("第 \(model.currentPage) 页")
                }
            }
            if model.isLoading {
                Button("取消加载", systemImage: "xmark.circle") { model.cancel(userInitiated: true) }
            } else {
                Button("刷新本页", systemImage: "arrow.clockwise", action: model.reload)
            }
        }
        .accessibilityValue(Text("第 \(model.currentPage) 页"))
    }
}
