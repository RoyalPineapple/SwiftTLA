// swift-tools-version: 5.9
import PackageDescription

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
                .product(name: "SwiftTLAMacros", package: "SwiftTLA"),
                .product(name: "SwiftTLAUI", package: "SwiftTLA"),
            ],
            path: "."
        ),
    ]
)
