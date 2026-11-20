import Foundation
import Observation

@Observable @MainActor
final class GalleryFeedModel {
    struct Request: Equatable {
        let query: String
        let page: Int
        var appending = false
    }

    struct Snapshot {
        let query: String
        let page: Int
        let items: [WallItem]
        let hasMore: Bool
    }

    struct Failure {
        let request: Request
        let message: String
    }

    let search: WallhavenSearch?
    private let source: FeedSource?
    private var intended: Request
    private(set) var displayed: Snapshot?
    private(set) var pending: Request?
    private(set) var failure: Failure?
    private(set) var resetID = UUID()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation: UUID?

    init(source: FeedSource?) {
        let search = WallhavenSearch(source)
        self.source = source
        self.search = search
        intended = Request(query: search?.initialQuery ?? "", page: search?.initialPage ?? 1)
    }

    var isLoading: Bool { pending != nil }
    var appliedQuery: String { displayed?.query ?? intended.query }
    var hasMore: Bool { displayed?.hasMore == true }

    func ensureLoaded() async {
        guard displayed == nil, failure == nil else { return }
        await start(intended)?.value
    }

    func refresh() async {
        await start(reloadRequest)?.value
    }

    func reload() { start(reloadRequest) }

    func retry(_ failure: Failure) { start(failure.request) }

    func dismissFailure() { failure = nil }

    func submit(_ draft: String) {
        guard search != nil else { return }
        start(Request(query: draft.trimmingCharacters(in: .whitespacesAndNewlines), page: 1))
    }

    func clearSearchIfNeeded() {
        guard !(pending?.query ?? displayed?.query ?? intended.query).isEmpty else { return }
        submit("")
    }

    func loadMore() {
        guard search != nil, let displayed, displayed.hasMore, displayed.page < Int.max, !isLoading, failure == nil else { return }
        start(Request(query: displayed.query, page: displayed.page + 1, appending: true))
    }

    func cancel() {
        operation?.cancel()
        operation = nil
        generation = nil
        pending = nil
    }

    private var reloadRequest: Request {
        guard let displayed else { return intended }
        return Request(query: displayed.query, page: displayed.query == search?.initialQuery ? search?.initialPage ?? 1 : 1)
    }

    @discardableResult
    private func start(_ request: Request) -> Task<Void, Never>? {
        guard let source else { return nil }
        if pending == request, let operation { return operation }
        operation?.cancel()
        let token = UUID()
        generation = token
        if !request.appending { intended = request }
        pending = request
        failure = nil
        let operation = Task { [weak self, search] in
            do {
                var input = source
                if let search {
                    input.endpoint = try search.endpoint(query: request.query, page: request.page)
                }
                let feed = try await FeedLoader.loadPage(input, paged: search != nil)
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.apply(feed, for: request)
                self.finish()
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.failure = Failure(request: request, message: error.localizedDescription)
                self.finish()
            }
        }
        self.operation = operation
        return operation
    }

    private func apply(_ feed: FeedPage, for request: Request) {
        var items = request.appending ? displayed?.items ?? [] : []
        var seen = Set(items.map(\.id))
        let additions = feed.items.filter { seen.insert($0.id).inserted }
        items.append(contentsOf: additions)
        let hasMore = search != nil && !additions.isEmpty && request.page < Int.max
            && (feed.lastPage.map { request.page < $0 } ?? true)
        displayed = Snapshot(query: request.query, page: request.page, items: items, hasMore: hasMore)
        if !request.appending { resetID = UUID() }
    }

    private func finish() {
        operation = nil
        generation = nil
        pending = nil
    }
}
