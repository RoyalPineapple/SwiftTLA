// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "InvalidValidatedMacro",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(name: "SwiftTLA", path: "../../..")
  ],
  targets: [
    .executableTarget(
      name: "InvalidValidatedMacro",
      dependencies: [
        .product(name: "SwiftTLA", package: "SwiftTLA"),
        .product(name: "SwiftTLAMacros", package: "SwiftTLA")
      ]
    )
  ]
)
