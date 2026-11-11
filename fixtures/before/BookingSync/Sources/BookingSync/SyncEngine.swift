import Foundation

/// Periodically refreshes availability for the watched listings.
public final class SyncEngine {
    private let cache: AvailabilityCache
    private var watched: [Int] = []
    public private(set) var completedPasses = 0
    public var onPass: ((Int) -> Void)?

    public init(cache: AvailabilityCache) { self.cache = cache }

    public func watch(_ listingIDs: [Int]) { watched = listingIDs }

    /// Starts polling forever.
    public func start() {
        Task.detached {
            while true {
                await self.syncOnce()
                try? await Task.sleep(nanoseconds: UInt64(SyncConfig.pollInterval * 1_000_000_000))
            }
        }
    }

    public func syncOnce() async {
        syncAttempts += 1
        for id in watched.prefix(syncBatchSize) {
            await cache.invalidate(id)
            _ = try? await cache.availability(for: id)
        }
        completedPasses += 1
        onPass?(completedPasses)
    }
}
