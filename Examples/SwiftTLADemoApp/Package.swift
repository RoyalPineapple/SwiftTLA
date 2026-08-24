// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftTLADemoApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftTLA", path: "../.."),
        .package(path: "../SwiftTLADemos")
    ],
    targets: [
        .executableTarget(
            name: "SwiftTLADemoApp",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLADemos", package: "SwiftTLADemos")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
