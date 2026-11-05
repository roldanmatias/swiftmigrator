import Foundation

/// Never mutated after launch, so it's a constant.
public let feedPageSize = 20

public enum FeedEndpoints {
    public static let baseURL = URL(string: "https://example.com/api")!
}

// `requestCount` was removed: it was written from background queues (a real data race)
// and never read anywhere.
