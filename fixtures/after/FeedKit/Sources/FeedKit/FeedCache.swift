import Foundation

/// `@unchecked Sendable`: all mutable state (`storage`) is only accessed while holding `lock`.
/// Follow-up: replace with `Mutex` (Synchronization) once the deployment target is macOS 15 / iOS 18.
public final class FeedCache: @unchecked Sendable {
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
