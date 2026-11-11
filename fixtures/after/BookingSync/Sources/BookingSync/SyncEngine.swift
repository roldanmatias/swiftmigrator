import Foundation
import os

/// Periodically refreshes availability for the watched listings.
///
/// R23: the old `start()` launched a detached `while true` loop that captured
/// `self` strongly and could never be stopped: the engine leaked forever and kept
/// polling after its owner was gone. Now the engine owns its task, the loop holds
/// `self` only during a pass, `stop()` and `deinit` cancel it, and the clock is
/// injected so tests never sleep.
public final class SyncEngine: Sendable {
    private struct State {
        var watched: [Int] = []
        var completedPasses = 0
        var onPass: (@Sendable (Int) -> Void)?
        var pollTask: Task<Void, Never>?
    }

    private let cache: AvailabilityCache
    private let clock: any Clock<Duration>
    private let interval: Duration
    // R24: Sendable lock (macOS 13 / iOS 16) instead of unsynchronized `var`s.
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(
        cache: AvailabilityCache,
        clock: any Clock<Duration> = ContinuousClock(),
        interval: Duration = .seconds(SyncConfig.pollInterval)
    ) {
        self.cache = cache
        self.clock = clock
        self.interval = interval
    }

    deinit { state.withLock { $0.pollTask }?.cancel() }

    public var completedPasses: Int { state.withLock { $0.completedPasses } }
    public var isRunning: Bool { state.withLock { $0.pollTask != nil } }

    /// R13: now `@Sendable`, since it's called from the polling task.
    public var onPass: (@Sendable (Int) -> Void)? {
        get { state.withLock { $0.onPass } }
        set { state.withLock { $0.onPass = newValue } }
    }

    public func watch(_ listingIDs: [Int]) { state.withLock { $0.watched = listingIDs } }

    /// Starts polling. Idempotent: a second call doesn't start a second loop.
    public func start() {
        state.withLock { state in
            guard state.pollTask == nil else { return }
            state.pollTask = Task { [weak self, clock, interval] in
                while !Task.isCancelled {
                    do {
                        guard let engine = self else { return }   // strong only for this pass
                        await engine.syncOnce()
                    }
                    do { try await clock.sleep(for: interval) } catch { return }   // cancelled
                }
            }
        }
    }

    public func stop() {
        let task = state.withLock { state in defer { state.pollTask = nil }; return state.pollTask }
        task?.cancel()
    }

    public func syncOnce() async {
        let watched = state.withLock { $0.watched }
        for id in watched.prefix(syncBatchSize) {
            await cache.invalidate(id)
            _ = try? await cache.availability(for: id)
        }
        let (passes, onPass) = state.withLock { state in
            state.completedPasses += 1
            return (state.completedPasses, state.onPass)
        }
        onPass?(passes)
    }
}
