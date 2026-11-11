import Foundation

// R2.1: public value types state `Sendable` explicitly (implicit conformance
// isn't visible to other modules).

public struct AvailabilitySnapshot: Equatable, Sendable {
    public let listingID: Int
    public let freeNights: Set<Int>
    public init(listingID: Int, freeNights: Set<Int>) {
        self.listingID = listingID
        self.freeNights = freeNights
    }
}

public struct Reservation: Equatable, Sendable {
    public let guest: String
    public let listingID: Int
    public let nights: ClosedRange<Int>
    public init(guest: String, listingID: Int, nights: ClosedRange<Int>) {
        self.guest = guest
        self.listingID = listingID
        self.nights = nights
    }
}

public enum SyncError: Error, Equatable, Sendable {
    case listingNotFound
    case nightsUnavailable
    case paymentDeclined
}
