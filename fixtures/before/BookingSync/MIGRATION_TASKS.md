# BookingSync: Swift 6 Migration Tasks

The second, harder fixture (Day 5): an Airbnb-style booking sync library written in **Swift 5** (tools 5.9, minimal checking). Unlike FeedKit it centres on **actors, async streams and bugs the compiler can't see**: two reentrancy bugs, a leaked polling task, an unsynchronized multicast delegate and a pool-starvation deadlock that only appears after a naive migration.

Goal: migrate `BookingSync` to Swift 6 language mode with **zero warnings**, choose approachable-concurrency settings per target, keep `LegacyCalendarAPI` as an unmigrated vendored SDK, and add regression tests for every bug the compiler can't detect.

```bash
swift build && swift test                                    # baseline: green, 6 XCTest tests
swift build -Xswiftc -strict-concurrency=complete            # 36 warnings (31 BookingSync + 5 LegacyCalendarAPI), fresh scratch path
swift build -Xswiftc -swift-version -Xswiftc 6               # errors
```

## Steps (playbook v2 §1)

1. Measure with complete checking on a **fresh** scratch path (incremental builds hide warnings).
2. Choose the isolation defaults per target (R17): the library stays nonisolated, the demo app target gets default `MainActor` isolation.
3. `swift package migrate --target BookingSync --to-feature NonisolatedNonsendingByDefault`, then prune the `@concurrent` it adds (R18).
4. Fix the tasks below, smallest change first. Build and test after each file.
5. `swift-tools-version: 6.2`; `LegacyCalendarAPI` on `.swiftLanguageMode(.v5)`; warnings as errors on migrated targets.
6. XCTest → Swift Testing, plus a regression test for every row marked 🐞. Run the suite **10 times**.

## Tasks

🐞 = a bug the compiler does **not** report.

| # | File | Planted issue | Expected fix | Rule |
| --- | --- | --- | --- | --- |
| 1 | `SyncConfig.swift` | `public var syncBatchSize` global mutable state | `let` (no writes anywhere) | R1 |
| 2 | `SyncConfig.swift` | `static var maxRetries`, `pollInterval` | `static let` | R1 |
| 3 | `SyncConfig.swift` | 🐞 `syncAttempts` written from background queues, never read | delete (behavior-neutral) | R1 |
| 4 | `Models.swift` | public structs not visibly `Sendable` | `: Sendable` on `AvailabilitySnapshot`, `Reservation`, `SyncError` | R2.1 |
| 5 | `ReservationStore.swift` | non-Sendable singleton guarded by a reader-writer `DispatchQueue` | an `OSAllocatedUnfairLock`, so the class is checked `Sendable` | R24 |
| 6 | `ReservationStore.swift` | 🐞 the "obvious" fix (`@unchecked Sendable` + keep `queue.sync`) **deadlocks** under concurrent async callers: every pool thread blocks in `queue.sync` behind a barrier that never gets a thread | don't block cooperative threads: a lock with tiny critical sections | R24 |
| 7 | `AvailabilityCache.swift` | unmigrated `LegacyCalendarAPI` (non-Sendable `CalendarClient`, `RawAvailability`) | `@preconcurrency import` + documented `@unchecked Sendable` retroactive conformance | R10 |
| 8 | `AvailabilityCache.swift` | the continuation resumes with a non-Sendable `RawAvailability` (*"sending 'result' risks causing data races"*) | convert to the `Sendable` snapshot inside the callback | R4, R14 |
| 9 | `AvailabilityCache.swift` | the callback runs on the SDK's background queue but isn't `@Sendable` | `{ @Sendable result in … }` | R5 |
| 10 | `AvailabilityCache.swift` | 🐞 reentrancy: N concurrent callers for one listing make N fetches | an in-flight `Task` dictionary, recorded before suspending | R21 |
| 11 | `BookingCoordinator.swift` | 🐞 reentrancy: two guests both pass the availability check while the first is suspended in payment, so the same nights are **sold twice** | a synchronous hold before the payment `await`, released on failure | R21 |
| 12 | `BookingCoordinator.swift` | *"sending 'self.payments' risks causing data races"*: `authorize` hops to the global executor | `NonisolatedNonsendingByDefault` (it now runs on the coordinator): no `Sendable` requirement forced on a public protocol | R18 |
| 13 | `AvailabilityFeed.swift` | 🐞 `handlers` dictionary mutated by callers and read on the SDK's queue, with no lock | `OSAllocatedUnfairLock`; class `Sendable`; never call out under the lock | R24 |
| 14 | `AvailabilityFeed.swift` | multicast callback API, manual add/remove (leaks if callers forget) | `updates(for:) -> AsyncStream` per subscriber with `onTermination`; the callback API kept, deprecated, `@Sendable` | R22, R13 |
| 15 | `ConflictResolver.swift` | CPU work offloaded with `DispatchQueue.global().async` + a non-Sendable completion | `@concurrent static func resolved(…) async`; keep the callback, deprecated, `@Sendable` | R19, R13 |
| 16 | `SyncEngine.swift` | 🐞 `Task.detached { while true { … self … } }`: captures `self` strongly forever, can't be stopped, keeps polling after the owner is gone | the engine owns its `Task`; `self` held weakly between passes; `stop()` + `deinit` cancel it; idempotent `start()` | R23 |
| 17 | `SyncEngine.swift` | real-time `Task.sleep`, so it's untestable without sleeping | inject `any Clock<Duration>` | R23 |
| 18 | `SyncEngine.swift` | non-Sendable class with mutable `watched`, `completedPasses`, `onPass` | state in an `OSAllocatedUnfairLock`; `onPass` becomes `@Sendable` | R24, R13 |
| 19 | `BookingViewModel.swift` | `ObservableObject` + `DispatchQueue.main.async` around UI state | `@preconcurrency @MainActor @Observable` (macOS 14 / iOS 17 already required) | R6, R13 |
| 20 | `BookingViewModel.swift` | the feed subscription is a callback cleaned up in `deinit` | a stream-consuming `Task` owned by the model, `[weak self]` per element, cancelled in `deinit` | R23, R9 |
| 21 | `BookingViewModel.swift` | `load(completion:)` callback API | `func load() async`; keep the callback version, deprecated | R13 |
| 22 | `BookingSyncDemo/main.swift` | app glue full of main-thread assumptions | app target with default `MainActor` isolation: no annotations, `await viewModel.load()` | R17 |
| 23 | `Package.swift` | Swift 5 everywhere | tools 6.2; settings per target; `.treatAllWarnings(as: .error)` on migrated targets | R16, R17, R18 |
| 24 | `BookingSyncTests.swift` | XCTest with expectations and timeouts | Swift Testing, `@MainActor` suite, regression tests for 🐞 rows, an injected `ManualClock`, no sleeping on timers | R15 |

## Results (verified)

| | Before | After |
| --- | --- | --- |
| Language mode | Swift 5 | Swift 6 (`LegacyCalendarAPI` stays on 5) |
| Complete-checking warnings (fresh build) | **36** | **0** on Swift 6.3.2 and 6.4.2, with warnings as errors |
| Tests | 6 XCTest | **18 Swift Testing functions (46 cases)**, 10 green runs in a row |
| Bugs the compiler can't see (🐞) | 6 | 4 with dedicated regression tests (#6, #10, #11, #16), plus the subscription leak (#20). #3 was deleted; #13 is fixed by construction (the lock), and Thread Sanitizer is the tool that would catch it |
