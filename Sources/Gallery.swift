import SwiftUI

struct Gallery: View {
    @State private var library = SourceLibrary()
    @State private var selection: WallFlowTab = .gallery

    var body: some View {
        TabView(selection: $selection) {
            Tab("图库", systemImage: "photo.on.rectangle", value: WallFlowTab.gallery) {
                NavigationStack {
                    GalleryFeed(
                        source: library.selected,
                        sources: library.sources,
                        select: library.select,
                        manage: { selection = .sources }
                    )
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
