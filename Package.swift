// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let settings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .unsafeFlags(["-warnings-as-errors"]),
]

let package = Package(
    name: "SwiftTLA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftTLA", targets: ["SwiftTLA"]),
        .library(name: "SwiftTLAMacros", targets: ["SwiftTLAMacros"]),
        .library(name: "SwiftTLAUI", targets: ["SwiftTLAUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ],
    targets: [
        .target(name: "SwiftTLA", dependencies: [
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftBasicFormat", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        ], swiftSettings: settings),
        .target(name: "SwiftTLAMacros", dependencies: ["SwiftTLAPlugin"]),
        .macro(name: "SwiftTLAPlugin", dependencies: [
            "SwiftTLA",
            "SwiftTLAUI",
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ]),
        .target(name: "SwiftTLAUI", dependencies: ["SwiftTLA"]),
        .testTarget(name: "SwiftTLATests", dependencies: ["SwiftTLA"], swiftSettings: settings),
    ]
)
