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

    /// Runs `resolve` off the main thread.
    public static func resolveInBackground(local: [Reservation], server: [Reservation],
                                           completion: @escaping ([Reservation]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            completion(resolve(local: local, server: server))
        }
    }
}
