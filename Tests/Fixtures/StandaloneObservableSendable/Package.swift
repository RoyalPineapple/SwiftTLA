// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "StandaloneObservableSendable",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "SwiftTLA", path: "../../..")],
  targets: [
    .executableTarget(
      name: "StandaloneObservableSendable",
      dependencies: [
        .product(name: "SwiftTLA", package: "SwiftTLA"),
        .product(name: "SwiftTLAMacros", package: "SwiftTLA")
      ],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency"), .unsafeFlags(["-warnings-as-errors"])]
    )
  ]
)
