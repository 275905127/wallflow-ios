import Foundation

enum SiteCatalog {
    // Persisted selections refer to these IDs; keep them stable across launches.
    static var sources: [FeedSource] {
        [
            FeedSource(
                id: UUID(uuidString: "E653C596-5B1F-48D9-9B21-DCB26D78E5F9")!,
                name: "Wallhaven · SFW 最新",
                endpoint: "https://wallhaven.cc/api/v1/search?purity=100&sorting=date_added&order=desc",
                kind: .json,
                listPath: "data",
                imagePath: "path",
                thumbPath: "thumbs.large"
            ),
            FeedSource(
                id: UUID(uuidString: "0430E69F-B01C-45BA-89F2-D25892895467")!,
                name: "Lorem Picsum · 随机摄影",
                endpoint: "https://picsum.photos/1080/1920",
                kind: .random,
                listPath: "",
                imagePath: "",
                thumbPath: ""
            )
        ]
    }
}
