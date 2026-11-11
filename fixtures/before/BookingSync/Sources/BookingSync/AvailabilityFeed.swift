import Foundation
import LegacyCalendarAPI

/// Fans out server pushes to every interested screen.
public final class AvailabilityFeed: CalendarClientDelegate {
    private let client: CalendarClient
    private var handlers: [UUID: (AvailabilitySnapshot) -> Void] = [:]

    public init(client: CalendarClient) {
        self.client = client
        client.delegate = self
    }

    @discardableResult
    public func addHandler(_ handler: @escaping (AvailabilitySnapshot) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    public func removeHandler(_ id: UUID) { handlers[id] = nil }

    public var handlerCount: Int { handlers.count }

    public func calendarClient(_ client: CalendarClient, didReceive change: RawChange) {
        let snapshot = AvailabilitySnapshot(listingID: change.listingID, freeNights: Set(change.freeNights))
        for handler in handlers.values { handler(snapshot) }
    }
}
