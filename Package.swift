// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let settings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .unsafeFlags(["-warnings-as-errors"])
]

let executableSettings: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"])
]

let package = Package(
    name: "SwiftTLA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftTLA", targets: ["SwiftTLA"]),
        .library(name: "SwiftTLAMacros", targets: ["SwiftTLAMacros"]),
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
        .target(name: "SwiftTLAMacros", dependencies: ["SwiftTLA", "SwiftTLAPlugin"], swiftSettings: settings),
        .macro(name: "SwiftTLAPlugin", dependencies: [
            "SwiftTLA",
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ], swiftSettings: settings),
        // The externally qualified upstream backbone is its own source target
        // so its exact models can be exported without compiling the full
        // example gallery. UpstreamParity re-exports these public types.
        .target(
            name: "CanonicalUpstreamCorpus",
            dependencies: ["SwiftTLA", "SwiftTLAMacros"],
            path: "Sources/UpstreamParity/CanonicalCorpus",
            swiftSettings: settings
        ),
        .target(
            name: "UpstreamParity",
            dependencies: [
                "SwiftTLA",
                "SwiftTLAMacros",
                "CanonicalUpstreamCorpus",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            exclude: ["Examples/AGENTS.md", "CanonicalCorpus"],
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
        .executableTarget(
            name: "tlc-validate",
            dependencies: ["SwiftTLA", "UpstreamParity"],
            path: "Sources/TLCValidate",
            swiftSettings: executableSettings
        ),
        // Internal CI appendix: exports the canonical upstream Algorithm
        // corpus for independent translator/TLC evidence. It is deliberately
        // not a package product or application-facing API.
        .executableTarget(
            name: "canonical-corpus-export",
            dependencies: ["SwiftTLA", "CanonicalUpstreamCorpus"],
            path: "Tools/CanonicalCorpusExport",
            swiftSettings: executableSettings
        ),
        // Fast semantic-core tests. Keep this target free of UpstreamParity so
        // Fast semantic witnesses compile and run without the parity corpus.
        .testTarget(name: "SwiftTLATests", dependencies: [
            "SwiftTLA",
            "SwiftTLAMacros"
        ], swiftSettings: settings),
        // Slower corpus, oracle, governance, and public-workflow tests.
        .testTarget(name: "SwiftTLAParityTests", dependencies: [
            "SwiftTLA",
            "SwiftTLAMacros",
            "UpstreamParity",
            "PublicWorkflowGeneratedFixtures"
        ], path: "Tests/SwiftTLAParityTests", swiftSettings: settings)
    ]
)
