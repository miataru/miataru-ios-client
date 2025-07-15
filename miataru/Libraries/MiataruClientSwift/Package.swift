// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MiataruAPIClient",
    platforms: [
        .macOS(.v12),
        .iOS(.v13)
    ],
    products: [
        .library(name: "MiataruAPIClient", targets: ["MiataruAPIClient"]),
        .executable(name: "MiataruTestApp", targets: ["MiataruTestApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MiataruAPIClient",
            dependencies: [],
            path: "Sources/MiataruAPIClient"
        ),
        .executableTarget(
            name: "MiataruTestApp",
            dependencies: ["MiataruAPIClient"],
            path: "Examples/MiataruTestApp",
            exclude: ["Dockerfile"]
        )
    ]
) 