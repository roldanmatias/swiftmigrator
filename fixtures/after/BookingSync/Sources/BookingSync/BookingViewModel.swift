import Foundation
import Observation

/// R6: UI state → `@MainActor`, manual `DispatchQueue.main.async` removed.
/// `ObservableObject` → `@Observable` (approved; the deployment target already
/// allows it). R13: `@preconcurrency @MainActor` for existing clients.
@preconcurrency @MainActor
@Observable
public final class BookingViewModel {
    public private(set) var snapshot: AvailabilitySnapshot?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let listingID: Int
    @ObservationIgnored private let cache: AvailabilityCache
    @ObservationIgnored private let feed: AvailabilityFeed
    /// R23: the subscription is a task the model owns, cancelled in `deinit`.
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    public init(listingID: Int, cache: AvailabilityCache, feed: AvailabilityFeed) {
        self.listingID = listingID
        self.cache = cache
        self.feed = feed
        // Same behavior as before (pushes update `snapshot` automatically), now
        // through a stream. `[weak self]` per element, so the model can deinit.
        let updates = feed.updates(for: listingID)
        updatesTask = Task { [weak self] in
            for await snapshot in updates {
                self?.snapshot = snapshot
            }
        }
    }

    /// R9: `deinit` is nonisolated; it only touches its own Sendable stored property.
    deinit { updatesTask?.cancel() }

    public func load() async {
        do {
            snapshot = try await cache.availability(for: listingID)
        } catch {
            errorMessage = "Couldn't load availability"
        }
    }

    /// R13: kept for existing callers.
    @available(*, deprecated, message: "Use await load() instead")
    public func load(completion: (@MainActor () -> Void)? = nil) {
        Task {
            await load()
            completion?()
        }
    }
}
