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
        .library(name: "SwiftTLAGenerator", targets: ["SwiftTLAGenerator"]),
        .library(name: "SwiftTLAExamples", targets: ["SwiftTLAExamples"]),
        .executable(name: "demo", targets: ["SwiftTLADemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ],
    targets: [
        .target(name: "SwiftTLA", dependencies: [], swiftSettings: settings),
        .target(name: "SwiftTLAGenerator", dependencies: [
            "SwiftTLA",
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftBasicFormat", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        ], swiftSettings: settings),
        .target(name: "SwiftTLAMacros", dependencies: ["SwiftTLAPlugin"]),
        .macro(name: "SwiftTLAPlugin", dependencies: [
            "SwiftTLA",
            "SwiftTLAGenerator",
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ]),
        .target(name: "SwiftTLAExamples", dependencies: ["SwiftTLA"]),
        .executableTarget(name: "SwiftTLADemo", dependencies: ["SwiftTLA", "SwiftTLAGenerator", "SwiftTLAExamples", "SwiftTLAMacros"]),
        .testTarget(name: "SwiftTLATests", dependencies: ["SwiftTLA", "SwiftTLAGenerator"], swiftSettings: settings),
    ]
)
