import Combine
import Foundation

/// Non-isolated protocol whose only real callers are on the main thread.
public protocol FeedRenderer: AnyObject {
    func render(_ articles: [Article])
}

/// UI state guarded "by convention" with `DispatchQueue.main.async`.
public final class FeedViewModel: ObservableObject, FeedRenderer {
    @Published public private(set) var articles: [Article] = []
    @Published public private(set) var errorMessage: String?

    private let service: FeedService

    public init(service: FeedService = FeedService()) {
        self.service = service
    }

    public func load(page: Int = 1, completion: (() -> Void)? = nil) {
        service.fetchArticles(page: page) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let articles):
                    self?.render(articles)
                case .failure(let error):
                    self?.errorMessage = "Failed to load: \(error)"
                }
                completion?()
            }
        }
    }

    public func render(_ articles: [Article]) {
        self.articles = articles
    }
}

public enum FeedPreviews {
    /// Static instance built from a non-isolated context.
    public static let viewModel = FeedViewModel()
}
