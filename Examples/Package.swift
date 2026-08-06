// swift-tools-version: 5.9
import PackageDescription

/// Validated upstream ports live in the root `UpstreamParity` product.
/// This package is a thin CLI that lists and emits them. Views come later.
let package = Package(
    name: "Examples",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../"),
    ],
    targets: [
        .executableTarget(
            name: "Examples",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "UpstreamParity", package: "SwiftTLA"),
            ],
            path: "Sources/ExamplesCLI"
        ),
    ]
)
