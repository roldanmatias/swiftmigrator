# Swift 6 Migration Playbook

Rules a migration agent follows to move a Swift 5 module to the **Swift 6 language mode** (complete data-race safety).
It is written to be loaded as **prompt context**: rules are numbered so the agent can cite them in its reports (`applied R4, R11`).

- Reference fixture: `fixtures/before/FeedKit` → `fixtures/after/FeedKit` (manual migration; every example below comes from it).
- Concept reference: `notes/swift6-concurrency.md`, and the official guide at https://docs.swift.org/latest/documentation/migrationguide

---

## 0. Prime directives

1. **Preserve behavior.** A migration is not a refactor. Observable behavior, public names, and test expectations stay the same unless a rule below explicitly allows a change.
2. **Express what is true now.** Annotate the isolation and thread-safety the code *already has* (by convention, comments, locks, queues). Don't redesign.
3. **The compiler is the oracle.** Every change must be motivated by a diagnostic or by a rule in this playbook. Never "fix" code the compiler and these rules don't flag.
4. **Prefer safe over unsafe.** Use the most checked fix that works (see the ladder in §3). Every unsafe opt-out needs a justification comment.
5. **Small diffs, always green.** One file, or one tightly coupled group of files, at a time. Build and tests must pass before you move on.
6. **Stop and escalate instead of guessing** (§6).

---

## 1. Process

### 1.1 Module-level (once per module)
| Step | Action | Done when |
|---|---|---|
| M1 | Baseline: `swift build && swift test` in Swift 5 mode | green; save the warning count |
| M2 | Measure: `swift build -Xswiftc -strict-concurrency=complete` | diagnostics saved, grouped by file |
| M3 | Order work: globals and shared models first (they cause the most warnings), then services, then UI, then tests | queue of files |
| M4 | Migrate each file (§1.2) while still in **Swift 5 mode + complete checking** | 0 concurrency warnings in the module |
| M5 | Switch the language mode: `swift-tools-version: 6.0`; unmigrated targets get `.swiftLanguageMode(.v5)` | Swift 6 build is green |
| M6 | Final: clean build (fresh `--scratch-path`) with **0 warnings**, `swift test --parallel` green 3 times in a row | report written |

### 1.2 File-level loop
```
read file + its diagnostics
→ classify each diagnostic (§2 table)
→ apply the matching rule (smallest change)
→ build (complete checking)  ── fail → read the new errors, retry (max N attempts)
→ run tests                  ── fail → revert the last change, retry or escalate
→ report: rules applied, unsafe opt-outs used, follow-ups
```
New diagnostics often show up *after* a fix (adding `@MainActor` exposes protocol mismatches and default-value errors). That's expected. Keep looping.

---

## 2. Diagnostic → rule lookup

| Diagnostic (substring) | Rule |
|---|---|
| `var '…' is not concurrency-safe because it is nonisolated global shared mutable state` | R1 |
| `static property '…' is not concurrency-safe because non-'Sendable' type` | R2 |
| `sending '…' risks causing data races` / `capture of '…' with non-Sendable type` | R3 → R4 → R5 |
| `…cannot be used to satisfy nonisolated protocol requirement` | R7 |
| `main actor-isolated default value in a nonisolated context` | R8 |
| `…can not be referenced from a nonisolated context` (inside `deinit`) | R9 |
| `capture of 'self' in a closure that outlives deinit` | R9 |
| `passing closure as a 'sending' parameter risks causing data races` (task groups, `Task {}`) | R5, R12 |
| Diagnostics coming from a module you don't own | R10 |
| No diagnostic, but `DispatchQueue.main.async` around UI state | R6 |
| No diagnostic, but read-modify-write across `await` | R11 |

---

## 3. Rules

### R1 — Global and static mutable variables
Ladder: `let` → computed property → `@MainActor` → `nonisolated(unsafe)` (only with an external lock, plus a justification comment).
```swift
// before
public var feedPageSize = 20
public static var baseURL = URL(string: "https://example.com/api")!
// after
public let feedPageSize = 20
public static let baseURL = URL(string: "https://example.com/api")!
```
**Edge cases**
- `var` → `let` on a **public** global is source-breaking if clients assign to it. Search for writes first. If any exist, use `@MainActor` instead.
- A variable that is **written but never read** (e.g. `requestCount`) can be deleted. Say so in the report, because it's a behavior-neutral removal, not a fix.
- Never use `nonisolated(unsafe)` just to silence a variable that is mutated from several threads without a lock. That's a real data race → escalate.

### R2 — Make types `Sendable` (in this order)
1. **Value type** with Sendable members → add `: Sendable` explicitly. This is **required for `public` types**, because implicit `Sendable` isn't visible outside the module.
2. **Class with only `let` Sendable properties** → `final class X: Sendable`.
3. **UI or main-thread type** → `@MainActor` (implicitly Sendable).
4. **Owns mutable state used from many places** → `actor`. Only do this if callers can become `async`. Otherwise escalate.
5. **Already synchronized by a lock or queue** → `@unchecked Sendable` + a comment naming the lock.
```swift
// before
public struct Article: Equatable, Codable { ... }
public final class FeedCache { private var storage...; private let lock = NSLock() }
// after
public struct Article: Equatable, Codable, Sendable { ... }
/// `@unchecked Sendable`: all mutable state (`storage`) is only accessed while holding `lock`.
public final class FeedCache: @unchecked Sendable { ... }
```
**Edge cases**
- `@unchecked Sendable` is allowed **only** if you can point to the lock or queue protecting *every* mutable property. If you can't, escalate.
- Adding `Sendable` to a public type is a public promise. Removing it later breaks the API.
- Don't add `Sendable` to a generic **requirement** (`where T: Sendable`) without `@preconcurrency` (R13).

### R3 — Fix latent isolation before adding Sendable
If a value only crosses a boundary because a function is non-isolated while all its work happens on the main actor, **isolate the function** instead of making the value Sendable.
```swift
// before: non-isolated → hops to main → non-Sendable value crosses
func updateStyle(_ c: ColorComponents) async { await applyBackground(c) }
// after
@MainActor func updateStyle(_ c: ColorComponents) async { applyBackground(c) }
```

### R4 — Convert to Sendable *before* the boundary
When a non-Sendable value comes from code you can't change, transform it into a Sendable value **inside** the callback, and send only that.
```swift
// ❌ error: sending 'result' risks causing data races (HTTPResponse is non-Sendable)
try await withCheckedThrowingContinuation { c in client.get(url) { c.resume(with: $0) } }
// ✅ decode inside the callback, resume with Result<[Article], FeedError> (Sendable)
await withCheckedContinuation { c in fetch(page: page) { c.resume(returning: $0) } }
```
Alternatives: a `sending` parameter (`func f(_ x: sending T)`), or pass a `@Sendable () -> T` factory instead of the value.

### R5 — Closures that run elsewhere must be `@Sendable`
Completion handlers called on another queue, task-group bodies, and stored async closures: mark them `@Sendable`. Capture **values**, not `self`.
```swift
// before
public typealias Loader = (URL) async -> Data?
group.addTask { (url, await self.loader(url)) }
// after
public typealias Loader = @Sendable (URL) async -> Data?
let loader = self.loader
group.addTask { (url, await loader(url)) }
```
**Edge case:** if an *unmigrated* API calls your closure off the main thread but doesn't declare `@Sendable`, the compiler infers `@MainActor` for the closure and it **crashes at runtime**. Write `{ @Sendable in ... }` explicitly when the docs say "called on a background queue".

### R6 — UI state → `@MainActor` (replace manual dispatch)
Types whose state is touched with `DispatchQueue.main.async` are main-actor types by convention. Make that static.
```swift
// before
public final class FeedViewModel: ObservableObject {
    public func load(completion: (() -> Void)? = nil) {
        service.fetchArticles(page: 1) { [weak self] result in
            DispatchQueue.main.async { self?.render(...) ; completion?() }
        }
    }
}
// after
@MainActor @Observable
public final class FeedViewModel {
    public func load(page: Int = 1) async {
        do { render(try await service.fetchArticles(page: page)) } catch { errorMessage = "…" }
    }
}
```
**Edge cases**
- Remove the `DispatchQueue.main.async` wrappers once the type is `@MainActor`. Leaving them in causes Sendable errors.
- `ObservableObject` → `@Observable` requires iOS 17 / macOS 14. Do it **only** if the deployment target already allows it, or if a human approved raising it (as in the fixture). Mark `@ObservationIgnored` on stored dependencies that aren't UI state.
- A long synchronous job on a `@MainActor` type → move it to a `nonisolated` or `@concurrent` function. Don't take the whole type off the main actor.

### R7 — Protocol conformance isolation mismatch
Pick, in order:
1. All callers are on main → `@MainActor protocol P` (or `@MainActor` on the single requirement for a narrower effect).
2. The implementation doesn't touch isolated state → `nonisolated func` in the conforming type.
3. The protocol is from a module you don't own → `class C: @preconcurrency P` (adds runtime checks).
4. Make the requirement `async` → only with human approval (it affects every call site).
```swift
// after (fixture)
@MainActor
public protocol FeedRenderer: AnyObject { func render(_ articles: [Article]) }
```

### R8 — Isolated initializers in non-isolated contexts
`static let x = MainActorType()` in a non-isolated type:
1. Isolate the container: `@MainActor enum FeedPreviews { static let viewModel = FeedViewModel() }`
2. Or make the init `nonisolated` if it only sets Sendable or default-valued properties.

### R9 — `deinit` is always non-isolated
- Don't call isolated methods from `deinit`. If the cleanup only touches the dying object's own state, **delete it** (the fixture's `reset()` had no observable effect).
- If cleanup must reach *another* object: `Task { [store] in await store.stop() }`. Capture only what's needed.
- **Never capture `self` in a `deinit`** (not even implicitly through a property). It crashes with "deallocated with non-zero retain count", as observed in the fixture.

### R10 — Unmigrated dependencies
1. `@preconcurrency import Module` to downgrade its diagnostics.
2. If one of its types is documented as or verifiably thread-safe, add a retroactive conformance with a comment and a removal condition:
```swift
@preconcurrency import LegacyNetworking
// HTTPClient only holds immutable state. Remove once LegacyNetworking ships Sendable annotations.
extension HTTPClient: @unchecked Sendable {}
```
(Use `@retroactive` when the type comes from another *package*.)
3. Targets you don't migrate stay at `.swiftLanguageMode(.v5)`. **Never edit vendored or third-party sources.**

### R11 — Actor atomicity (reentrancy)
Every `await` is a point where actor state can change. Read-modify-write split across awaits loses updates → move it into **one synchronous actor method**.
```swift
// before (lost updates under concurrency)
let current = await stats.readCount
await stats.setReadCount(current + 1)
// after
await stats.increment()      // actor: func increment() { readCount += 1 }
```
The compiler does **not** flag this. Look for `await x.prop` followed by `await x.set…`. Add a regression test (100 concurrent calls → count == 100).

### R12 — Bounded task groups
Don't `addTask` once per item for unbounded input. Keep at most N tasks in flight, and add the next one as each finishes.
```swift
var pending = urls.makeIterator()
for _ in 0..<maxConcurrentTasks { guard let u = pending.next() else { break }; group.addTask { (u, await loader(u)) } }
for await (url, data) in group {
    if let data { results[url] = data }
    if let next = pending.next() { group.addTask { (next, await loader(next)) } }
}
```
Capture the item in a `let`, never a mutable index. Adding a limit parameter with a default value is source-compatible.

### R13 — Public API compatibility (libraries)
| Change | Do |
|---|---|
| Add `Sendable` to a concrete type | OK as is |
| Add `@Sendable` to a closure parameter or `where T: Sendable` | `@preconcurrency` on the declaration |
| Add `@MainActor` to a public type or function | `@preconcurrency @MainActor` when the type is otherwise unchanged |
| Callback API → async | **Add** the async overload; keep the callback version, `@available(*, deprecated)` |
| Add `sending` to a *result* | OK. To a *parameter*: breaking → escalate |
```swift
public func fetchArticles(page: Int) async throws(FeedError) -> [Article]   // new

@preconcurrency
@available(*, deprecated, message: "Use the async fetchArticles(page:) instead")
public func fetchArticles(page: Int, completion: @escaping @Sendable (Result<[Article], FeedError>) -> Void)
```

### R14 — Wrapping callbacks with continuations
- `withCheckedContinuation` / `withCheckedThrowingContinuation`, **never** the unsafe variants.
- Resume **exactly once** on every path, including error and early-return paths.
- Implement the async API on top of one private callback helper, so both public APIs share the same logic (no duplication).

### R15 — Tests
- XCTest → Swift Testing: `XCTestCase` → `@Suite struct`, `func testX` → `@Test func x`, `XCTAssertEqual(a, b)` → `#expect(a == b)`, `XCTAssertNil` → `#expect(x == nil)`, thrown error → `await #expect(throws: E.case) { try await … }`.
- Expectations and `wait(for:)` → `async` tests. For callback APIs, use `withCheckedContinuation`.
- Main-actor types → `@MainActor` on the suite.
- Tests calling deprecated APIs → mark the test `@available(*, deprecated)` instead of deleting it. The legacy API must stay covered.
- Add regression tests for bugs the compiler can't see (R11, R12). Repeated variants → `@Test(arguments:)`.
- Never weaken an assertion to make a test pass.

### R16 — Package and language mode
```swift
// swift-tools-version: 6.0
.target(name: "LegacyNetworking", swiftSettings: [.swiftLanguageMode(.v5)]),
.target(name: "FeedKit", dependencies: ["LegacyNetworking"]),   // Swift 6 by default
```
Don't change `platforms` unless R6 (Observation) was approved. Never disable checks to "pass" (`-disable-dynamic-actor-isolation`, `-strict-concurrency=minimal`, a `.v5` downgrade of the target being migrated).

---

## 4. Forbidden actions
- Removing or weakening tests, assertions, or `@available` checks.
- Blanket `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or `MainActor.assumeIsolated` without the justification required by its rule.
- `@MainActor` on a type only to silence errors when its work isn't UI or main-thread work. Choose R2 instead.
- `Task { }` used just to escape an isolation error inside synchronous code (it changes ordering and timing). Escalate.
- `withUnsafeContinuation`, `DispatchSemaphore` or blocking waits used to bridge async code.
- Editing generated, vendored, or third-party sources.
- Renaming or removing public API (deprecate instead, R13).

## 5. Unsafe opt-out policy
Every opt-out gets a one-line comment: **why it's safe + when to remove it**. All of them are listed in the report as follow-up refactors.

| Opt-out | Allowed only when |
|---|---|
| `@unchecked Sendable` | a named lock or queue guards every mutable property, or the type is immutable but comes from an unmigrated module |
| `nonisolated(unsafe)` | the variable is guarded by an external lock |
| `@preconcurrency import` | the module isn't owned by us or isn't migrated yet |
| `@preconcurrency` conformance | the protocol isn't owned by us |
| `MainActor.assumeIsolated` | the code is provably always on the main thread, as a temporary fix |

## 6. Escalate to a human when
- Making the fix requires turning sync API into `async` across module boundaries, or converting a widely-used class into an `actor`.
- A real data race exists with no lock to point to (shared mutable state written from several threads).
- The fix needs a deployment-target change, a new dependency, or a breaking public API change.
- An ObjC/C API's annotations look wrong (runtime `_dispatch_assert_queue_fail`). The workaround is a `nonisolated` override, plus a bug report to the library.
- The same file fails the build or tests after **N** attempts.

---

## 7. Verification checklist (per module)
- [ ] Clean build (fresh scratch path) in Swift 6 mode: **0 errors, 0 warnings** in migrated targets.
- [ ] `swift test --parallel` green **3×** in a row (concurrency bugs are flaky).
- [ ] Every opt-out has a justification comment and appears in the report.
- [ ] Public API: only additions and deprecations (or approved breaks).
- [ ] Regression tests for R11/R12 issues found.

Fixture result: `before` = 18 complete-checking warnings → `after` = 0 warnings, 9 test functions (11 cases) passing.

## 8. Report format (one per file)
```json
{
  "file": "Sources/FeedKit/FeedService.swift",
  "status": "migrated",            // migrated | escalated | failed
  "rules": ["R4", "R5", "R10", "R13", "R14"],
  "unsafe_opt_outs": [
    {"kind": "@unchecked Sendable", "symbol": "HTTPClient", "reason": "immutable; unmigrated module"}
  ],
  "public_api_changes": ["added async fetchArticles(page:)", "deprecated callback fetchArticles(page:completion:)"],
  "attempts": 2,
  "follow_ups": ["remove HTTPClient conformance when LegacyNetworking adds Sendable"]
}
```

---

## Appendix — FeedKit before → after map

| File | Rules |
|---|---|
| `Config.swift` | R1 (`let`, removal of a dead racy counter) |
| `Models.swift` | R2.1 |
| `FeedCache.swift` | R2.5 |
| `FeedService.swift` | R2.2, R4, R5, R10, R13, R14 |
| `FeedViewModel.swift` | R6, R7, R8, R13 |
| `ReadingTracker.swift` | R2.2, R9, R11 |
| `ImagePrefetcher.swift` | R5, R12 |
| `Package.swift` | R16 (+ approved platform bump for `@Observable`) |
| `FeedKitTests.swift` | R15 |
