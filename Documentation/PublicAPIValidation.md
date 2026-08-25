# Public API validation

The `public-api` GitHub Actions job validates SwiftTLA as an external Swift
package. It runs the repository smoke suite, which exercises the generated
value machine, actor, and SwiftUI-facing API.

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
