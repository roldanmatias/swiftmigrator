import Foundation

public actor ReadingStats {
    public private(set) var readCount = 0
    private var history: [Int] = []

    public init() {}

    public func setReadCount(_ value: Int) {
        readCount = value
    }

    public func reset() {
        history.append(readCount)
        readCount = 0
    }

    deinit {
        // deinit is non-isolated: calling an isolated method here is invalid.
        reset()
    }
}

public final class ReadingTracker {
    public let stats: ReadingStats

    public init(stats: ReadingStats = ReadingStats()) {
        self.stats = stats
    }

    /// Read-modify-write split across two `await`s.
    public func markRead(_ article: Article) async {
        let current = await stats.readCount
        await stats.setReadCount(current + 1)
    }
}
