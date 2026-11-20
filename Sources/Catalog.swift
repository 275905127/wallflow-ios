import Foundation

enum SiteCatalog {
    // Keep the legacy preset's UUID and fields for selection and migration.
    static let legacyWallhaven = FeedSource(
        id: UUID(uuidString: "E653C596-5B1F-48D9-9B21-DCB26D78E5F9")!,
        name: "Wallhaven · SFW 最新",
        endpoint: "https://wallhaven.cc/api/v1/search?purity=100&sorting=date_added&order=desc",
        kind: .json,
        listPath: "data",
        imagePath: "path",
        thumbPath: "thumbs.large"
    )
    static let wallhaven: FeedSource = {
        var source = legacyWallhaven
        source.name = "Wallhaven"
        source.thumbPath = "thumbs.original"
        return source
    }()
    static let sources = [wallhaven]
}
