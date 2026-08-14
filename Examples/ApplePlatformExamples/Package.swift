// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ApplePlatformExamples",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "ApplePlatformBluetooth", targets: ["ApplePlatformBluetooth"]),
        .library(name: "ApplePlatformAVPipeline", targets: ["ApplePlatformAVPipeline"]),
        .executable(name: "bluetooth-example", targets: ["BluetoothExample"]),
        .executable(name: "av-pipeline-example", targets: ["AVPipelineExample"])
    ],
    dependencies: [
        .package(name: "SwiftTLA", path: "../..")
    ],
    targets: [
        .target(
            name: "ApplePlatformBluetooth",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA")
            ]
        ),
        .target(
            name: "ApplePlatformAVPipeline",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA")
            ]
        ),
        .executableTarget(
            name: "BluetoothExample",
            dependencies: ["ApplePlatformBluetooth"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
        .executableTarget(
            name: "AVPipelineExample",
            dependencies: ["ApplePlatformAVPipeline"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
        .testTarget(
            name: "ApplePlatformExamplesTests",
            dependencies: ["ApplePlatformBluetooth"]
        )
    ]
)
