import SwiftUI

@main struct WallFlowApp: App {
    var body: some Scene { WindowGroup { Gallery() } }
}

struct SourceManager: View {
    private struct EditorRequest: Identifiable {
        let source: FeedSource
        let isNew: Bool
        var id: FeedSource.ID { source.id }
    }

    let library: SourceLibrary
    let onSelection: () -> Void
    @State private var editor: EditorRequest?
    @State private var openGalleryAfterSaving = false

    init(library: SourceLibrary, onSelection: @escaping () -> Void) {
        self.library = library
        self.onSelection = onSelection
    }

    var body: some View {
        let selectedID = library.selected?.id
        NavigationStack {
            List {
                Section("内置图源") {
                    ForEach(SiteCatalog.sources) { source in
                        SourceSelectionButton(source: source, isSelected: selectedID == source.id) {
                            select(source)
                        }
                    }
                }
                Section("我的图源") {
                    if library.custom.isEmpty {
                        Text("还没有个人图源。点按 + 添加 JSON 或随机图片接口。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.custom) { source in
                        ManagedSourceRow(
                            source: source,
                            isSelected: selectedID == source.id,
                            onSelect: { select(source) },
                            onEdit: { editor = EditorRequest(source: source, isNew: false) },
                            onRemove: { library.remove(source) }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("图源")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("添加图源", systemImage: "plus") {
                        editor = EditorRequest(source: FeedSource(name: ""), isNew: true)
                    }
                }
            }
            .sheet(item: $editor, onDismiss: finishEditing) { request in
                SourceEditor(source: request.source, isNew: request.isNew) { updated in
                    library.save(updated)
                    openGalleryAfterSaving = true
                    editor = nil
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func select(_ source: FeedSource) {
        library.select(source)
        onSelection()
    }

    private func finishEditing() {
        guard openGalleryAfterSaving else { return }
        openGalleryAfterSaving = false
        onSelection()
    }
}

struct ManagedSourceRow: View {
    let source: FeedSource
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        HStack {
            SourceSelectionButton(source: source, isSelected: isSelected, onSelect: onSelect)
                .contextMenu {
                    editAction
                    Button("删除", systemImage: "trash", role: .destructive, action: confirmRemoval)
                }

            Menu {
                editAction
                Button("删除", systemImage: "trash", role: .destructive, action: confirmRemoval)
            } label: {
                Label("管理 \(source.name)", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .confirmationDialog("删除图源？", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("删除图源", role: .destructive, action: onRemove)
                Button("取消", role: .cancel) { }
            } message: {
                Text("将从「我的图源」中移除“\(source.name)”。")
            }
        }
        .swipeActions(allowsFullSwipe: false) {
            // Don't animate the row away before the user confirms removal.
            Button("删除", systemImage: "trash", action: confirmRemoval)
                .tint(.red)
            editAction
        }
    }

    private var editAction: some View {
        Button("编辑", systemImage: "pencil", action: onEdit)
    }

    private func confirmRemoval() {
        confirmingRemoval = true
    }
}

private struct SourceSelectionButton: View {
    let source: FeedSource
    let isSelected: Bool
    let onSelect: () -> Void

    private var symbol: String {
        if isSelected { return "checkmark.circle.fill" }
        return source.kind == .json ? "list.bullet" : "shuffle"
    }

    var body: some View {
        Button(action: onSelect) {
            Label {
                VStack(alignment: .leading) {
                    Text(source.name)
                    Text(source.kind.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? Text("当前图源") : Text(""))
    }
}

extension FeedKind {
    var displayTitle: LocalizedStringKey {
        switch self {
        case .json: "JSON 列表"
        case .random: "随机图片"
        }
    }
}
