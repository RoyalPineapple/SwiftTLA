// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftTLADemo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftTLADemo",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAExamples", package: "SwiftTLA"),
            ]
        ),
    ]
)
