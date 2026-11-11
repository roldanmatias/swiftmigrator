import os
@testable import BookingSync

/// Deterministic helpers. No test in this package sleeps.

final class Counter: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)
    @discardableResult func increment() -> Int { value.withLock { $0 += 1; return $0 } }
    var current: Int { value.withLock { $0 } }
}

/// Yields until `condition` holds (bounded: a bug fails instead of hanging).
func eventually(_ condition: @Sendable () async -> Bool, maxYields: Int = 10_000) async -> Bool {
    for _ in 0..<maxYields {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

/// A clock that only moves when the test says so.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper { let id: Int; let deadline: Instant; let continuation: CheckedContinuation<Void, any Error> }
    private struct State { var now = Instant(offset: .zero); var sleepers: [Sleeper] = []; var cancelled: Set<Int> = []; var nextID = 0 }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { s in defer { s.nextID += 1 }; return s.nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let outcome: Int = state.withLock { s in
                    if s.cancelled.remove(id) != nil { return 2 }
                    if deadline <= s.now { return 1 }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: c))
                    return 0
                }
                if outcome == 1 { c.resume() } else if outcome == 2 { c.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper: Sleeper? = state.withLock { s in
                guard let i = s.sleepers.firstIndex(where: { $0.id == id }) else { s.cancelled.insert(id); return nil }
                return s.sleepers.remove(at: i)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due: [Sleeper] = state.withLock { s in
            s.now = s.now.advanced(by: duration)
            let now = s.now
            defer { s.sleepers.removeAll { $0.deadline <= now } }
            return s.sleepers.filter { $0.deadline <= now }
        }
        due.forEach { $0.continuation.resume() }
    }
}
