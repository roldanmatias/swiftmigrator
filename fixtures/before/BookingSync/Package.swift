// swift-tools-version: 5.9
// "Before" fixture: Swift 5 language mode, minimal concurrency checking.

import PackageDescription

let package = Package(
    name: "BookingSync",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BookingSync", targets: ["BookingSync"]),
    ],
    targets: [
        // Simulates a vendored calendar SDK that will NOT be migrated.
        .target(name: "LegacyCalendarAPI"),
        .target(name: "BookingSync", dependencies: ["LegacyCalendarAPI"]),
        // A tiny "app" target: UI glue on top of the library.
        .executableTarget(name: "BookingSyncDemo", dependencies: ["BookingSync", "LegacyCalendarAPI"]),
        .testTarget(name: "BookingSyncTests", dependencies: ["BookingSync", "LegacyCalendarAPI"]),
    ]
)
