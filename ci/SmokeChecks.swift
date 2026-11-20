import Foundation

@main
struct SmokeChecks {
    @MainActor static func main() throws {
        try checkLibrary()
        try checkColumns()
        print("Default source, legacy migration, and masonry checks passed")
    }

    @MainActor private static func checkLibrary() throws {
        let domain = "WallFlow.Smoke.\(UUID())"
        let defaults = try require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let builtIn = SiteCatalog.wallhaven
        let original = SourceLibrary(defaults: defaults)
        precondition(original.sources == [builtIn] && original.selected == builtIn)
        original.remove(builtIn)
        precondition(original.sources == [builtIn])

        let personal = FeedSource(name: "个人随机图源", endpoint: "https://picsum.photos/1080/1920", kind: .random)
        defaults.set(try JSONEncoder().encode([SiteCatalog.legacyWallhaven, personal]), forKey: "sources")
        defaults.set(personal.id.uuidString, forKey: "current")
        let migrated = SourceLibrary(defaults: defaults)
        precondition(migrated.sources == [builtIn, personal] && migrated.selected == personal)
        migrated.remove(personal)
        precondition(migrated.selected == builtIn)

        var edited = SiteCatalog.legacyWallhaven
        edited.name = "修改过的旧 Wallhaven"
        defaults.set(try JSONEncoder().encode([edited]), forKey: "sources")
        defaults.set(edited.id.uuidString, forKey: "current")
        let restored = SourceLibrary(defaults: defaults)
        let restoredEdit = try require(restored.custom.first)
        precondition(restoredEdit.id != builtIn.id && restoredEdit.name == edited.name)
        precondition(restored.selected == restoredEdit && restored.sources.count == 2)
        precondition(SourceLibrary(defaults: defaults).selected == restoredEdit)
    }

    private static func checkColumns() throws {
        let items = try [ImageDimensions(width: 600, height: 1000), ImageDimensions(width: 1200, height: 600), nil].enumerated().map { index, dimensions in
            let url = try require(URL(string: "https://example.org/\(index).jpg"))
            return WallItem(full: url, thumb: url, dimensions: dimensions)
        }
        let first = MasonryColumns.make(items: Array(items.prefix(2)), count: 2, columnWidth: 180, spacing: 8)
        let appended = MasonryColumns.make(items: items, count: 2, columnWidth: 180, spacing: 8)
        precondition(appended.map { $0.map(\.number) } == [[1], [2, 3]])
        precondition(zip(first, appended).allSatisfy { $0.0.map(\.id) == Array($0.1.prefix($0.0.count)).map(\.id) })
        precondition(appended[0][0].aspectRatio < appended[1][0].aspectRatio)
        precondition(MasonryColumns.make(items: items, count: 1, columnWidth: 350, spacing: 8)[0].map(\.id) == items.map(\.id))
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw URLError(.badURL) }
        return value
    }
}
