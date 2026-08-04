// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Examples",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../"),
    ],
    targets: [
        .target(
            name: "Examples",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAGeneration", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA"),
            ],
            path: "."
        ),
    ]
)
