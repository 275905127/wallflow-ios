import Foundation
import Observation

@Observable @MainActor
final class GalleryFeedModel {
    struct Request: Equatable {
        var query: String
        var page: Int
    }

    struct Snapshot {
        let request: Request
        let feed: FeedPage
    }

    struct Failure: Identifiable {
        let id: UUID
        let request: Request
        let message: String
    }

    let search: WallhavenSearch?
    private let source: FeedSource?
    private var intended: Request
    private(set) var displayed: Snapshot?
    private(set) var pending: Request?
    private(set) var failure: Failure?
    private(set) var cancelled = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation: UUID?

    init(source: FeedSource?) {
        let search = WallhavenSearch(source)
        self.source = source
        self.search = search
        intended = Request(query: search?.initialQuery ?? "", page: search?.initialPage ?? 1)
    }

    var isLoading: Bool { pending != nil }
    var appliedQuery: String { displayed?.request.query ?? intended.query }
    var currentPage: Int { displayed?.request.page ?? intended.page }
    var lastPage: Int? { displayed?.feed.lastPage }
    var canGoBack: Bool { !isLoading && currentPage > 1 }
    var canGoForward: Bool {
        guard !isLoading, let displayed, currentPage < Int.max else { return false }
        return lastPage.map { currentPage < $0 } ?? !displayed.feed.items.isEmpty
    }

    func ensureLoaded() async {
        guard displayed == nil, failure == nil, !cancelled else { return }
        await start(intended)?.value
    }

    func refresh() async {
        if let operation { await operation.value; return }
        await start(displayed?.request ?? intended)?.value
    }

    func reload() { start(displayed?.request ?? intended) }

    func retry(_ failure: Failure) { start(failure.request) }

    func dismissFailure() { failure = nil }

    func submit(_ draft: String) {
        guard search != nil else { return }
        start(Request(query: draft.trimmingCharacters(in: .whitespacesAndNewlines), page: 1))
    }

    func clearSearchIfNeeded() {
        guard !(pending?.query ?? displayed?.request.query ?? intended.query).isEmpty else { return }
        submit("")
    }

    func turnPage(_ offset: Int) {
        guard search != nil else { return }
        let allowed = offset == -1 ? canGoBack : offset == 1 && canGoForward
        guard allowed else { return }
        let base = displayed?.request ?? intended
        start(Request(query: base.query, page: base.page + offset))
    }

    func cancel(userInitiated: Bool = false) {
        guard operation != nil else { return }
        operation?.cancel()
        operation = nil
        generation = nil
        pending = nil
        if let displayed { intended = displayed.request }
        cancelled = userInitiated && displayed == nil
    }

    @discardableResult
    private func start(_ request: Request) -> Task<Void, Never>? {
        guard var source else { return nil }
        if pending == request, let operation { return operation }
        operation?.cancel()
        let token = UUID()
        generation = token
        intended = request
        pending = request
        failure = nil
        cancelled = false
        let operation = Task { [weak self, search] in
            do {
                if let search {
                    source.endpoint = try search.endpoint(query: request.query, page: request.page)
                }
                let feed = try await FeedLoader.loadPage(source, paged: search != nil)
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.displayed = Snapshot(request: request, feed: feed)
                self.finish()
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.failure = Failure(id: token, request: request, message: error.localizedDescription)
                self.finish()
            }
        }
        self.operation = operation
        return operation
    }

    private func finish() {
        operation = nil
        generation = nil
        pending = nil
    }
}
