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
        .library(name: "AlgorithmConformance", targets: ["AlgorithmConformance"]),
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
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
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
        .target(name: "AlgorithmConformance", dependencies: ["SwiftTLA", "SwiftTLAMacros"], swiftSettings: settings),
        .target(
            name: "UpstreamParity",
            dependencies: [
                "SwiftTLA",
                "SwiftTLAMacros",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            exclude: ["Examples/AGENTS.md"],
            swiftSettings: settings
        ),
        .target(
            name: "PublicWorkflowGeneratedFixtures",
            dependencies: ["SwiftTLA", "SwiftTLAMacros"],
            path: "Tests/Fixtures/PublicWorkflowConformance/Generated",
            exclude: [
                "builder-observation.json",
                "counter.config.json",
                "counter-mismatch.config.json",
                "generated-observation.json"
            ],
            swiftSettings: settings
        ),
        .executableTarget(name: "tlc-validate", dependencies: ["SwiftTLA", "UpstreamParity"], path: "Sources/TLCValidate"),
        // Fast semantic-core tests. Keep this target free of UpstreamParity so
        // K1–K4 witnesses can compile and run without the parity corpus.
        .testTarget(name: "SwiftTLATests", dependencies: [
            "SwiftTLA",
            "SwiftTLAModels",
            "SwiftTLAMacros",
            "AlgorithmConformance"
        ], swiftSettings: settings),
        // Slower corpus, oracle, governance, and public-workflow tests.
        .testTarget(name: "SwiftTLAParityTests", dependencies: [
            "SwiftTLA",
            "SwiftTLAModels",
            "SwiftTLAMacros",
            "UpstreamParity",
            "PublicWorkflowGeneratedFixtures"
        ], path: "Tests/SwiftTLAParityTests", swiftSettings: settings)
    ]
)
