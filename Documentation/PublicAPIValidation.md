# Public API validation

The required `swift-tests` GitHub Actions job validates SwiftTLA's compiler,
runtime, generated machine, and external Swift package contracts. It runs both
repository test targets.

The suite builds two real consumer packages. `GeneratedMachineDocumentation`
compiles and runs the documented generated machine and actor behavior.
`ExternalConsumerContracts` contains independently selected products for the
remaining public-boundary checks:

- `GeneratedTypedSurface` compiles and runs typed state and action calls.
- `InvalidGeneratedRawSurface` must fail because application code cannot access
  raw formal state or transition evidence.
- `InvalidGeneratedActorRawSurface` must fail for the same private boundary on
  the generated actor.

The invalid-package tests require compiler diagnostics for raw-member access.
A successful job proves that supported typed calls compile and that generated
machines and actors do not expose raw formal state or transition evidence.

Attached macro expansions type-check in the consuming module. The underscored
`_GeneratedMachineStorage`, `_TLAFiniteEnum`, and `_TLAValueEnum` declarations
are public expansion support for that boundary. Generated application code uses
them privately; application code uses the generated machine and actor.

GitHub Actions records the job status and logs.

For a focused local diagnostic, use the repository validation wrapper:

```sh
./scripts/local-validation.sh swiftpm-test "GeneratedStateMachineTests"
./scripts/local-validation.sh swiftpm-test "GeneratedActorExecutionContractTests"
./scripts/local-validation.sh swiftpm-test "GeneratedMachineDocumentationTests"
./scripts/local-validation.sh swiftpm-test "NestedComposableMacroConformanceTests"
```
