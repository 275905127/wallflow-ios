import Foundation

struct WallhavenSearch {
    let components: URLComponents
    let initialQuery: String
    let initialPage: Int

    init?(_ source: FeedSource?) {
        guard let source, source.kind == .json,
              let parts = URLComponents(string: source.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "wallhaven.cc",
              parts.percentEncodedPath == "/api/v1/search", parts.user == nil, parts.password == nil else { return nil }
        components = parts
        let parameters = parts.queryItems ?? []
        initialQuery = parameters.first { $0.name == "q" }?.value ?? ""
        initialPage = max(1, Int(parameters.first { $0.name == "page" }?.value ?? "") ?? 1)
    }

    func endpoint(query: String, page: Int) throws -> String {
        var parts = components
        var parameters = parts.percentEncodedQueryItems ?? []
        parameters.removeAll { ["q", "page"].contains($0.name.removingPercentEncoding ?? $0.name) }
        if !query.isEmpty {
            // Wallhaven's query parser treats a literal '+' as a space.
            var encoder = URLComponents()
            encoder.queryItems = [URLQueryItem(name: "q", value: query)]
            guard var item = encoder.percentEncodedQueryItems?.first else { throw URLError(.badURL) }
            item.value = item.value?.replacingOccurrences(of: "+", with: "%2B")
            parameters.append(item)
        }
        parameters.append(URLQueryItem(name: "page", value: String(page)))
        parts.percentEncodedQueryItems = parameters
        guard let url = parts.url else { throw URLError(.badURL) }
        return url.absoluteString
    }
}
