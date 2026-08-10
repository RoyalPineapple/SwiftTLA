// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "InvalidCollectionPredicateMacro",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(name: "SwiftTLA", path: "../../..")
  ],
  targets: [
    .executableTarget(
      name: "InvalidCollectionPredicateMacro",
      dependencies: [
        .product(name: "SwiftTLA", package: "SwiftTLA"),
        .product(name: "SwiftTLAMacros", package: "SwiftTLA")
      ]
    )
  ]
)
