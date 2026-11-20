import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FeedKind: String, Codable, CaseIterable, Sendable { case json, random }

struct FeedSource: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name = "新图源"
    var endpoint = ""
    var kind: FeedKind = .json
    var listPath = ""
    var imagePath = "url"
    var thumbPath = ""
}

struct WallItem: Identifiable, Hashable, Sendable {
    let full: URL
    let thumb: URL
    let resolution: String?
    var id: URL { full }
}

struct FeedPage: Sendable {
    let items: [WallItem]
    let lastPage: Int?
}

private struct FeedError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// Inspect every Location before issuing the next request, including CDN hops.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum FeedLoader {
    private static func https(_ text: String?, relativeTo base: URL? = nil) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains("\\"),
              let url = URL(string: text, relativeTo: base)?.absoluteURL,
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func load(_ source: FeedSource) async throws -> [WallItem] {
        try await loadPage(source).items
    }

    static func loadPage(_ source: FeedSource, paged: Bool = false) async throws -> FeedPage {
        try Task.checkCancellation()
        guard var url = https(source.endpoint) else { throw FeedError("图源需要不含用户名和密码的 HTTPS 地址。") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let limit = (source.kind == .json ? 2 : 16) * 1024 * 1024
        for hop in 0...5 {
            try Task.checkCancellation()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue(source.kind == .json ? "application/json" : "image/*", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw FeedError("不是 HTTP 响应。") }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard hop < 5, let next = https(http.value(forHTTPHeaderField: "Location"), relativeTo: url) else {
                    throw FeedError("图源重定向不安全、无效或次数过多。")
                }
                url = next
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw FeedError("图源返回 HTTP \(http.statusCode)。") }
            guard response.expectedContentLength <= Int64(limit) else { throw FeedError("响应超出大小限制。") }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw FeedError("响应超出大小限制。") }
                if data.count.isMultiple(of: 65536) { try Task.checkCancellation() }
                data.append(byte)
            }
            try Task.checkCancellation()
            switch source.kind {
            case .json: return try parsePage(data, source, url, paged: paged)
            case .random:
                let file = try await PictureCache.shared.store(data)
                return FeedPage(items: [WallItem(full: file, thumb: file, resolution: nil)], lastPage: nil)
            }
        }
        throw FeedError("图源重定向次数过多。")
    }

    // An empty path selects the current value; decimal components can index arrays.
    private static func value(_ root: Any, _ path: String) -> Any? {
        var current = root
        for key in path.split(separator: ".") {
            if let object = current as? [String: Any], let next = object[String(key)] { current = next }
            else if let array = current as? [Any], let i = Int(key), array.indices.contains(i) { current = array[i] }
            else { return nil }
        }
        return current
    }

    private static func parsePage(_ data: Data, _ source: FeedSource, _ base: URL, paged: Bool) throws -> FeedPage {
        let root = try JSONSerialization.jsonObject(with: data)
        let lastPage = paged ? (value(root, "meta.last_page") as? Int).map { max(1, $0) } : nil
        guard let rows = value(root, source.listPath) as? [Any] else { throw FeedError("列表路径没有指向 JSON 数组。") }
        var seen = Set<URL>(), result = [WallItem]()
        for row in rows {
            try Task.checkCancellation()
            let image = (row as? String) ?? (value(row, source.imagePath) as? String)
            guard let full = https(image, relativeTo: base), seen.insert(full).inserted else { continue }
            let thumb = https(value(row, source.thumbPath) as? String, relativeTo: base) ?? full
            let resolution: String? = if paged,
                let width = value(row, "dimension_x") as? Int, width > 0,
                let height = value(row, "dimension_y") as? Int, height > 0 {
                "\(width) × \(height)"
            } else { nil }
            result.append(WallItem(full: full, thumb: thumb, resolution: resolution))
            if result.count == 200 { break }
        }
        if !rows.isEmpty && result.isEmpty { throw FeedError("列表中没有可用的 HTTPS 图片，请检查原图路径。") }
        return FeedPage(items: result, lastPage: lastPage)
    }
}

private actor PictureCache {
    static let shared = PictureCache()

    func store(_ data: Data) throws -> URL {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String), type.conforms(to: .image),
              let ext = type.preferredFilenameExtension else { throw FeedError("随机接口未返回完整的图片。") }
        let fm = FileManager.default
        let root = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = root.appendingPathComponent("WallFlow-Random", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys))
        var entries: [(url: URL, size: Int, date: Date)] = []
        for file in files {
            let info = try file.resourceValues(forKeys: keys)
            if info.isRegularFile == true {
                entries.append((file, info.fileSize ?? 0, info.contentModificationDate ?? .distantPast))
            }
        }
        var count = entries.count + 1
        var total = entries.reduce(data.count) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if count <= 48 && total <= 96 * 1024 * 1024 { break }
            try fm.removeItem(at: entry.url)
            count -= 1
            total -= entry.size
        }
        let file = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: file, options: .atomic)
        return file
    }
}
