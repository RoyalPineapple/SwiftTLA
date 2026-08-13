// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GeneratedMachineDocumentation",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "SwiftTLA", path: "../../..")],
    targets: [
        .target(
            name: "GeneratedMachineDocumentation",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA")
            ]
        ),
        .testTarget(
            name: "GeneratedMachineDocumentationTests",
            dependencies: ["GeneratedMachineDocumentation"]
        )
    ]
)
