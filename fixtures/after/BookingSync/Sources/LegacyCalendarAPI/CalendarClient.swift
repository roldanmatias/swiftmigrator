import Foundation

/// Vendored SDK (unmigrated). Raw types are non-Sendable classes.
public final class RawAvailability {
    public let listingID: Int
    public let freeNights: [Int]
    public init(listingID: Int, freeNights: [Int]) {
        self.listingID = listingID
        self.freeNights = freeNights
    }
}

public final class RawChange {
    public let listingID: Int
    public let freeNights: [Int]
    public init(listingID: Int, freeNights: [Int]) {
        self.listingID = listingID
        self.freeNights = freeNights
    }
}

public enum CalendarAPIError: Error {
    case notFound
    case cancelled
}

public protocol CalendarClientDelegate: AnyObject {
    /// Called on an internal background queue.
    func calendarClient(_ client: CalendarClient, didReceive change: RawChange)
}

/// Thread-safe by documentation: "all state is immutable after init, callbacks
/// are delivered on an internal serial queue". Not annotated for Swift concurrency.
public final class CalendarClient {
    private let data: [Int: [Int]]
    private let queue = DispatchQueue(label: "calendar.client")
    public weak var delegate: CalendarClientDelegate?

    public init(data: [Int: [Int]]) { self.data = data }

    /// Completion is called on an internal background queue.
    @discardableResult
    public func fetchAvailability(listingID: Int, completion: @escaping (Result<RawAvailability, Error>) -> Void) -> CalendarRequest {
        let request = CalendarRequest()
        queue.async {
            if request.isCancelled { completion(.failure(CalendarAPIError.cancelled)); return }
            guard let nights = self.data[listingID] else { completion(.failure(CalendarAPIError.notFound)); return }
            completion(.success(RawAvailability(listingID: listingID, freeNights: nights)))
        }
        return request
    }

    /// Test hook: simulates a server push.
    public func simulatePush(_ change: RawChange) {
        queue.async { self.delegate?.calendarClient(self, didReceive: change) }
    }
}

public final class CalendarRequest {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
