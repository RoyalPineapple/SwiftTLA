# SwiftTLA

SwiftTLA is a compile-time spec validator and behavioral compiler. Swift types constrain which models you can construct. The `@TLAModel`, `@TLAActor`, and `@TLAObservable` macros parse the model. They model-check supported finite safety behavior during compilation. A successful check generates an executable state machine or an actor API.

It also exports TLA+ and a TLC configuration. For declared finite cases, TLC is a
pinned executable reference. Published TLA+ semantics remain authoritative.

See [the supported language fragment](Documentation/Design.md), the [generated-machine guide](Documentation/GeneratedMachines.md), the [live-machine guide](Documentation/LiveMachines.md), and the [symmetric collections guide](Documentation/SymmetricCollections.md). The generated-machine API reference is in [SwiftTLA DocC](Sources/SwiftTLA/SwiftTLA.docc/SwiftTLA.md).

## Live machines

For shared, running machine state, create one `TLALiveMachineOwner` and pass
its `TLALiveMachine` handle to generated `Live`, actor, observable, and
generic inspector surfaces. The live runtime is the sole mutable source for
that identity. Direct generated-model values are non-live value semantics; do
not use `apply(_:)` or a value copy as a handle for a running runtime. See
[Live Machines](Documentation/LiveMachines.md).

## Demonstrations app

The macOS demonstration app is a separate Swift package in
[`Examples/SwiftTLADemoApp`](Examples/SwiftTLADemoApp). It consumes the root
package's public `SwiftTLA` and `SwiftTLADemos` products. The formal models
live in [`Examples/SwiftTLADemos`](Examples/SwiftTLADemos), so the app imports
the same generated machines that the package verifies.

Run it from the repository root:

```bash
cd Examples/SwiftTLADemoApp
swift run SwiftTLADemoApp
```

It includes the Two Buckets puzzle, the Duck, Duck, Leader Chang–Roberts
election, and the Elevator Bank model.

## Compiler pipeline

```text
typed Swift authoring ──► source model ──► compile() ──► CompiledSpecification
                                                           ├──► typed generated machine
                                                           ├──► local exploration
                                                           └──► rendered TLA+ and PlusCal bundles
```

The release-facing macro examples use the same model-checking pipeline before they generate code. `@TLAModel` produces an executable model type. `@TLAActor` produces an actor or a nested actor adapter. `@TLAObservable` produces an observable model or a nested main-actor adapter with typed callbacks. The runtime behavior, the compile-time check, and the TLA+ export all come from one DSL model. The current public-workflow evidence covers only the bounded fixtures and package matrix described in [public workflow conformance](Documentation/PublicWorkflowConformance.md); it is not a claim about every accepted macro input.

## Usage

### @TLAModel — executable struct

```swift
import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock {
    enum Process: String, FiniteDomainKey {
        case clock

        static let formalDomain: [Process] = [.clock]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "readme.hour-clock.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel {
        case tick
    }

    public static var spec: TLASpec {
        #spec("HourClock") {
            Algorithm("HourClock") {
                let hour = SharedVar(initial: 1)
                Each(Process.all) { _ in
                    Do(Step.tick) {
                        Either {
                            When(hour < 12)
                            Assign(hour, to: hour + 1)
                        } or: {
                            When(hour == 12)
                            Assign(hour, to: 1)
                        }
                    }
                }
            }
        }
    }
}

var clock = try HourClock.makeMachine()
let result = try clock.apply(.tick)
print(result.after.hour)
```

## Symmetric collections

Symmetric-collection verification is a formal-engine/parity facility for the
declared finite fixtures. Application models use `#spec`, `Algorithm`,
`SharedVar`, and typed `Function`, `SetExpr`, and `Record` values. See the
[language fragment](Documentation/Design.md) for the supported boundary.

## Examples and TLC checks

Core ports live under `Sources/UpstreamParity/Examples/` (HourClock, DieHard, CoffeeCan, MovingCat, Majority, Allocator, and more). State counts for core specifications are regression-tested.

For selected finite core models, the repository can compare the complete labeled
transition relation with a pinned TLC run. The support gate admits only the
behavior and bounds named in its register. See [core graph
conformance](Documentation/CoreGraphConformance.md) and [core
support](Documentation/CoreSupport.md).

GitHub Actions runs the core-support gate. Exit `0` means all requested
support entries were admitted from one current run. Exit `1` means the
evidence was complete but requested support was blocked. Exit `2` means setup,
execution, governance, or evidence validation failed. The gate retains its
current report at
`.build/core-support-gate/support-admission.json` and each run below
`.build/core-support-gate/runs/`.

Use `scripts/local-validation.sh` only for local, focused diagnosis. It does
not create admission evidence. GitHub Actions owns broad validation and
release qualification.

### Temporal and symmetry support

Temporal and symmetry support is report-derived. Do not advertise a requested
entry unless the current P3 admission report marks it `admitted`.

GitHub Actions creates
`.build/temporal-symmetry-support-gate/support-admission.json`. It exits `0`
only when every requested entry is admitted. Exit `1` means a complete
evaluation blocks a claim. Exit `2` means the evaluation is unavailable or
unsafe. Both nonzero results remain failures.

The declared entries are finite temporal cases and one binary-valued
`SymmetricCollection` at exact scopes 2, 3, and 4. The report does not claim
arbitrary temporal formulas, unbounded fairness or liveness, larger symmetry
scopes, combined temporal symmetry reduction, multiple collection declarations,
or nested member values. See [temporal and symmetry conformance](Documentation/TemporalSymmetryConformance.md).

### Public workflow validation

The hosted aggregate P4 diagnostic checks the declared parser-builder and
generated two-state counters, the
valid/invalid `@TLAModel`, `@TLAActor`, and `@TLAObservable` fixtures, and the
`SwiftTLA-Package` public-library build for the declared macOS destination.
It makes no cross-platform or demo-product claim. Exit `0` means those exact bounded checks matched;
exit `1` means a completed difference; exit `2` means unavailable or unsafe
evaluation. A local report is diagnostic only. The checked-in GitHub workflow
produces explicit hosted-candidate evidence and retains its logs and artifacts,
but does not turn the bounded result into general public support.

The current report is `.build/public-workflow-support-gate/support-admission.json`,
with immutable evidence under `.build/public-workflow-support-gate/runs/<run-id>/`.
`@TypedVar` and `@TLAValidated` were removed and have no public contract.
See [public workflow conformance](Documentation/PublicWorkflowConformance.md)
for fixture identities, report fields, workflow artifact locations, authority
labels, and limits.

State counts alone do not establish behavioral equivalence. A successful
bounded check does not prove arbitrary population sizes, liveness, or
unsupported TLA+ constructs. GitHub Actions runs exact finite graph comparison
with the pinned toolchain; see [core graph conformance](Documentation/CoreGraphConformance.md).

## Local validation

Use `scripts/local-validation.sh static` or a focused wrapper test during
normal development. GitHub Actions runs the broad PR and release qualification
workflows, including coverage and external conformance gates. Local broad
validation requires explicit authorization.

## Requirements

- macOS 14+
- Swift 5.9+
- Xcode 16+
