// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "InvalidTypedFacade",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "SwiftTLA", path: "../../..")],
  targets: [
    .executableTarget(
      name: "InvalidTypedFacade",
      dependencies: [.product(name: "SwiftTLA", package: "SwiftTLA")]
    )
  ]
)
