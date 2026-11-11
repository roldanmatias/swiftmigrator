// swift-tools-version: 6.2
// "After" fixture: BookingSync in Swift 6 language mode (complete data-race checking),
// with approachable-concurrency settings chosen per target (playbook R17).

import PackageDescription

let package = Package(
    name: "BookingSync",
    // Unchanged: @Observable needs macOS 14 / iOS 17, which the package already required.
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BookingSync", targets: ["BookingSync"]),
    ],
    targets: [
        // Vendored SDK: not ours, stays in Swift 5 mode (R10, R16).
        .target(name: "LegacyCalendarAPI", swiftSettings: [.swiftLanguageMode(.v5)]),

        // Library: nonisolated by default (R17), `nonisolated(nonsending)` by default (R18).
        .target(
            name: "BookingSync",
            dependencies: ["LegacyCalendarAPI"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .treatAllWarnings(as: .error),
            ]
        ),

        // App target: Approachable Concurrency, MainActor by default (R17).
        .executableTarget(
            name: "BookingSyncDemo",
            dependencies: ["BookingSync", "LegacyCalendarAPI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .treatAllWarnings(as: .error),
            ]
        ),

        .testTarget(name: "BookingSyncTests", dependencies: ["BookingSync", "LegacyCalendarAPI"]),
    ]
)
