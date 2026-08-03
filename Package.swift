// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let settings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .unsafeFlags(["-warnings-as-errors"]),
]

let package = Package(
    name: "SwiftTLA",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftTLA", targets: ["SwiftTLA"]),
        .library(name: "SwiftTLAGenerator", targets: ["SwiftTLAGenerator"]),
        .executable(name: "swift-tla", targets: ["SwiftTLACLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ],
    targets: [
        .target(name: "SwiftTLA", dependencies: [], swiftSettings: settings),
        .target(name: "SwiftTLAGenerator", dependencies: [
            "SwiftTLA",
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftBasicFormat", package: "swift-syntax"),
        ], swiftSettings: settings),
        .target(name: "SwiftTLAMacrosInterface", dependencies: ["SwiftTLAMacros"]),
        .macro(name: "SwiftTLAMacros", dependencies: [
            "SwiftTLA",
            "SwiftTLAGenerator",
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        ]),
        .executableTarget(name: "SwiftTLACLI", dependencies: [
            "SwiftTLA", "SwiftTLAGenerator",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ], swiftSettings: settings),
        .testTarget(name: "SwiftTLATests", dependencies: ["SwiftTLA", "SwiftTLAGenerator"], swiftSettings: settings),
        .testTarget(name: "SwiftTLAMacroTests", dependencies: ["SwiftTLA", "SwiftTLAMacrosInterface"]),
    ]
)
