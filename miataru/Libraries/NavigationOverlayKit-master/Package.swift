// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NavigationOverlayKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "NavigationOverlayKit",
            targets: ["NavigationOverlayKit"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "NavigationOverlayKit",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NavigationOverlayKitTests",
            dependencies: ["NavigationOverlayKit"],
            path: "Tests"
        )
    ]
)
