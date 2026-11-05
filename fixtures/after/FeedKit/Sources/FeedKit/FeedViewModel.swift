import Foundation
import Observation

/// Every caller is UI code, so the protocol itself is main-actor isolated.
@MainActor
public protocol FeedRenderer: AnyObject {
    func render(_ articles: [Article])
}

/// UI state: statically isolated to the main actor instead of `DispatchQueue.main.async`.
@MainActor
@Observable
public final class FeedViewModel: FeedRenderer {
    public private(set) var articles: [Article] = []
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: FeedService

    public init(service: FeedService = FeedService()) {
        self.service = service
    }

    public func load(page: Int = 1) async {
        do {
            render(try await service.fetchArticles(page: page))
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load: \(error)"
        }
    }

    @available(*, deprecated, message: "Use the async load(page:) instead")
    public func load(page: Int = 1, completion: (@MainActor () -> Void)? = nil) {
        Task {
            await load(page: page)
            completion?()
        }
    }

    public func render(_ articles: [Article]) {
        self.articles = articles
    }
}

/// Isolated to the main actor so the default value can call the `@MainActor` init.
@MainActor
public enum FeedPreviews {
    public static let viewModel = FeedViewModel()
}
