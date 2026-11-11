import Foundation

/// Reader-writer store: concurrent reads, barrier writes.
public final class ReservationStore {
    public static let shared = ReservationStore()

    private let queue = DispatchQueue(label: "reservation.store", attributes: .concurrent)
    private var reservations: [Reservation] = []

    public init() {}

    public func add(_ reservation: Reservation) {
        queue.async(flags: .barrier) { self.reservations.append(reservation) }
    }

    public func all() -> [Reservation] {
        queue.sync { reservations }
    }

    public func reservations(for listingID: Int) -> [Reservation] {
        queue.sync { reservations.filter { $0.listingID == listingID } }
    }
}
