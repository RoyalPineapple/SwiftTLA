// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpecExpressionMacro",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "SpecExpressionMacro",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA")
            ]
        )
    ]
)
