# SwiftTLA

SwiftTLA is a compile-time behavioral compiler. Swift types constrain which models you can construct. The macros `@TLAModel`, `@TLAActor`, `@TLAObservable`, and `@TLAValidated` parse the model. They then model-check its behavior during compilation. A successful check generates an executable state machine or an actor API.

The `@TLAValidated` macro generates no code. You can use it when you need proof only.

It also exports TLA+ and a TLC configuration so bounded models can be checked against TLC as an oracle.

See [Documentation/Fragment.md](Documentation/Fragment.md) for the supported language fragment and the [symmetric collections guide](Documentation/SymmetricCollections.md) for the identity and proof boundary.

## Compiler pipeline

```text
Typed Swift DSL ──► TLASpec ──► compile-time model checking ──► executable model
       │                │                    │                         │
       │                │                    ├── failure: compiler diagnostic
       │                │                    └── success: state machine or actor API
       │                └── .tlaModule + .tlaCfg ──► TLC oracle
       └── types constrain legal variables, values, and collection operations
```

Each macro model-checks the spec before it generates code. `@TLAModel` produces an executable model type. `@TLAActor` applies the same pipeline to an actor. `@TLAObservable` generates an `@Observable` class with callbacks. `@TLAValidated` verifies the spec at compile time. It generates no runtime code. The runtime behavior, the compile-time check, and the TLA+ export all come from one DSL model.

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

### @TLAValidated — proof

The `@TLAValidated` macro checks the spec at compile time. It does not generate code.

```swift
@TLAValidated
struct CounterProtocol {
    static var spec: TLASpec {
        TLASpec("CounterProtocol") {
            let counter = Var("counter", 0)
            Variable(counter)
            Action("increment") { counter.becomes(counter + 1) }
            Invariant("nonNegative") { counter >= 0 }
        }
    }
}
```

The spec is registered for composition with `UseSpec()`. The macro does not generate `_state`, `apply…()`, or `runtime` members.

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

Run the symmetric-collection TLC oracle after [setting up TLC](scripts/setup-tlc.sh):

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

## Examples and oracle checks

Core ports live under `Examples/` (HourClock, DieHard, CoffeeCan, MovingCat, Majority, Allocator, and more). State counts for core specifications are regression-tested.

Upstream CI-validated specifications are the TLC oracle; see [Documentation/UpstreamParity.md](Documentation/UpstreamParity.md).

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
