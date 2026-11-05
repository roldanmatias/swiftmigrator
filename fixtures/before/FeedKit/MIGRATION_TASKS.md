# FeedKit — Swift 6 Migration Tasks

Tiny news-feed library written in **Swift 5** (tools 5.9, minimal checking).
Each file plants one or more concepts from [notes/swift6-concurrency.md](../../../notes/swift6-concurrency.md).
Goal: migrate `FeedKit` to Swift 6 language mode; keep `LegacyNetworking` as an unmigrated dependency.

```bash
swift build && swift test                                     # baseline: green, 1 warning
swift build -Xswiftc -strict-concurrency=complete             # ~18 warnings
swift build -Xswiftc -swift-version -Xswiftc 6                # errors
```

## Steps (follow the strategy, §2)
1. Measure: build with `-strict-concurrency=complete` and save the warning count.
2. Swift 5 mode + upcoming features one at a time: `GlobalConcurrency`, `InferSendableFromCaptures`, `DisableOutwardActorInference`, then `StrictConcurrency` (§2, §3).
3. Fix the tasks below ("express what is true now").
4. `swift-tools-version: 6.0`; keep `LegacyNetworking` on `.swiftLanguageMode(.v5)` (§3).
5. Tests stay green after every step. Bonus: XCTest → Swift Testing, `ObservableObject` → `@Observable`.

## Tasks

| # | File | Planted issue | Expected fix | Notes § |
|---|------|---------------|--------------|---------|
| 1 | `Config.swift` | `public var feedPageSize` global mutable | `let` (or `@MainActor`) | 4.1 |
| 2 | `Config.swift` | `var requestCount` mutated from background queues (real race) | move into `FeedService` behind isolation / remove; `nonisolated(unsafe)` only with a lock | 4.1 |
| 3 | `Config.swift` | `static var baseURL` | `static let` | 4.1 |
| 4 | `Models.swift` | `public struct Article` not visibly Sendable to clients | `: Sendable` (also `FeedError`) | 1, 4.3 |
| 5 | `FeedCache.swift` | lock-protected class + `static let shared` non-Sendable | `final class FeedCache: @unchecked Sendable` (or convert to `actor`) | 4.3 manual sync |
| 6 | `FeedService.swift` | depends on unmigrated `LegacyNetworking` (non-Sendable `HTTPResponse`, `HTTPClient`) | `@preconcurrency import LegacyNetworking` | 4.3, 5 |
| 7 | `FeedService.swift` | callback-only public API | add `func fetchArticles(page:) async throws(FeedError) -> [Article]` with `withCheckedThrowingContinuation`; resume exactly once | 5 |
| 8 | `FeedService.swift` | `completion` called from another queue but not `@Sendable` | `@escaping @Sendable`; mark the class `Sendable` (`final`, `let`s only) | 5, 1 |
| 9 | `FeedService.swift` | public API change breaks clients | `@preconcurrency` on the changed declaration | 8 |
| 10 | `FeedViewModel.swift` | UI state protected by `DispatchQueue.main.async` (latent isolation) | `@MainActor` class, `async` `load()` | 4.3 latent isolation |
| 11 | `FeedViewModel.swift` | after #10: `FeedRenderer` conformance mismatch | `@MainActor protocol FeedRenderer` (or per-requirement / `@preconcurrency` conformance) | 4.2 |
| 12 | `FeedViewModel.swift` | after #10: `FeedPreviews.viewModel` default value in non-isolated context | `@MainActor` on `FeedPreviews` or `nonisolated init` | 4.4 |
| 13 | `FeedViewModel.swift` | public type becomes `@MainActor` (ABI/source break) | `@preconcurrency @MainActor` | 5, 8 |
| 14 | `ReadingTracker.swift` | actor `deinit` calls isolated `reset()` | remove / do sync cleanup on stored props, or `Task { [captured] in ... }` without `self` | 4.5 |
| 15 | `ReadingTracker.swift` | `markRead` read-modify-write across two `await`s (lost updates) | atomic `func increment()` inside the actor | 1 atomicity |
| 16 | `ReadingTracker.swift` | `ReadingTracker` non-Sendable class | `final class ...: Sendable` (only `let stats`) | 1 |
| 17 | `ImagePrefetcher.swift` | `self` + non-Sendable `Loader` captured in `addTask` | `@Sendable` loader, `Sendable` class (or capture `loader` locally) | 4.3 |
| 18 | `ImagePrefetcher.swift` | unbounded task group (one task per URL) | throttle to N in-flight tasks | 9 |
| 19 | `Package.swift` | Swift 5 everywhere | tools 6.0, per-target `.swiftLanguageMode(.v5)` for `LegacyNetworking` | 3 |
| 20 | `Tests/` | XCTest + expectations | Swift Testing (`@Test`, `#expect`), `async` tests, add a concurrency test for #15 (100 concurrent `markRead` → 100) | Day 3 |

**Deliberately not migrated:** `LegacyNetworking` simulates a third-party SDK — it must keep compiling in Swift 5 mode and be consumed via `@preconcurrency import`.

## Done when
- `swift build` with tools 6.0 → **0 errors, 0 warnings** in `FeedKit`.
- `swift test` green; new concurrency test for #15 passes reliably (`swift test --parallel`, repeat runs).
- Every `@unchecked Sendable` / `nonisolated(unsafe)` / `@preconcurrency` has a one-line justification comment (future refactor list).
- Before/after diff copied to `fixtures/after/FeedKit` + examples extracted into `playbook/MIGRATION_PLAYBOOK.md`.
