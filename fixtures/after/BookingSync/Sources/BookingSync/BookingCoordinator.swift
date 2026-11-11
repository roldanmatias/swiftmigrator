import Foundation

/// R18: with `NonisolatedNonsendingByDefault`, `authorize` runs on the caller's
/// actor, so `payments` never crosses a boundary and the protocol doesn't need a
/// `Sendable` requirement (which would have broken every client conformer).
public protocol PaymentAuthorizing {
    func authorize(guest: String, amountCents: Int) async throws
}

/// Books nights after payment authorization.
public actor BookingCoordinator {
    private let cache: AvailabilityCache
    private let payments: any PaymentAuthorizing
    private let store: ReservationStore
    private var bookedNights: [Int: Set<Int>] = [:]

    public init(cache: AvailabilityCache, payments: any PaymentAuthorizing, store: ReservationStore = .shared) {
        self.cache = cache
        self.payments = payments
        self.store = store
    }

    /// R21: the availability check and the hold happen synchronously, *after*
    /// the cache await and *before* the payment await. Two guests can no longer
    /// both pass the check while the first one is suspended in payment.
    public func book(guest: String, listingID: Int, nights: ClosedRange<Int>, amountCents: Int) async throws -> Reservation {
        let availability = try await cache.availability(for: listingID)
        let requested = Set(nights)
        guard requested.isSubset(of: availability.freeNights),
              bookedNights[listingID, default: []].isDisjoint(with: requested) else {
            throw SyncError.nightsUnavailable
        }
        bookedNights[listingID, default: []].formUnion(requested)          // hold
        do {
            try await payments.authorize(guest: guest, amountCents: amountCents)
        } catch {
            bookedNights[listingID, default: []].subtract(requested)        // release the hold
            throw SyncError.paymentDeclined
        }
        let reservation = Reservation(guest: guest, listingID: listingID, nights: nights)
        store.add(reservation)
        return reservation
    }
}
