// swift-tools-version: 5.9

import PackageDescription

let generatedMachineDependencies: [Target.Dependency] = [
  .product(name: "SwiftTLA", package: "SwiftTLA"),
  .product(name: "SwiftTLAMacros", package: "SwiftTLA")
]

let package = Package(
  name: "ExternalConsumerContracts",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "SwiftTLA", path: "../../..")],
  targets: [
    .executableTarget(
      name: "GeneratedTypedSurface",
      dependencies: generatedMachineDependencies,
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency"), .unsafeFlags(["-warnings-as-errors"])]
    ),
    .executableTarget(
      name: "InvalidActionParameterAPI",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidCollectionPredicateMacro",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidDynamicModelName",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidModelClassHost",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidModelActorHost",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidModelStoredState",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidObservedModelState",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidTypedDSL",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidTypedDSLUnknownField",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "InvalidTypedFacade",
      dependencies: [.product(name: "SwiftTLA", package: "SwiftTLA")]
    ),
    .executableTarget(
      name: "ReadmeSymmetricCollectionMacro",
      dependencies: generatedMachineDependencies
    ),
    .executableTarget(
      name: "SpecExpressionMacro",
      dependencies: generatedMachineDependencies
    )
  ]
)
