import Foundation

/// Global mutable state, readable and writable from any thread.
public var feedPageSize = 20

/// Mutated from background queues by `FeedService`.
var requestCount = 0

public enum FeedEndpoints {
    /// Mutable static state.
    public static var baseURL = URL(string: "https://example.com/api")!
}
