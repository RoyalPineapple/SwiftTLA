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
            name: "ExamplesLibrary",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA"),
            ],
            path: "Sources/Examples"
        ),
        .executableTarget(
            name: "Examples",
            dependencies: [
                "ExamplesLibrary",
                .product(name: "SwiftTLAUI", package: "SwiftTLA"),
            ],
            path: "Sources/ExamplesApp"
        ),
    ]
)
