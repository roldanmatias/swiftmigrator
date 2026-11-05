# Swift 6 Concurrency Migration — Cheat Sheet

A short memory helper summarizing the official **Swift 6 Concurrency Migration Guide**.
Each section links to the corresponding page of the official docs.

---

## 0. Overview — Migrating to Swift 6
🔗 https://docs.swift.org/latest/documentation/migrationguide

- The Swift 6 **language mode** guarantees, at compile time, that concurrent code is **free of data races**. Checks that were optional before become required.
- It's **opt-in per target**. Swift 5 and Swift 6 mode modules (and C/ObjC code) interoperate.
- **Compiler version ≠ language mode.** The Swift 6 compiler supports modes `6`, `5`, `4.2`, `4`.

---

## 1. Data Race Safety (core concepts)
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/dataracesafety/

**Data race** = one thread accesses memory while another thread mutates it.
**Data isolation** = compile-time mutual exclusion over mutable state, like a lock checked by the compiler.
- **Static** isolation: declared with keywords and annotations (`actor`, `@MainActor`, `nonisolated`, …).
- **Dynamic** isolation: runtime fallbacks, for example for ObjC APIs (see §5).

### Isolation domains
Every declaration falls into one of three domains:

| Domain | Example |
|---|---|
| **Non-isolated** (default) | `func sailTheSea() {}` |
| **Actor instance** | `actor Island { var flock: [Chicken] }` |
| **Global actor** | `@MainActor class ChickenValley { ... }` |

```swift
actor Island {
    var flock: [Chicken]
    func addToFlock() { flock.append(Chicken()) }   // isolated to self
    nonisolated func canGrow() -> PlantSpecies { ... }  // can't touch flock
}

// `isolated` parameter: the function gains the actor's isolation
func addToFlock(of island: isolated Island) {
    island.flock.append(Chicken())
}
```

### Tasks
- A **Task** is a unit of concurrent work. It runs one function at a time, in order.
- A task always has an isolation (actor, global actor, or none). It is often **inherited from its context**.
- Only one task at a time runs synchronous code in a given isolation domain.

### Isolation inference and inheritance
- **Classes**: a subclass gets its superclass's isolation and can't change it. Members inherit the type's isolation.
- **Protocols**: an `@MainActor` protocol infers isolation onto the **whole type** when you conform in the type declaration, but **only onto the extension** when you conform in an extension. You can also isolate individual requirements.
- **Closures**: they are isolated to the context where they're formed, unless they're `@Sendable` or `sending`.
- **`Task {}`** inherits the enclosing isolation. You can override it with `Task { @MyGlobalActor in ... }`.

```swift
@MainActor
func eat(food: Pineapple) {
    Task { Chicken.prizedHen.eat(food: food) }   // inherits MainActor
    Task { @MyGlobalActor in /* ... */ }         // explicit isolation
}
```

### Isolation boundaries and `Sendable`
**Crossing a boundary** means moving a value between domains, either through an async call or a closure capture. Only values that are safe to share can cross.

- **Value types** are *implicitly* `Sendable` when all their stored properties are `Sendable`, but **only inside their own module**. Public types must declare `Sendable` explicitly.
- **Actors** and **global-actor-isolated types** are implicitly `Sendable`.
- **Classes** can be `Sendable` only if they are `final`, have only immutable (`let`) properties, and all those properties are `Sendable`. `@unchecked Sendable` skips checking and is meant for types you synchronize manually.

```swift
struct Pineapple { var weight: Double }     // implicitly Sendable (internal)
final class Chicken: Sendable { let name: String }
```

### Region-based isolation and `sending`
The compiler uses flow analysis to let a **non-Sendable value cross a boundary** when nothing else uses it afterwards.
```swift
func populate(island: Island) async {
    let chicken = Chicken()               // non-Sendable
    await island.adopt(chicken)           // OK: chicken isn't used afterwards
    // chicken.eat(food: Pineapple())     // ❌ error: used after being sent
}

// Make the guarantee explicit in an API:
func populate(island: Island, with chicken: sending Chicken) async {
    await island.adopt(chicken)
}
```

### Suspension points and atomicity
- `await` marks a **potential** suspension. The call might not actually suspend. Suspending **frees** the actor or thread instead of blocking it.
- Actors prevent data races, but **not atomicity across `await`**. State can change in between (actor *reentrancy*). Keep critical sections **synchronous**.

```swift
// ❌ Bug: island.food may change between the two awaits
func deposit(pineapples: [Pineapple], onto island: Island) async {
    var food = await island.food
    food += pineapples
    await island.store(food)
}
```

---

## 2. Migration Strategy
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/migrationstrategy/

Don't panic if you get thousands of warnings. A few changes usually remove many of them.

1. **Select a module.** Start from the **outermost** one (nothing depends on it). But fix **unsafe globals** and **implicitly-Sendable public types** in your dependencies early, because they cause many warnings.
2. **Stay in Swift 5 mode** and enable checks gradually, so problems show up as warnings:

   | Upcoming feature flag | Proposal |
   |---|---|
   | `DisableOutwardActorInference` | SE-0401 — no isolation inference from property wrappers |
   | `GlobalConcurrency` | SE-0412 — strict concurrency for global variables |
   | `InferSendableFromCaptures` | SE-0418 — infer `Sendable` for methods and key paths |

   Then enable **complete checking** (§3).
3. **Address warnings.** Principle: ***"express what is true now"***. Don't refactor yet. Treat the unsafe opt-outs you add as a to-do list for later.
4. **Iterate.** Move on to dependencies that needed workarounds. You don't need zero warnings before moving on.

---

## 3. Enable Data-Race Safety Checking
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/enabledataracesafety/

### Swift 6 language mode
```swift
// swift-tools-version: 6.0   → every target defaults to Swift 6 mode
let package = Package(
    name: "MyPackage",
    targets: [
        .target(name: "FullyMigrated"),
        .target(name: "NotQuiteReadyYet",
                swiftSettings: [.swiftLanguageMode(.v5)]),   // per-target
    ]
)
// Package-wide: swiftLanguageModes: [...]
// Supporting tools older than 6.0: swiftLanguageVersions: [.version("6"), .v5]
// (or a version-specific manifest like Package@swift-5.9.swift)
```
| Where | How |
|---|---|
| CLI | `swift build -Xswiftc -swift-version -Xswiftc 6` / `swiftc -swift-version 6` |
| Xcode | Build setting **Swift Language Version = 6** |
| xcconfig | `SWIFT_VERSION = 6;` |

### Complete checking as *warnings* (in Swift 5 mode)
```swift
.target(name: "MyTarget", swiftSettings: [
    .enableUpcomingFeature("StrictConcurrency")       // Swift 6.0+ tools
    // .enableExperimentalFeature("StrictConcurrency") // 5.9 / 5.10 tools
])
```
| Where | How |
|---|---|
| CLI | `swift build -Xswiftc -strict-concurrency=complete` |
| Xcode | **Strict Concurrency Checking = Complete** |
| xcconfig | `SWIFT_STRICT_CONCURRENCY = complete;` |

---

## 4. Common Compiler Errors (and fixes)
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/commonproblems/

### 4.1 Unsafe global and static variables
`error: global variable 'x' is not concurrency-safe because it is non-isolated global shared mutable state`
```swift
var supportedStyleCount = 42                        // ❌

@MainActor var supportedStyleCount = 42             // ✅ isolate it
let supportedStyleCount = 42                        // ✅ make it immutable
var supportedStyleCount: Int { 42 }                 // ✅ computed constant
nonisolated(unsafe) var supportedStyleCount = 42    // ⚠️ only if guarded by a lock or queue
```
A `static let` of a **non-Sendable class** is also a problem, because its internal state is shared. Fix it by isolating it to a global actor or by making the type `Sendable`.

### 4.2 Protocol conformance isolation mismatch
`error: main actor-isolated instance method 'applyStyle()' cannot be used to satisfy nonisolated protocol requirement`
```swift
protocol Styler { func applyStyle() }
@MainActor class WindowStyler: Styler { func applyStyle() {} }   // ❌
```
Fixes:
```swift
@MainActor protocol Styler { func applyStyle() }      // isolate the whole protocol
protocol Styler { @MainActor func applyStyle() }      // isolate one requirement (narrower)
@preconcurrency @MainActor protocol Styler { ... }    // stage in without breaking clients

protocol Styler { func applyStyle() async }           // async requirement: an isolated sync impl is OK
                                                      // (but every call site is affected)

@MainActor class WindowStyler: @preconcurrency Styler { // suppress the error + add runtime checks
    func applyStyle() {}
}

@MainActor class WindowStyler: Styler {
    nonisolated func applyStyle() {}                   // impl doesn't touch isolated state
}
```
**Conformance by proxy**: when an actor can't conform (for example, the protocol requires a superclass), create a separate class that conforms and use it from the actor.

### 4.3 Crossing isolation boundaries
`error: sending 'x' risks causing data races`

| Technique | Code |
|---|---|
| Make `Sendable` explicit (public types aren't implicitly Sendable) | `public struct ColorComponents: Sendable {}` |
| `@preconcurrency import` for a module that isn't migrated (Swift 6: error → warning; Swift 5: no diagnostic) | `@preconcurrency import UnmigratedModule` |
| **Fix latent isolation**: the most common case is a missing `@MainActor` | `@MainActor func updateStyle(...) async { applyBackground(c) }` |
| Pass a `@Sendable` function that computes the value | `func f(provider: @Sendable () -> ColorComponents) async` |
| `sending` argument | `func f(color: sending ColorComponents) async` |

Ways to make a type `Sendable`:
```swift
@MainActor public struct ColorComponents { }           // 1. global isolation
actor Style { private var background: ColorComponents } // 2. actor (move the data + its operations inside)
class Style: @unchecked Sendable {                      // 3. manual sync (queue or lock)
    private var background: ColorComponents
    private let queue: DispatchQueue
}
extension ColorComponents: @retroactive @unchecked Sendable {} // 4. retroactive conformance (use with extreme care)

final class Style: Sendable {                           // checked: final, no mutable state,
    private let background: ColorComponents             // superclass only NSObject
}

final class Style: Sendable {                           // composition of techniques
    private nonisolated(unsafe) var background: ColorComponents
    private let queue: DispatchQueue
    @MainActor private var foreground: ColorComponents
}
```

### 4.4 Non-isolated initialization
`error: main actor-isolated default value in a nonisolated context`
```swift
@MainActor class WindowStyler {
    private var primaryStyleName: String
    nonisolated init(name: String) { self.primaryStyleName = name }  // ✅ callable from anywhere
}
struct Stylers { static let window = WindowStyler(name: "x") }
```

### 4.5 Non-isolated deinitialization
A `deinit` is **always non-isolated**, even in an actor.
```swift
actor BackgroundStyler {
    private let store = StyleStore()
    deinit {
        Task { [store] in await store.stopNotifications() }  // capture only what you need
    }
}
```
⚠️ **Never capture `self`** (not even implicitly) in a `deinit`. Extending its lifetime **crashes**.

---

## 5. Incremental Adoption
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/incrementaladoption/

### Wrap callbacks with continuations
```swift
func updateStyle(backgroundColor: ColorComponents) async {
    await withCheckedContinuation { continuation in
        updateStyle(backgroundColor: backgroundColor) {
            continuation.resume()        // resume EXACTLY once
        }
    }
}
```
If you never resume, the task hangs forever. If you resume twice, a *checked* continuation crashes.

### Dynamic isolation
```swift
// Internal-only: keeps the API unchanged but hides the isolation (temporary fix)
class WindowStyler {
    @MainActor private var backgroundColor: ColorComponents
    func applyStyle() {
        MainActor.assumeIsolated { /* MainActor state */ }  // traps if not on main
    }
}

// Usage-only: the type is statically isolated, call sites use assumeIsolated
class UIStyler {
    @MainActor private let windowStyler: WindowStyler
    func applyStyle() { MainActor.assumeIsolated { windowStyler.applyStyle() } }
}

// Explicit switch in an async context (a migration aid, not a substitute for @MainActor)
await MainActor.run { let t = PersonalTransportation() }
```

### Missing annotations: unmarked Sendable closures
If an unmigrated API calls back on another thread but its closure isn't marked `@Sendable`, the compiler wrongly **infers `@MainActor`** for the closure body. That compiles but **crashes at runtime**.
```swift
JPKJetPack.jetPackConfiguration { @Sendable in     // mark the closure yourself
    Task { await self.applyConfiguration() }
}
```
(`-disable-dynamic-actor-isolation` turns off these runtime checks. ⚠️ That allows data races.)

### DispatchSerialQueue as an actor executor
```swift
actor LandingSite {
    private let queue = DispatchSerialQueue(label: "something")
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }
    func acceptTransport(_ t: PersonalTransportation) { /* runs on queue */ }
}
```

### Backwards compatibility for public API
```swift
@preconcurrency @MainActor
public class WindowStyler { }   // isolation is enforced only for clients with complete checking
```

### Dependencies and C/Objective-C
- Use `@preconcurrency` (on imports and conformances) for unmigrated dependencies.
- Annotate C/ObjC headers with `__attribute__((swift_attr("@Sendable" | "nonisolated" | "@UIActor" | "sending")))`, or with the Foundation macros:
  `NS_SWIFT_SENDABLE`, `NS_SWIFT_NONSENDABLE`, `NS_SWIFT_NONISOLATED`, `NS_SWIFT_UI_ACTOR`, `NS_SWIFT_SENDING`, `NS_SWIFT_ASYNC(...)`, `NS_SWIFT_DISABLE_ASYNC`, `NS_SWIFT_UNAVAILABLE_FROM_ASYNC(msg)`.
- If an ObjC member was wrongly inferred as `@MainActor` and crashes with `_dispatch_assert_queue_fail`, override it as `nonisolated` and report the problem to the library:
```swift
@MainActor final class MyJetPack: NSJetPack {
    override nonisolated class var supportsHighAltitude: Bool { true }
}
```

---

## 6. Migrating to Upcoming Language Features
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/featuremigration/

- Enable a feature with `-enable-upcoming-feature <Name>`. Some features have a **migration mode** that only emits warnings with fix-its.
- `swift package migrate` (SwiftPM, 6.2+) builds the package, applies fix-its, and updates the manifest. Start from a **clean git tree and a working build**.
```bash
swift package migrate --to-feature NonisolatedNonsendingByDefault
swift package migrate --targets TargetA --to-feature NonisolatedNonsendingByDefault
```
Example result: `func alwaysSwitch() async {}` becomes `@concurrent func alwaysSwitch() async {}`, and `.enableUpcomingFeature("NonisolatedNonsendingByDefault")` is added to the manifest. If the manifest can't be updated automatically (for example, `swiftSettings` is stored in a shared variable), add the setting by hand.

---

## 7. Source Compatibility
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/sourcecompatibility/

Swift 6 changes that can break existing source. Each one can be enabled early in Swift 5 mode with its flag:

| Flag | Effect |
|---|---|
| `NonfrozenEnumExhaustivity` (SE-0192) | A missing `@unknown default` becomes an **error** |
| `ConciseMagicFile` (SE-0274) | `#file` → `"Module/File.swift"` |
| `ForwardTrailingClosures` (SE-0286) | Forward-scan matching for multiple defaulted closures |
| `StrictConcurrency` (SE-0337) | Data-race errors (also enables `IsolatedDefaultValues`, `GlobalConcurrency`, `RegionBasedIsolation`) |
| `ImplicitOpenExistentials` (SE-0352) | Overload resolution with existentials and generics |
| `BareSlashRegexLiterals` (SE-0354) | `/.../` is parsed as a regex |
| `DeprecateApplicationMain` (SE-0383) | `@UIApplicationMain` / `@NSApplicationMain` → use `@main` |
| `ImportObjcForwardDeclarations` (SE-0384) | Forward-declared ObjC types become visible |
| `DisableOutwardActorInference` (SE-0401) | Property wrappers no longer infer isolation |
| `IsolatedDefaultValues` (SE-0411) | Default value expressions are isolation-checked |
| `GlobalConcurrency` (SE-0412) | Global variables are concurrency-checked |
| `RegionBasedIsolation` (SE-0414) | Tighter constraints on `assumeIsolated` |
| `InferSendableFromCaptures` (SE-0418) | Methods and key paths can be inferred `@Sendable` |
| `DynamicActorIsolation` (SE-0423) | Runtime isolation assertions |
| `GlobalActorIsolatedTypesUsability` (SE-0434) | Inference for non-Sendable globally-isolated functions |

---

## 8. Library Evolution (source and ABI impact)
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/libraryevolution/

`@preconcurrency` on an API stages in new requirements: no errors for clients with minimal checking, **warnings** for clients with complete checking or Swift 6 mode. It also mangles the symbol **without** concurrency annotations, which preserves the ABI. APIs imported from C, C++ and ObjC are automatically `@preconcurrency`.

| Change | Source | ABI | Mitigation |
|---|---|---|---|
| `struct S` → `struct S: Sendable` | ✅ | ✅ | — |
| `func g<T>` → `where T: Sendable` | ❌ | ❌ | `@preconcurrency` |
| closure → `@Sendable` closure | ❌ | ❌ | `@preconcurrency` on the function |
| `@MainActor` on a protocol or type | ❌ | ❌ | `@preconcurrency` (the ABI can still break when clients infer the isolation → mark them `nonisolated` explicitly) |
| `@MainActor` on a function or function type | ❌ | ❌ | `@preconcurrency` |
| `-> sending T` (result) | ✅ | ✅ | — |
| `sending` parameter | ❌ | ❌ | none yet |
| `@Sendable` → `sending` (closure param) | ✅ | ❌ | `@_silgen_name` + `__shared sending` (not needed for inits) |

```swift
@preconcurrency
public func performConcurrently(completion: @escaping @Sendable () -> Void) { }

@preconcurrency @MainActor
public func runOnMain() { }
```

---

## 9. Runtime Behavior
🔗 https://docs.swift.org/latest/documentation/swift-6-concurrency-migration-guide/runtimebehavior/

**Limit concurrency in task groups.** Each `addTask` allocates memory. Adding thousands of tasks up front is wasteful, so keep only *N* in flight:
```swift
let maxConcurrent = min(lotsOfWork.count, 10)

await withTaskGroup(of: Something.self) { group in
    var next = 0
    for _ in 0..<maxConcurrent {
        let item = lotsOfWork[next]
        group.addTask { await item.work() }          // or addTaskUnlessCancelled
        next += 1
    }
    for await result in group {
        process(result)
        if next < lotsOfWork.count {                 // a task finished → add the next one
            let item = lotsOfWork[next]
            group.addTask { await item.work() }
            next += 1
        }
    }
}
```
*(Slightly adjusted from the official snippet: each item is captured with a `let` instead of capturing the mutable `next` index inside the task.)*

---

## Quick decision guide
1. **Global `var`** → `let`, `@MainActor`, or `nonisolated(unsafe)` (only with a lock).
2. **"sending X risks data races"** → Is it UI code? Use `@MainActor`. Otherwise use a `Sendable` value type, `sending`, or an actor.
3. **Protocol mismatch** → isolate the protocol or requirement, make the impl `nonisolated`, or use `@preconcurrency` on the conformance.
4. **Unmigrated dependency** → `@preconcurrency import`.
5. **Public API change** → `@preconcurrency` to keep clients compiling.
6. **Callback API** → `withCheckedContinuation`.
7. **Already thread-safe through a lock or queue** → `@unchecked Sendable`.
