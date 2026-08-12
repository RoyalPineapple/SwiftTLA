# SwiftTLA

SwiftTLA is a compile-time spec validator and behavioral compiler. Swift types constrain which models you can construct. The `@TLAModel`, `@TLAActor`, and `@TLAObservable` macros parse the model. They model-check supported finite safety behavior during compilation. A successful check generates an executable state machine or an actor API.

It also exports TLA+ and a TLC configuration. For declared finite cases, TLC is a
pinned executable reference. Published TLA+ semantics remain authoritative.

See [the supported language fragment](Documentation/Design.md) and the [symmetric collections guide](Documentation/SymmetricCollections.md) for the identity and proof boundary.

## Compiler pipeline

```text
Typed Swift DSL ──► TLASpec ──► compile-time model checking ──► executable model
       │                │                    │                         │
       │                │                    ├── failure: compiler diagnostic
       │                │                    └── success: state machine or actor API
       │                └── .tlaModule + .tlaCfg ──► pinned TLC reference
       └── types constrain legal variables, values, and collection operations
```

The release-facing macro examples use the same model-checking pipeline before they generate code. `@TLAModel` produces an executable model type. `@TLAActor` applies the pipeline to an actor. `@TLAObservable` generates an `@Observable` class with callbacks. The runtime behavior, the compile-time check, and the TLA+ export all come from one DSL model. The current public-workflow evidence covers only the bounded fixtures and package matrix described in [public workflow conformance](Documentation/PublicWorkflowConformance.md); it is not a claim about every accepted macro input.

## Usage

### @TLAModel — executable struct

```swift
import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock {
    public static var spec: TLASpec {
        TLASpec("HourClock") {
            let hour = Var<Int>("hour", value: 1)
            Variable(hour, 1)
            Action("Tick") {
                (hour != 12 && hour.becomes(hour + 1)) ||
                (hour == 12 && hour.becomes(1))
            }
            Invariant("validHour") { hour >= 1 && hour <= 12 }
        }
    }
}

var clock = HourClock()
clock.applytick()
```

## Symmetric collections

Use a symmetric collection when individual members are exchangeable for the property being checked. Runtime devices keep their concrete `Identifiable.ID` values; the verifier uses separate opaque members derived only from `verificationScope`.

```swift
import Foundation
import SwiftTLA
import SwiftTLAMacros

struct Device: Identifiable {
    let id: UUID
}

@TLAModel
struct DeviceContract {
    static var spec: TLASpec {
        TLASpec("DeviceContract") {
            let phases = SymmetricCollectionVar<Device, Int>("phases")
            SymmetricCollection(phases, verificationScope: 4, initial: 0)

            CollectionAction("beginConnect", on: phases) { member in
                phases[member] == 0 && phases.update(member, to: 1)
            }

            Invariant("validPhase") {
                phases.allSatisfy { phase in phase >= 0 && phase <= 1 }
            }
        }
    }
}

let device = Device(id: UUID())
var contract = DeviceContract()
contract.phases.insert(device)
try contract.beginConnect(id: device.id)
```

The ID routes the generated runtime action but never becomes model data. This macro example verifies the collection declaration, ID-routed action, and a nontrivial collection-wide phase invariant. `allSatisfy` quantifies the opaque verification members, so a modeled transition that produces a phase outside `0...1` fails the compile-time check. The collection member token in `CollectionAction` is opaque: it may select or update its owning collection, but it cannot be compared, stored, or otherwise used to observe member identity. Use `contains(where:)` when the property is existential rather than universal; both predicates are checked over the same finite modeled domain.

### Verification boundary

`verificationScope: 4` checks exactly four exchangeable model members for that run. The live runtime collection can contain a different number of concrete devices. A successful finite run does **not** prove the model for larger populations, arbitrary population sizes, or membership churn not represented in the model. Parametric verification is future work; it is not supplied by symmetric-collection reduction.

Run the symmetric-collection check with the pinned TLC executable after [setting up TLC](scripts/setup-tlc.sh):

```bash
./scripts/setup-tlc.sh
swift run tlc-validate symmetric-collections
```

## Bootstrap

The checker lifecycle is also represented as a TLA model:

```swift
import SwiftTLA
import SwiftTLAModels

let checker = TLASpec.bfsChecker(maxStates: 5)
let result = try ModelChecker.checkComposed(user: hourClockSpec)
let machine = BFSChecker.StateMachine.initial
```

Production exploration is plain BFS. Composition is for self-proof, not a controller inside the exploration loop.

## Examples and TLC checks

Core ports live under `Examples/` (HourClock, DieHard, CoffeeCan, MovingCat, Majority, Allocator, and more). State counts for core specifications are regression-tested.

For selected finite core models, the repository can compare the complete labeled
transition relation with a pinned TLC run. The support gate admits only the
behavior and bounds named in its register. See [core graph
conformance](Documentation/CoreGraphConformance.md) and [core
support](Documentation/CoreSupport.md).

Run the core-support gate directly with:

```bash
make core-support-gate
```

Exit `0` means all requested support entries were admitted from one current
run. Exit `1` means the evidence was complete but requested support was
blocked. Exit `2` means setup, execution, governance, or evidence validation
failed. The command retains its current report at
`.build/core-support-gate/support-admission.json` and each run below
`.build/core-support-gate/runs/`.

Run the complete local verification gate with:

```bash
make ci-local
```

It runs tests, coverage, builds, and the locked finite TLC comparison plus the
core-support gate. It writes fresh evidence below `.build/`. SwiftLint remains
an advisory warning. These commands run locally; they do not require a hosted
or paid GitHub runner. This is a bounded claim for the declared cases only. It
does not prove arbitrary bounds, temporal properties, liveness, fairness, or
symmetry reduction.

### Temporal and symmetry support

Temporal and symmetry support is report-derived. Do not advertise a requested
entry unless the current P3 admission report marks it `admitted`.

Run the mandatory local P3 check with:

```bash
make temporal-symmetry-release-check
```

The command creates `.build/temporal-symmetry-support-gate/support-admission.json`.
It exits `0` only when every requested entry is admitted. Exit `1` means a
complete evaluation blocks a claim. Exit `2` means the evaluation is
unavailable or unsafe. Both nonzero results remain failures in local and
hosted workflows.

The declared entries are finite temporal cases and one binary-valued
`SymmetricCollection` at exact scopes 2, 3, and 4. The report does not claim
arbitrary temporal formulas, unbounded fairness or liveness, larger symmetry
scopes, combined temporal symmetry reduction, multiple or legacy collections,
or nested member values. See [temporal and symmetry conformance](Documentation/TemporalSymmetryConformance.md).

### Public workflow validation

Run the aggregate P4 diagnostic with:

```bash
make public-workflow-release-check
```

It checks the declared parser-builder and generated two-state counters, the
valid/invalid `@TLAModel`, `@TLAActor`, and `@TLAObservable` fixtures, and the
`SwiftTLA-Package` public-library build for the declared macOS destination.
It makes no cross-platform or demo-product claim. Exit `0` means those exact bounded checks matched;
exit `1` means a completed difference; exit `2` means unavailable or unsafe
evaluation. A local report is diagnostic only. The checked-in GitHub workflow
produces explicit hosted-candidate evidence and retains its logs and artifacts,
but does not turn the bounded result into general public support.

The current report is `.build/public-workflow-support-gate/support-admission.json`,
with immutable evidence under `.build/public-workflow-support-gate/runs/<run-id>/`.
`@TypedVar` is not release-facing or admitted, and `@TLAValidated` was removed.
See [public workflow conformance](Documentation/PublicWorkflowConformance.md)
for fixture identities, report fields, workflow artifact locations, authority
labels, and limits.

State counts alone do not establish behavioral equivalence. A successful bounded check does not prove arbitrary population sizes, liveness, or unsupported TLA+ constructs.

```bash
./scripts/setup-tlc.sh
./scripts/validate_tlc.sh              # operator matrix vs TLC
./scripts/validate_upstream_parity.sh  # Swift ports ↔ upstream TLC
swift test
make parity
```

## Requirements

- macOS 14+
- Swift 5.9+
- Xcode 16+
