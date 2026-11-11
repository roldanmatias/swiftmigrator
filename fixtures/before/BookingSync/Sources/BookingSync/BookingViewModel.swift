import Combine
import Foundation

public final class BookingViewModel: ObservableObject {
    @Published public private(set) var snapshot: AvailabilitySnapshot?
    @Published public private(set) var errorMessage: String?

    private let listingID: Int
    private let cache: AvailabilityCache
    private let feed: AvailabilityFeed
    private var feedToken: UUID?

    public init(listingID: Int, cache: AvailabilityCache, feed: AvailabilityFeed) {
        self.listingID = listingID
        self.cache = cache
        self.feed = feed
        feedToken = feed.addHandler { [weak self] snapshot in
            guard snapshot.listingID == listingID else { return }
            DispatchQueue.main.async { self?.snapshot = snapshot }
        }
    }

    deinit {
        if let feedToken { feed.removeHandler(feedToken) }
    }

    public func load(completion: (() -> Void)? = nil) {
        Task {
            do {
                let value = try await cache.availability(for: listingID)
                DispatchQueue.main.async { self.snapshot = value; completion?() }
            } catch {
                DispatchQueue.main.async { self.errorMessage = "Couldn't load availability"; completion?() }
            }
        }
    }
}
