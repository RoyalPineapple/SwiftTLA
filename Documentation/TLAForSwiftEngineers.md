# TLA+ for Swift engineers

SwiftTLA lets you write finite TLA+-style specs in Swift, explore them with
a BFS model checker, export `.tla` for TLC, and (optionally) generate a
concrete `StateMachine` via `@TLAModel`.

**Supported language surface:** [Fragment.md](Fragment.md)

## Minimal example

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

// Generated:
let m = HourClock.StateMachine.initial
m.availableTransitions  // [.tick]
```

## Check without the macro

```swift
let result = try ModelChecker(spec: HourClock.spec).check()
print(HourClock.spec.tlaModule)  // feed to TLC
```

## Bootstrap composition

```swift
import SwiftTLAModels

try ModelChecker.checkComposed(user: someUserSpec)
// checker lifecycle ⋊ user — self-proof, not the production BFS driver
```

## TLC oracle

```bash
./scripts/setup-tlc.sh
./scripts/validate_tlc.sh
```
