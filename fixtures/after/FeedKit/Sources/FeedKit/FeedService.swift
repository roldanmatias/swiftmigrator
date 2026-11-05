import Foundation
// LegacyNetworking has not adopted Swift concurrency yet: downgrade its diagnostics.
@preconcurrency import LegacyNetworking

// `@unchecked Sendable` (retroactive, from an unmigrated module): HTTPClient only holds
// immutable state (`let stubbedBody`) and does its work on a global queue.
// Remove once LegacyNetworking ships its own Sendable annotations.
extension HTTPClient: @unchecked Sendable {}

/// `Sendable`: final, and only immutable `Sendable` stored properties.
public final class FeedService: Sendable {
    private let client: HTTPClient
    private let cache: FeedCache

    public init(client: HTTPClient = .shared, cache: FeedCache = .shared) {
        self.client = client
        self.cache = cache
    }

    // MARK: async API (preferred)

    public func fetchArticles(page: Int) async throws(FeedError) -> [Article] {
        // The continuation receives the Sendable `Result<[Article], FeedError>`,
        // never the non-Sendable `HTTPResponse` from LegacyNetworking.
        let result = await withCheckedContinuation { continuation in
            fetch(page: page) { continuation.resume(returning: $0) }   // resumed exactly once
        }
        return try result.get()
    }

    // MARK: Callback API (kept for source compatibility)

    /// `@preconcurrency` keeps clients that pass non-`@Sendable` closures compiling
    /// (warnings instead of errors) until they migrate.
    @preconcurrency
    @available(*, deprecated, message: "Use the async fetchArticles(page:) instead")
    public func fetchArticles(
        page: Int,
        completion: @escaping @Sendable (Result<[Article], FeedError>) -> Void
    ) {
        fetch(page: page, completion: completion)
    }

    // MARK: Helpers

    /// Converts the legacy, non-Sendable response into a Sendable result *inside* the callback.
    private func fetch(
        page: Int,
        completion: @escaping @Sendable (Result<[Article], FeedError>) -> Void
    ) {
        client.get(makeURL(page: page)) { result in
            switch result {
            case .success(let response):
                completion(self.decodeAndCache(response, page: page))
            case .failure:
                completion(.failure(.network))
            }
        }
    }

    private func makeURL(page: Int) -> URL {
        var components = URLComponents(
            url: FeedEndpoints.baseURL.appendingPathComponent("articles"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(feedPageSize)"),
        ]
        return components.url!
    }

    private func decodeAndCache(_ response: HTTPResponse, page: Int) -> Result<[Article], FeedError> {
        guard response.statusCode == 200,
              let articles = try? JSONDecoder().decode([Article].self, from: response.body)
        else {
            return .failure(.decoding)
        }
        cache.store(articles, forPage: page)
        return .success(articles)
    }
}
