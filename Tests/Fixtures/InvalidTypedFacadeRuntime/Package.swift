// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "InvalidTypedFacadeRuntime",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "SwiftTLA", path: "../../..")],
  targets: [
    .executableTarget(
      name: "InvalidTypedFacadeRuntime",
      dependencies: [.product(name: "SwiftTLA", package: "SwiftTLA")]
    )
  ]
)
