import SwiftUI

@main struct WallFlowApp: App {
    var body: some Scene { WindowGroup { Gallery() } }
}

@Observable @MainActor final class SourceLibrary {
    private(set) var custom: [FeedSource]
    private var current: UUID?
    var sources: [FeedSource] { custom }
    var selected: FeedSource? { sources.first { $0.id == current } ?? custom.first }
    init() {
        let defaults = UserDefaults.standard
        custom = (defaults.data(forKey: "sources").flatMap { try? JSONDecoder().decode([FeedSource].self, from: $0) }) ?? []
        current = defaults.string(forKey: "current").flatMap { UUID(uuidString: $0) }
    }
    func select(_ s: FeedSource) { current = s.id; UserDefaults.standard.set(s.id.uuidString, forKey: "current") }
    func save(_ s: FeedSource) {
        if let index = custom.firstIndex(where: { $0.id == s.id }) { custom[index] = s } else { custom.append(s) }
        persist(); select(s)
    }
    func remove(_ s: FeedSource) { custom.removeAll { $0.id == s.id }; if current == s.id { current = nil; UserDefaults.standard.removeObject(forKey: "current") }; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: "sources") } }
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

    private var availablePresets: [FeedSource] {
        let savedIDs = Set(library.sources.map(\.id))
        return SiteCatalog.sources.filter { !savedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("我的图源") {
                    if library.sources.isEmpty {
                        ContentUnavailableView(
                            "还没有图源", systemImage: "photo.on.rectangle",
                            description: Text("可加入下方的已适配网站，或添加自己的 HTTPS 接口。")
                        )
                    }
                    ForEach(library.sources) { source in
                        ManagedSourceRow(
                            source: source,
                            isSelected: library.selected?.id == source.id,
                            onSelect: {
                                library.select(source)
                                onSelection()
                            },
                            onEdit: { editor = EditorRequest(source: source, isNew: false) },
                            onRemove: { library.remove(source) }
                        )
                    }
                }
                let presets = availablePresets
                if !presets.isEmpty {
                    Section {
                        ForEach(presets) { site in
                            Button {
                                library.save(site)
                                onSelection()
                            } label: {
                                SourceRowLabel(source: site, symbol: "plus.circle")
                            }
                        }
                    } header: {
                        Text("已适配的网站")
                    } footer: {
                        Text("点按网站以加入「我的图源」并选用。")
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
            .sheet(item: $editor, onDismiss: {
                guard openGalleryAfterSaving else { return }
                openGalleryAfterSaving = false
                onSelection()
            }) { request in
                SourceEditor(source: request.source, isNew: request.isNew) { updated in
                    library.save(updated)
                    openGalleryAfterSaving = true
                    editor = nil
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
