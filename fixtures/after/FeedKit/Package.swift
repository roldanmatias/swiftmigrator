// swift-tools-version: 6.0
// "After" fixture: FeedKit in Swift 6 language mode (complete data-race checking).

import PackageDescription

let package = Package(
    name: "FeedKit",
    // Raised from macOS 13 / iOS 16 to adopt the Observation framework (@Observable).
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FeedKit", targets: ["FeedKit"]),
    ],
    targets: [
        // Unmigrated third-party-style dependency: stays in Swift 5 mode.
        .target(
            name: "LegacyNetworking",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(name: "FeedKit", dependencies: ["LegacyNetworking"]),
        .testTarget(name: "FeedKitTests", dependencies: ["FeedKit", "LegacyNetworking"]),
    ]
)
