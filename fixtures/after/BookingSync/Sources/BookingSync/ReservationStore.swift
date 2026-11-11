import Foundation
import os

/// Thread-safe reservation store.
///
/// R24: the "before" version was a reader-writer `DispatchQueue` (sync reads,
/// async barrier writes). Wrapping it in `@unchecked Sendable` compiled, but the
/// regression test `theSameNightsAreSoldOnce` **deadlocked**: async callers
/// blocked every cooperative-pool thread in `queue.sync` behind a pending barrier,
/// and the barrier never got a thread to run on (verified with `sample`: 16/16
/// pool threads in `_dispatch_sync_f_slow`). Never block a cooperative thread on
/// work that needs another thread.
///
/// Fix: an `OSAllocatedUnfairLock` (Sendable, macOS 13 / iOS 16). The critical
/// sections are tiny and never wait on other work, and the class is now checked
/// `Sendable`. `Mutex` would be equivalent but needs macOS 15 / iOS 18.
/// Behavior note: `add` is now visible to the next read immediately (it used to
/// be eventually visible); no caller relied on the delay.
public final class ReservationStore: Sendable {
    public static let shared = ReservationStore()

    private let reservations = OSAllocatedUnfairLock<[Reservation]>(initialState: [])

    public init() {}

    public func add(_ reservation: Reservation) {
        reservations.withLock { $0.append(reservation) }
    }

    public func all() -> [Reservation] {
        reservations.withLock { $0 }
    }

    public func reservations(for listingID: Int) -> [Reservation] {
        reservations.withLock { $0.filter { $0.listingID == listingID } }
    }
}
