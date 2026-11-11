import Foundation

public struct AvailabilitySnapshot: Equatable {
    public let listingID: Int
    public let freeNights: Set<Int>
    public init(listingID: Int, freeNights: Set<Int>) {
        self.listingID = listingID
        self.freeNights = freeNights
    }
}

public struct Reservation: Equatable {
    public let guest: String
    public let listingID: Int
    public let nights: ClosedRange<Int>
    public init(guest: String, listingID: Int, nights: ClosedRange<Int>) {
        self.guest = guest
        self.listingID = listingID
        self.nights = nights
    }
}

public enum SyncError: Error, Equatable {
    case listingNotFound
    case nightsUnavailable
    case paymentDeclined
}
