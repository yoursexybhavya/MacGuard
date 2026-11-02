// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGuard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacGuard",
            targets: ["MacGuard"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacGuard",
            dependencies: [],
            path: "Sources/MacGuard",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "MacGuardTests",
            dependencies: ["MacGuard"],
            path: "Tests/MacGuardTests",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
