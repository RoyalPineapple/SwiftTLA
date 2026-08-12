// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "PublicWorkflowTLAActorValid",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "SwiftTLA", path: "../../../../..")],
  targets: [.executableTarget(
    name: "PublicWorkflowTLAActorValid",
    dependencies: [
      .product(name: "SwiftTLA", package: "SwiftTLA"),
      .product(name: "SwiftTLAMacros", package: "SwiftTLA")
    ]
  )]
)
