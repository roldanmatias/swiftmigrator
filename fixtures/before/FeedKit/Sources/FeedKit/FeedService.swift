import Foundation
import LegacyNetworking

/// Callback-based public API.
public final class FeedService {
    private let client: HTTPClient
    private let cache: FeedCache

    public init(client: HTTPClient = .shared, cache: FeedCache = .shared) {
        self.client = client
        self.cache = cache
    }

    public func fetchArticles(
        page: Int,
        completion: @escaping (Result<[Article], FeedError>) -> Void
    ) {
        requestCount += 1

        var components = URLComponents(
            url: FeedEndpoints.baseURL.appendingPathComponent("articles"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(feedPageSize)"),
        ]

        client.get(components.url!) { result in
            switch result {
            case .success(let response):
                guard response.statusCode == 200,
                      let articles = try? JSONDecoder().decode([Article].self, from: response.body)
                else {
                    completion(.failure(.decoding))
                    return
                }
                self.cache.store(articles, forPage: page)
                completion(.success(articles))
            case .failure:
                completion(.failure(.network))
            }
        }
    }
}
