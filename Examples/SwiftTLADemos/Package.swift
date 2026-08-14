// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftTLADemos",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftTLADemos", targets: ["SwiftTLADemos"])
    ],
    dependencies: [
        .package(name: "SwiftTLA", path: "../..")
    ],
    targets: [
        .target(
            name: "SwiftTLADemos",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .testTarget(
            name: "SwiftTLADemosTests",
            dependencies: [
                "SwiftTLADemos",
                .product(name: "SwiftTLA", package: "SwiftTLA")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-warnings-as-errors"])
            ]
        )
    ]
)
