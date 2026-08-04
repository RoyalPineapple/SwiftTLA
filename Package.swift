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
        .library(name: "SwiftTLAGeneration", targets: ["SwiftTLAGeneration"]),
        .library(name: "SwiftTLAExamples", targets: ["SwiftTLAExamples"]),
        .library(name: "SwiftTLASwiftUI", targets: ["SwiftTLASwiftUI"]),
        .executable(name: "demo", targets: ["SwiftTLADemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ],
    targets: [
        .target(name: "SwiftTLA", dependencies: [], swiftSettings: settings),
        .target(name: "SwiftTLAGeneration", dependencies: [
            "SwiftTLA",
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftBasicFormat", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        ], swiftSettings: settings),
        .target(name: "SwiftTLAMacros", dependencies: ["SwiftTLAPlugin"]),
        .macro(name: "SwiftTLAPlugin", dependencies: [
            "SwiftTLA",
            "SwiftTLAGeneration",
            "SwiftTLASwiftUI",
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ]),
        .target(name: "SwiftTLAExamples", dependencies: ["SwiftTLA", "SwiftTLAGeneration", "SwiftTLAMacros"]),
        .target(name: "SwiftTLASwiftUI", dependencies: [
            "SwiftTLA",
            "SwiftTLAGeneration",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        ]),
        .executableTarget(name: "SwiftTLADemo", dependencies: ["SwiftTLA", "SwiftTLAGeneration", "SwiftTLAExamples", "SwiftTLAMacros"]),
        .testTarget(name: "SwiftTLATests", dependencies: ["SwiftTLA", "SwiftTLAGeneration"], swiftSettings: settings),
    ]
)
