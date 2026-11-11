import Foundation
import LegacyCalendarAPI

/// Caches availability per listing. Callers hit it concurrently from every screen.
public actor AvailabilityCache {
    private let client: CalendarClient
    private var cache: [Int: AvailabilitySnapshot] = [:]
    public private(set) var fetchCount = 0

    public init(client: CalendarClient) { self.client = client }

    public func availability(for listingID: Int) async throws -> AvailabilitySnapshot {
        if let cached = cache[listingID] { return cached }
        fetchCount += 1
        let raw = try await withCheckedThrowingContinuation { continuation in
            client.fetchAvailability(listingID: listingID) { result in
                continuation.resume(with: result)
            }
        }
        let snapshot = AvailabilitySnapshot(listingID: raw.listingID, freeNights: Set(raw.freeNights))
        cache[listingID] = snapshot
        return snapshot
    }

    public func invalidate(_ listingID: Int) { cache[listingID] = nil }
}
