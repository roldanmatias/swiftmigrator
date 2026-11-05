// swift-tools-version: 5.9
// "Before" fixture: Swift 5 language mode, minimal concurrency checking.

import PackageDescription

let package = Package(
    name: "FeedKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "FeedKit", targets: ["FeedKit"]),
    ],
    targets: [
        // Simulates a third-party / legacy dependency that will NOT be migrated.
        .target(name: "LegacyNetworking"),
        .target(name: "FeedKit", dependencies: ["LegacyNetworking"]),
        .testTarget(name: "FeedKitTests", dependencies: ["FeedKit", "LegacyNetworking"]),
    ]
)
