# Swift Versions — Key Features

The most important feature in each Swift release, with a short example for each.

---

## Swift 1.0 (2014) — Optionals & type safety
Values that might be missing are written explicitly as `Optional` types.
```swift
var name: String? = nil
if let unwrapped = name {
    print("Hello, \(unwrapped)")
} else {
    print("No name")
}
```

## Swift 1.2 (2015) — Multiple optional bindings & native `Set`
```swift
if let a = Int("1"), let b = Int("2"), a < b {
    print(a + b)
}
let unique: Set = [1, 2, 2, 3]   // {1, 2, 3}
```

## Swift 2.0 (2015) — Error handling, `guard`, protocol extensions
```swift
enum FileError: Error { case notFound }

func load(_ path: String) throws -> String {
    guard !path.isEmpty else { throw FileError.notFound }
    return "contents"
}

do {
    let data = try load("")
    print(data)
} catch {
    print("Failed: \(error)")
}
```

## Swift 2.2 (2016) — `#selector` and deprecation of C-style syntax
```swift
button.addTarget(self, action: #selector(didTap), for: .touchUpInside)
// `++`, `--` and C-style `for` loops are deprecated
```

## Swift 3.0 (2016) — API Design Guidelines ("The Grand Renaming")
Cleaner, Swifty API names, and `fileprivate` / `open` access levels.
```swift
// Swift 2
// let s = array.joinWithSeparator(", ")
// Swift 3
let s = ["a", "b"].joined(separator: ", ")
let color = UIColor.red            // was UIColor.redColor()
```

## Swift 4.0 (2017) — `Codable`
Automatic JSON encoding/decoding. Also: smart key paths, multi-line strings.
```swift
struct User: Codable {
    let id: Int
    let name: String
}

let json = #"{"id": 1, "name": "Ana"}"#.data(using: .utf8)!
let user = try JSONDecoder().decode(User.self, from: json)
let name = user[keyPath: \User.name]
```

## Swift 4.1 (2018) — Conditional conformance & synthesized `Equatable`/`Hashable`
```swift
struct Point: Hashable { let x: Int; let y: Int }   // == and hash synthesized

// Array is Equatable only when its Element is Equatable
let equal = [Point(x: 1, y: 2)] == [Point(x: 1, y: 2)]  // true
```

## Swift 4.2 (2018) — `CaseIterable` & unified random API
```swift
enum Direction: CaseIterable { case north, south, east, west }

print(Direction.allCases.count)        // 4
let dice = Int.random(in: 1...6)
let pick = Direction.allCases.randomElement()
```

## Swift 5.0 (2019) — ABI stability & `Result`
The Swift runtime ships with the OS; also raw strings.
```swift
func fetch(completion: (Result<String, Error>) -> Void) {
    completion(.success("data"))
}

fetch { result in
    switch result {
    case .success(let value): print(value)
    case .failure(let error): print(error)
    }
}
```

## Swift 5.1 (2019) — Opaque types (`some`) & property wrappers
The foundation of SwiftUI. Also: implicit returns in single-expression functions, module stability.
```swift
@propertyWrapper
struct Clamped {
    private var value = 0
    var wrappedValue: Int {
        get { value }
        set { value = min(max(newValue, 0), 100) }
    }
}

struct Volume { @Clamped var level: Int }

func makeShape() -> some Equatable { 42 }
```

## Swift 5.2 (2020) — `callAsFunction` & key paths as functions
```swift
struct Multiplier {
    let factor: Int
    func callAsFunction(_ x: Int) -> Int { x * factor }
}
let triple = Multiplier(factor: 3)
print(triple(5))                        // 15

let names = users.map(\.name)
```

## Swift 5.3 (2020) — Multiple trailing closures & multi-pattern `catch`
```swift
UIView.animate(withDuration: 0.3) {
    view.alpha = 0
} completion: { _ in
    view.removeFromSuperview()
}
```

## Swift 5.4 (2021) — Result builders
Standardized the DSL feature behind SwiftUI's view syntax.
```swift
@resultBuilder
struct StringBuilder {
    static func buildBlock(_ parts: String...) -> String {
        parts.joined(separator: " ")
    }
}

@StringBuilder func greeting() -> String {
    "Hello"
    "World"
}
print(greeting())   // "Hello World"
```

## Swift 5.5 (2021) — `async`/`await`, actors, structured concurrency
```swift
actor Counter {
    private var value = 0
    func increment() -> Int { value += 1; return value }
}

func loadData() async throws -> Data {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://example.com")!)
    return data
}

Task {
    let counter = Counter()
    print(await counter.increment())
}
```

## Swift 5.6 (2022) — `any` keyword for existential types
```swift
protocol Shape { func area() -> Double }

let shapes: [any Shape] = []          // explicit existential
func draw(_ shape: some Shape) { }    // generic (static dispatch)
```

## Swift 5.7 (2022) — `if let` shorthand & Regex
```swift
let username: String? = "ana"
if let username {                      // was: if let username = username
    print(username)
}

let match = "Order #1234".firstMatch(of: /#(\d+)/)
```

## Swift 5.8 (2023) — `@backDeployed` & implicit `self` in closures
```swift
extension Text {
    @available(iOS 15, *)
    @backDeployed(before: iOS 17)
    func newModifier() -> some View { self }
}
```

## Swift 5.9 (2023) — Macros, `if`/`switch` expressions, parameter packs
Enables `@Observable` and SwiftData's `@Model`.
```swift
let label = if score > 90 { "A" } else { "B" }

@Observable
class Model {
    var count = 0
}

#Preview { ContentView() }
```

## Swift 5.10 (2024) — Complete strict concurrency checking
Full data-race checking available in Swift 5 mode; `nonisolated(unsafe)` escape hatch.
```swift
// Build setting: SWIFT_STRICT_CONCURRENCY = complete
nonisolated(unsafe) var legacyCache: [String: Int] = [:]
```

## Swift 6.0 (2024) — Data-race safety by default & typed throws
Swift 6 language mode turns concurrency data races into compile-time errors.
```swift
enum ParseError: Error { case invalid }

func parse(_ s: String) throws(ParseError) -> Int {
    guard let n = Int(s) else { throw .invalid }
    return n
}

do {
    _ = try parse("x")
} catch {
    // `error` is statically typed as ParseError
    print(error)
}
```

## Swift 6.1 (2025) — Trailing commas everywhere & `nonisolated` on types
```swift
func configure(
    name: String,
    age: Int,              // trailing comma allowed in parameter lists
) { }

nonisolated struct Formatter {
    func format(_ x: Int) -> String { "\(x)" }
}
```

## Swift 6.2 (2025) — Approachable concurrency, `InlineArray`, `Span`
Code can run on the main actor by default, and `@concurrent` makes moving work off it explicit.
```swift
// With default MainActor isolation enabled
final class ViewModel {
    var items: [String] = []

    @concurrent
    func heavyWork() async -> [String] {   // explicitly runs off the main actor
        (1...1000).map(String.init)
    }
}

var buffer: InlineArray<4, Int> = [1, 2, 3, 4]   // fixed-size, stack-allocated
```
