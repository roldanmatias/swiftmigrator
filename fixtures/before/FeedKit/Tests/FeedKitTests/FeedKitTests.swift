import XCTest
import LegacyNetworking
@testable import FeedKit

final class FeedKitTests: XCTestCase {
    override func setUp() {
        FeedCache.shared.removeAll()
    }

    func testFetchArticlesDecodesAndCaches() {
        let cache = FeedCache()
        let service = FeedService(client: HTTPClient(), cache: cache)
        let expectation = expectation(description: "fetch")

        service.fetchArticles(page: 1) { result in
            XCTAssertEqual(try? result.get().count, 2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(cache.articles(forPage: 1)?.first?.title, "Swift 6 is here")
    }

    func testFetchArticlesInvalidJSONFails() {
        let service = FeedService(client: HTTPClient(stubbedBody: Data("oops".utf8)), cache: FeedCache())
        let expectation = expectation(description: "fetch")

        service.fetchArticles(page: 1) { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error, .decoding)
            } else {
                XCTFail("Expected failure")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testViewModelLoadPublishesArticles() {
        let viewModel = FeedViewModel(service: FeedService(client: HTTPClient(), cache: FeedCache()))
        let expectation = expectation(description: "load")

        viewModel.load { expectation.fulfill() }

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(viewModel.articles.map(\.id), [1, 2])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testMarkReadIncrementsCount() async {
        let tracker = ReadingTracker()
        await tracker.markRead(Article(id: 1, title: "A"))
        let count = await tracker.stats.readCount
        XCTAssertEqual(count, 1)
    }

    func testPrefetchReturnsAllLoadedImages() async {
        let urls = (0..<20).map { URL(string: "https://example.com/img/\($0).png")! }
        let prefetcher = ImagePrefetcher { url in Data(url.lastPathComponent.utf8) }

        let results = await prefetcher.prefetch(urls)

        XCTAssertEqual(results.count, 20)
    }
}
