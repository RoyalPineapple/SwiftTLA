# Public API validation

The required `swift-tests` GitHub Actions job validates SwiftTLA's compiler,
runtime, generated machine, and external Swift package contracts. It runs both
repository test targets.

The suite also builds real consumer packages:

- `GeneratedMachineDocumentation` compiles and runs the documented generated
  machine and actor behavior.
- `GeneratedTypedSurface` compiles and runs typed state and action calls.
- `InvalidGeneratedRawSurface` must fail because application code cannot access
  raw formal state or transition evidence.
- `InvalidGeneratedActorRawSurface` must fail for the same private boundary on
  the generated actor.

The invalid-package tests require the compiler diagnostics that identify the
unavailable API. A successful job therefore proves both sides of the public
boundary: supported typed calls compile, and private compiler machinery does
not.

GitHub Actions records the job status and logs.

For a focused local diagnostic, use the repository validation wrapper:

```sh
./scripts/local-validation.sh swiftpm-test "GeneratedStateMachineTests"
./scripts/local-validation.sh swiftpm-test "GeneratedActorExecutionContractTests"
./scripts/local-validation.sh swiftpm-test "GeneratedMachineDocumentationTests"
./scripts/local-validation.sh swiftpm-test "NestedComposableMacroConformanceTests"
```
