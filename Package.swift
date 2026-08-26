// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let settings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
    name: "SwiftTLA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftTLA", targets: ["SwiftTLA"]),
        .library(name: "SwiftTLAMacros", targets: ["SwiftTLAMacros"])
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
        // Repository tools export the canonical corpus without compiling the
        // full example gallery.
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
                "CanonicalUpstreamCorpus"
            ],
            exclude: ["Examples/AGENTS.md", "CanonicalCorpus"],
            swiftSettings: settings
        ),
        .executableTarget(
            name: "tlc-validate",
            dependencies: ["SwiftTLA", "UpstreamParity"],
            path: "Sources/TLCValidate"
        ),
        // Internal CI appendix: exports the canonical upstream Algorithm
        // corpus for independent translator/TLC evidence. It is deliberately
        // not a package product or application-facing API.
        .executableTarget(
            name: "canonical-corpus-export",
            dependencies: ["SwiftTLA", "CanonicalUpstreamCorpus"],
            path: "Tools/CanonicalCorpusExport"
        ),
        // Fast semantic-core tests. Keep this target free of UpstreamParity so
        // Fast semantic witnesses compile and run without the parity corpus.
        .testTarget(name: "SwiftTLATests", dependencies: [
            "SwiftTLA",
            "SwiftTLAMacros",
            "SwiftTLAPlugin",
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax")
        ], swiftSettings: settings),
        // Slower corpus, oracle, and governance tests.
        .testTarget(name: "SwiftTLAParityTests", dependencies: [
            "SwiftTLA",
            "SwiftTLAMacros",
            "UpstreamParity"
        ], path: "Tests/SwiftTLAParityTests", swiftSettings: settings)
    ]
)
