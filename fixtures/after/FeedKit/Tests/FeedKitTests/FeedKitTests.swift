import Foundation
import Testing
import LegacyNetworking
@testable import FeedKit

@Suite("FeedService")
struct FeedServiceTests {
    @Test func fetchArticlesDecodesAndCaches() async throws {
        let cache = FeedCache()
        let service = FeedService(client: HTTPClient(), cache: cache)

        let articles = try await service.fetchArticles(page: 1)

        #expect(articles.count == 2)
        #expect(cache.articles(forPage: 1)?.first?.title == "Swift 6 is here")
    }

    @Test func fetchArticlesInvalidJSONFails() async {
        let service = FeedService(client: HTTPClient(stubbedBody: Data("oops".utf8)), cache: FeedCache())

        await #expect(throws: FeedError.decoding) {
            try await service.fetchArticles(page: 1)
        }
    }

    @available(*, deprecated)
    @Test func legacyCallbackAPIStillWorks() async throws {
        let service = FeedService(client: HTTPClient(), cache: FeedCache())

        let result = await withCheckedContinuation { continuation in
            service.fetchArticles(page: 1) { continuation.resume(returning: $0) }
        }

        #expect(try result.get().map(\.id) == [1, 2])
    }
}

@Suite("FeedViewModel")
@MainActor
struct FeedViewModelTests {
    @Test func loadPublishesArticles() async {
        let viewModel = FeedViewModel(service: FeedService(client: HTTPClient(), cache: FeedCache()))

        await viewModel.load()

        #expect(viewModel.articles.map(\.id) == [1, 2])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadFailureSetsErrorMessage() async {
        let client = HTTPClient(stubbedBody: Data("oops".utf8))
        let viewModel = FeedViewModel(service: FeedService(client: client, cache: FeedCache()))

        await viewModel.load()

        #expect(viewModel.articles.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }
}

@Suite("ReadingTracker")
struct ReadingTrackerTests {
    @Test func markReadIncrementsCount() async {
        let tracker = ReadingTracker()
        await tracker.markRead(Article(id: 1, title: "A"))
        #expect(await tracker.stats.readCount == 1)
    }

    /// Regression test for the lost-update bug (read-modify-write across `await`s).
    @Test func concurrentMarkReadDoesNotLoseUpdates() async {
        let tracker = ReadingTracker()

        await withTaskGroup(of: Void.self) { group in
            for id in 0..<100 {
                group.addTask { await tracker.markRead(Article(id: id, title: "\(id)")) }
            }
        }

        #expect(await tracker.stats.readCount == 100)
    }
}

@Suite("ImagePrefetcher")
struct ImagePrefetcherTests {
    private let urls = (0..<20).map { URL(string: "https://example.com/img/\($0).png")! }

    @Test func prefetchReturnsAllLoadedImages() async {
        let prefetcher = ImagePrefetcher { url in Data(url.lastPathComponent.utf8) }

        let results = await prefetcher.prefetch(urls)

        #expect(results.count == 20)
    }

    @Test(arguments: [1, 3, 6])
    func prefetchRespectsConcurrencyLimit(limit: Int) async {
        let gauge = InFlightGauge()
        let prefetcher = ImagePrefetcher(maxConcurrentTasks: limit) { url in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await gauge.exit()
            return Data(url.lastPathComponent.utf8)
        }

        let results = await prefetcher.prefetch(urls)

        #expect(results.count == 20)
        #expect(await gauge.peak <= limit)
    }
}

private actor InFlightGauge {
    private(set) var peak = 0
    private var current = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func exit() {
        current -= 1
    }
}
