import Foundation
@preconcurrency import LegacyCalendarAPI
import os

/// Fans out server pushes to every interested screen.
///
/// R2 / R24: `handlers` was mutated from callers and read from the SDK's
/// background queue with no synchronization (a real race). It now lives in an
/// `OSAllocatedUnfairLock` (Sendable, macOS 13 / iOS 16), so the class is
/// checked `Sendable` without `@unchecked`.
public final class AvailabilityFeed: CalendarClientDelegate, Sendable {
    public typealias Handler = @Sendable (AvailabilitySnapshot) -> Void

    private let handlers = OSAllocatedUnfairLock<[UUID: Handler]>(initialState: [:])

    public init(client: CalendarClient) {
        client.delegate = self
    }

    /// R22: one stream per subscriber; `onTermination` unregisters it, so a
    /// cancelled `.task {}` or a dropped stream can't leak a handler.
    public func updates(for listingID: Int? = nil) -> AsyncStream<AvailabilitySnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: AvailabilitySnapshot.self, bufferingPolicy: .bufferingNewest(1))
        let id = register { snapshot in
            if listingID == nil || snapshot.listingID == listingID { continuation.yield(snapshot) }
        }
        continuation.onTermination = { [weak self] _ in self?.removeHandler(id) }
        return stream
    }

    /// R13: kept for existing clients; the closure is now `@Sendable` because it's
    /// called on the SDK's background queue.
    @preconcurrency
    @available(*, deprecated, message: "Use updates(for:) instead")
    @discardableResult
    public func addHandler(_ handler: @escaping @Sendable (AvailabilitySnapshot) -> Void) -> UUID {
        register(handler)
    }

    public func removeHandler(_ id: UUID) {
        _ = handlers.withLock { $0.removeValue(forKey: id) }
    }

    public var handlerCount: Int { handlers.withLock { $0.count } }

    public func calendarClient(_ client: CalendarClient, didReceive change: RawChange) {
        let snapshot = AvailabilitySnapshot(listingID: change.listingID, freeNights: Set(change.freeNights))
        for handler in handlers.withLock({ Array($0.values) }) { handler(snapshot) }   // never call out under the lock
    }

    private func register(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        handlers.withLock { $0[id] = handler }
        return id
    }
}
