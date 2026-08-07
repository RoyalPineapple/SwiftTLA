// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftTLAVerified",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "SwiftTLAVerified", targets: ["SwiftTLAVerified"]),
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
    ]
)
