// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftTLAVerified",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "SwiftTLAVerified", targets: ["SwiftTLAVerified"]),
        .executable(name: "ble-scan", targets: ["BLEScan"]),
        .executable(name: "camera", targets: ["MediaScan"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .target(
            name: "SwiftTLAVerified",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA"),
            ]
        ),
        .executableTarget(
            name: "BLEScan",
            dependencies: ["SwiftTLAVerified"]
        ),
        .executableTarget(
            name: "MediaScan",
            dependencies: ["SwiftTLAVerified"]
        ),
    ]
)
