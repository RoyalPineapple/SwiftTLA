// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let settings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .unsafeFlags(["-warnings-as-errors"])
]

let package = Package(
    name: "SwiftTLA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftTLA", targets: ["SwiftTLA"]),
        .library(name: "SwiftTLAMacros", targets: ["SwiftTLAMacros"]),
        .library(name: "SwiftTLAModels", targets: ["SwiftTLAModels"]),
        .library(name: "UpstreamParity", targets: ["UpstreamParity"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0")
    ],
    targets: [
        .target(name: "SwiftTLA", dependencies: [
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftBasicFormat", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        ], swiftSettings: settings),
        .target(name: "SwiftTLAMacros", dependencies: ["SwiftTLA", "SwiftTLAPlugin"]),
        .macro(name: "SwiftTLAPlugin", dependencies: [
            "SwiftTLA",
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ]),
        .target(name: "SwiftTLAModels", dependencies: ["SwiftTLA", "SwiftTLAMacros"], swiftSettings: settings),
        .target(
            name: "UpstreamParity",
            dependencies: ["SwiftTLA", "SwiftTLAMacros"],
            exclude: ["Examples/AGENTS.md"],
            swiftSettings: settings
        ),
        .executableTarget(name: "tlc-validate", dependencies: ["SwiftTLA", "UpstreamParity"], path: "Sources/TLCValidate"),
        .testTarget(name: "SwiftTLATests", dependencies: [
            "SwiftTLA",
            "SwiftTLAModels",
            "SwiftTLAMacros",
            "UpstreamParity"
        ], swiftSettings: settings)
    ]
)
