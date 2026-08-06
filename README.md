# SwiftTLA

Finite-state TLA+ model checking from a Swift DSL, with TLC as the oracle.

See [Documentation/Fragment.md](Documentation/Fragment.md) for the supported language fragment (B v1).

## Pipeline

```
Swift DSL  ──► TLASpec ──► ModelChecker (plain BFS) ──► StateGraph
                  │                │
                  │         .tlaModule → TLC oracle
                  │
             @TLAModel ──► check + StateMachine codegen
                  │
         SwiftTLAModels (BFSChecker ⋊ user) ── bootstrap composition
```

## Bootstrap

The checker lifecycle is a TLA model itself:

```swift
import SwiftTLA
import SwiftTLAModels

// Lifecycle spec (dynamic bound)
let checker = TLASpec.bfsChecker(maxStates: 5)

// Compose with a user spec and model-check the product
let result = try ModelChecker.checkComposed(user: hourClockSpec)

// @TLAModel BFSChecker — compile-time checked + generated StateMachine
let machine = BFSChecker.StateMachine.initial
```

Production exploration is plain BFS. Composition is for self-proof, not a fake controller inside the loop.

## Usage

```swift
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock {
    public static var spec: TLASpec {
        TLASpec("HourClock") {
            let hr = Var<Int>("hr", value: 1)
            Variable(hr, 1)
            Action("Tick") {
                (hr != 12) && hr.becomes(hr + 1) ||
                (hr == 12) && hr.becomes(1)
            }
            Invariant("Valid") { hr >= 1 && hr <= 12 }
        }
    }
}

let machine = HourClock.StateMachine.initial
machine.availableTransitions
```

## Examples

Core ports under `Examples/` (HourClock, DieHard, CoffeeCan, MovingCat, Majority, Allocator, …).  
Weak name-only stubs are not kept. State counts for core specs are regression-tested.

## Oracle (tlaplus/Examples)

Upstream CI-validated specs are ground truth. See [Documentation/UpstreamParity.md](Documentation/UpstreamParity.md).

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
