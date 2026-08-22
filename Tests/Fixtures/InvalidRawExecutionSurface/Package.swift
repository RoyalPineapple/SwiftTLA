// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "InvalidRawExecutionSurface",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "SwiftTLA", path: "../../..")],
  targets: [
    .executableTarget(
      name: "InvalidRawExecutionSurface",
      dependencies: [.product(name: "SwiftTLA", package: "SwiftTLA")]
    )
  ]
)
