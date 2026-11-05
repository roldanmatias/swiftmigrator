# swiftmigrator

An AI agent pipeline that migrates Swift codebases to **Swift 6** and modern Swift APIs, file by file. Each file is migrated, compiled, tested and linted, and failed attempts are retried using the compiler and test errors.

Large-scale migrations follow rules that are mostly mechanical but full of edge cases:
- completion handlers → `async`/`await`
- `ObservableObject` → `@Observable`
- XCTest → Swift Testing
- strict concurrency (`Sendable`, actors, isolation)

swiftmigrator combines **deterministic tooling** (SwiftSyntax, SwiftPM, the compiler) with an **LLM agent** guided by an explicit, testable playbook.

## Status

| Component | Status |
|---|---|
| Migration playbook (rules the agent follows) | ✅ Done |
| Reference fixture, migrated by hand (before → after) | ✅ Done |
| Concurrency notes | ✅ Done |
| `scanner`: SwiftSyntax CLI that builds a prioritized queue of files to migrate | 🚧 Planned |
| `pipeline`: agent loop (migrate → compile → test → lint → retry) with logging | 🚧 Planned |
| Evals, optimizations, orchestration | 🚧 Planned |

## Repository layout

```
swiftmigrator/
├── playbook/
│   └── MIGRATION_PLAYBOOK.md    # Numbered rules (R1–R16) used as agent prompt context
├── fixtures/
│   ├── before/FeedKit/          # Swift 5 package with planted migration issues
│   │   └── MIGRATION_TASKS.md   # The 20 issues, their expected fixes, and links to the notes
│   └── after/FeedKit/           # The same package migrated by hand to Swift 6
└── notes/
    ├── swift6-concurrency.md    # Cheat sheet of the official Swift 6 migration guide
    └── swift_versions.md        # Key features of each Swift release
```

## The playbook

[`playbook/MIGRATION_PLAYBOOK.md`](playbook/MIGRATION_PLAYBOOK.md) is written to be loaded as prompt context for the agent. It contains:

- **Prime directives:** preserve behavior, express what is true now, the compiler is the oracle, prefer safe fixes over unsafe opt-outs.
- **Process:** module-level steps and the per-file build/test/retry loop.
- **Diagnostic → rule lookup table:** maps compiler error text to the rule that fixes it.
- **16 rules**, each with before/after code and edge cases. They cover global state, `Sendable`, isolation, protocol mismatches, `deinit`, unmigrated dependencies, actor reentrancy, task-group limits, public API compatibility, continuations, tests, and package settings.
- **Guardrails:** forbidden actions, when each unsafe opt-out is allowed, and when to escalate to a human.
- **A JSON report format** for each file, so the pipeline can log which rules the agent applied.

## The FeedKit fixture

FeedKit is a small news-feed library (about 200 lines) that serves as the reference migration. Every rule in the playbook is backed by a real change in it.

- `fixtures/before/FeedKit` is written in Swift 5 and contains common pre-concurrency patterns:
  - mutable globals
  - lock-protected singletons
  - callback APIs
  - `DispatchQueue.main.async` UI state
  - an actor `deinit` calling an isolated method
  - a read-modify-write across `await`s
  - an unbounded task group
  - an unmigrated dependency (`LegacyNetworking`)
- `fixtures/after/FeedKit` is the same package in the Swift 6 language mode, using `@Observable` and Swift Testing.

| | Before | After |
|---|---|---|
| Language mode | Swift 5 | Swift 6 (`LegacyNetworking` stays on 5) |
| Warnings with complete concurrency checking | 18 | **0** |
| Tests | 5 XCTest | 9 Swift Testing tests (11 cases), including regression tests for concurrency bugs the compiler can't detect |

Try it:

```bash
cd fixtures/before/FeedKit
swift build -Xswiftc -strict-concurrency=complete   # see the warnings
swift test

cd ../../after/FeedKit
swift build && swift test --parallel                # Swift 6 mode, no warnings
```

## Requirements

- Swift 6.0+ toolchain (Xcode 16+)
- macOS 14+ for the `after` fixture (Observation framework)

## References

- [Swift 6 Migration Guide](https://docs.swift.org/latest/documentation/migrationguide), the official documentation from swift.org
- [Swift Testing](https://developer.apple.com/documentation/testing)
- [Observation](https://developer.apple.com/documentation/observation)
