import Foundation
import Observation

@Observable @MainActor final class SourceLibrary {
    private enum Key {
        static let sources = "sources"
        static let current = "current"
    }

    private let defaults: UserDefaults
    private(set) var custom: [FeedSource]
    private var current: UUID?

    var sources: [FeedSource] { SiteCatalog.sources + custom }

    // Preserve the optional API used by Gallery, even though there is always a fallback.
    var selected: FeedSource? {
        sources.first { $0.id == current } ?? SiteCatalog.wallhaven
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedSources = defaults.data(forKey: Key.sources)
            .flatMap { try? JSONDecoder().decode([FeedSource].self, from: $0) } ?? []
        let savedSelection = defaults.string(forKey: Key.current).flatMap(UUID.init(uuidString:))
        let wallhaven = SiteCatalog.wallhaven
        var migratedSelection = savedSelection
        var usedIDs = Set(savedSources.map(\.id))

        custom = savedSources.compactMap { source in
            guard source.id == wallhaven.id else { return source }
            // The old preset was copied into the personal list when enabled.
            guard source != SiteCatalog.legacyWallhaven, source != wallhaven else { return nil }

            var personal = source
            repeat {
                personal.id = UUID()
            } while !usedIDs.insert(personal.id).inserted
            if migratedSelection == source.id {
                migratedSelection = personal.id
            }
            return personal
        }
        current = migratedSelection

        if custom != savedSources { persistCustom() }
        if migratedSelection != savedSelection, let migratedSelection {
            defaults.set(migratedSelection.uuidString, forKey: Key.current)
        }
    }

    func select(_ source: FeedSource) {
        guard sources.contains(where: { $0.id == source.id }) else { return }
        current = source.id
        defaults.set(source.id.uuidString, forKey: Key.current)
    }

    func save(_ source: FeedSource) {
        guard source.id != SiteCatalog.wallhaven.id else { return }
        if let index = custom.firstIndex(where: { $0.id == source.id }) {
            custom[index] = source
        } else {
            custom.append(source)
        }
        persistCustom()
        select(source)
    }

    func remove(_ source: FeedSource) {
        guard let index = custom.firstIndex(where: { $0.id == source.id }) else { return }
        custom.remove(at: index)
        if current == source.id {
            current = nil
            defaults.removeObject(forKey: Key.current)
        }
        persistCustom()
    }

    private func persistCustom() {
        if let data = try? JSONEncoder().encode(custom) {
            defaults.set(data, forKey: Key.sources)
        }
    }
}
