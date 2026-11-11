import Foundation

/// CPU-heavy merge of local and server reservations.
public enum ConflictResolver {
    /// Server wins on overlap; result sorted by listing then first night.
    public static func resolve(local: [Reservation], server: [Reservation]) -> [Reservation] {
        var result = server
        for reservation in local {
            let overlaps = server.contains {
                $0.listingID == reservation.listingID && $0.nights.overlaps(reservation.nights)
            }
            if !overlaps { result.append(reservation) }
        }
        return result.sorted { ($0.listingID, $0.nights.lowerBound) < ($1.listingID, $1.nights.lowerBound) }
    }

    /// R19: explicit background execution, structured, keeps priority and task-locals.
    /// With `NonisolatedNonsendingByDefault` a plain `async` function would run on
    /// the caller's actor (the main actor, from UI code), so `@concurrent` is required.
    @concurrent
    public static func resolved(local: [Reservation], server: [Reservation]) async -> [Reservation] {
        resolve(local: local, server: server)
    }

    /// R13: kept; the completion is `@Sendable` because it's called on a global queue.
    @preconcurrency
    @available(*, deprecated, message: "Use await resolved(local:server:) instead")
    public static func resolveInBackground(local: [Reservation], server: [Reservation],
                                           completion: @escaping @Sendable ([Reservation]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            completion(resolve(local: local, server: server))
        }
    }
}
