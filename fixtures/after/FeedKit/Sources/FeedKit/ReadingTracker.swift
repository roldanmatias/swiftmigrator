import Foundation

public actor ReadingStats {
    public private(set) var readCount = 0
    private var history: [Int] = []

    public init() {}

    /// Atomic read-modify-write: runs synchronously inside the actor, with no `await` in between.
    public func increment() {
        readCount += 1
    }

    public func setReadCount(_ value: Int) {
        readCount = value
    }

    public func reset() {
        history.append(readCount)
        readCount = 0
    }

    // deinit removed: it called an isolated method from a non-isolated deinit, and resetting
    // state of an actor that is being destroyed had no observable effect.
}

/// `Sendable`: final, and its only stored property is an actor (implicitly Sendable).
public final class ReadingTracker: Sendable {
    public let stats: ReadingStats

    public init(stats: ReadingStats = ReadingStats()) {
        self.stats = stats
    }

    public func markRead(_ article: Article) async {
        await stats.increment()
    }
}
