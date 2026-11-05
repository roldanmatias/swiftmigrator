import Foundation

/// Thread-safe thanks to a lock, but the compiler can't know that.
/// Exposed through a `static let` singleton of a non-Sendable class.
public final class FeedCache {
    public static let shared = FeedCache()

    private var storage: [Int: [Article]] = [:]
    private let lock = NSLock()

    public init() {}

    public func store(_ articles: [Article], forPage page: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage[page] = articles
    }

    public func articles(forPage page: Int) -> [Article]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[page]
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
