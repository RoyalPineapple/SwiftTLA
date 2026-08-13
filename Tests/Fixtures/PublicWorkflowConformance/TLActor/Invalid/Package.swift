// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "PublicWorkflowTLAActorInvalid",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "SwiftTLA", path: "../../../../..")],
  targets: [.executableTarget(
    name: "PublicWorkflowTLAActorInvalid",
    dependencies: [
      .product(name: "SwiftTLA", package: "SwiftTLA"),
      .product(name: "SwiftTLAMacros", package: "SwiftTLA")
    ]
  )]
)
