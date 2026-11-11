import Foundation

public protocol PaymentAuthorizing {
    func authorize(guest: String, amountCents: Int) async throws
}

/// Books nights after payment authorization.
public actor BookingCoordinator {
    private let cache: AvailabilityCache
    private let payments: PaymentAuthorizing
    private let store: ReservationStore
    private var bookedNights: [Int: Set<Int>] = [:]

    public init(cache: AvailabilityCache, payments: PaymentAuthorizing, store: ReservationStore = .shared) {
        self.cache = cache
        self.payments = payments
        self.store = store
    }

    public func book(guest: String, listingID: Int, nights: ClosedRange<Int>, amountCents: Int) async throws -> Reservation {
        let availability = try await cache.availability(for: listingID)
        let requested = Set(nights)
        guard requested.isSubset(of: availability.freeNights),
              bookedNights[listingID, default: []].isDisjoint(with: requested) else {
            throw SyncError.nightsUnavailable
        }
        do {
            try await payments.authorize(guest: guest, amountCents: amountCents)
        } catch {
            throw SyncError.paymentDeclined
        }
        bookedNights[listingID, default: []].formUnion(requested)
        let reservation = Reservation(guest: guest, listingID: listingID, nights: nights)
        store.add(reservation)
        return reservation
    }
}
