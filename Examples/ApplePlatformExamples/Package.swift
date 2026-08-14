// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ApplePlatformExamples",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "Bluetooth", targets: ["Bluetooth"]),
        .library(name: "AVPipeline", targets: ["AVPipeline"]),
        .executable(name: "bluetooth-example", targets: ["BluetoothExample"]),
        .executable(name: "bluetooth-cli", targets: ["BluetoothCLI"]),
        .executable(name: "av-pipeline-example", targets: ["AVPipelineExample"])
    ],
    dependencies: [
        .package(name: "SwiftTLA", path: "../..")
    ],
    targets: [
        .target(
            name: "Bluetooth",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA")
            ]
        ),
        .target(
            name: "AVPipeline",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA")
            ]
        ),
        .executableTarget(
            name: "BluetoothExample",
            dependencies: ["Bluetooth"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
        .executableTarget(
            name: "BluetoothCLI",
            dependencies: ["Bluetooth"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
        .executableTarget(
            name: "AVPipelineExample",
            dependencies: ["AVPipeline"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
        .testTarget(
            name: "ApplePlatformExamplesTests",
            dependencies: ["Bluetooth"]
        )
    ]
)
