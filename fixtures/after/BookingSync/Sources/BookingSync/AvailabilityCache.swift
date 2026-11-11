import Foundation
@preconcurrency import LegacyCalendarAPI

// R10: CalendarClient documents "immutable after init, callbacks on an internal
// serial queue". Remove once LegacyCalendarAPI ships Sendable annotations.
extension CalendarClient: @unchecked Sendable {}

/// Caches availability per listing. Callers hit it concurrently from every screen.
public actor AvailabilityCache {
    private let client: CalendarClient
    private var cache: [Int: AvailabilitySnapshot] = [:]
    /// R21: concurrent callers for the same listing join one fetch.
    private var inFlight: [Int: Task<AvailabilitySnapshot, any Error>] = [:]
    public private(set) var fetchCount = 0

    public init(client: CalendarClient) { self.client = client }

    public func availability(for listingID: Int) async throws -> AvailabilitySnapshot {
        if let cached = cache[listingID] { return cached }
        if let running = inFlight[listingID] { return try await running.value }

        fetchCount += 1
        let client = self.client
        let task = Task { try await Self.fetch(listingID, from: client) }
        inFlight[listingID] = task                      // recorded before suspending
        defer { inFlight[listingID] = nil }

        let snapshot = try await task.value
        cache[listingID] = snapshot
        return snapshot
    }

    public func invalidate(_ listingID: Int) { cache[listingID] = nil }

    /// R4 + R14: convert the non-Sendable `RawAvailability` into a Sendable
    /// snapshot *inside* the callback, and resume exactly once.
    private static func fetch(_ listingID: Int, from client: CalendarClient) async throws -> AvailabilitySnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AvailabilitySnapshot, any Error>) in
            client.fetchAvailability(listingID: listingID) { @Sendable result in   // R5: called on a background queue
                continuation.resume(with: result.map {
                    AvailabilitySnapshot(listingID: $0.listingID, freeNights: Set($0.freeNights))
                })
            }
        }
    }
}
