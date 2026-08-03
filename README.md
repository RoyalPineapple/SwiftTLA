# SwiftTLA

Model checkers in Swift. Write specs as code. Run them. The compiler catches mistakes.

```swift
import SwiftTLA
import SwiftTLAMacros

let hr = Var<Int>("hr")

#TLA {
    Variable(hr, 1)
    Act("Tick") {
        (hr <= 11 && next(hr) == hr + 1) || (hr == 12 && next(hr) == 1)
    }
}
// Generates a verified struct. 12 reachable states. Stays in sync with the spec.
```

---

## What you can do

**Define a spec.**
```swift
let spec = TLASpec("HourClock") {
    Variable(hr, 1)
    Act("Tick") {
        let increment: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
        let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
        increment || wrap
    }
}
```

**Check it.**
```swift
let result = try ModelChecker(spec: spec, maxStates: 20).check()
// .ok(statesCount: 12)
```

**Generate TLA+.** `.description` produces a `.tla` file you can verify with TLC.
```tla
---- MODULE HourClock ----
VARIABLES hr
Init == hr = 1
Tick == ((((hr >= 1) /\ (hr <= 11)) /\ hr' = (hr + 1)) \/ ((hr = 12) /\ hr' = 1))
Next == Tick
Spec == Init /\ [][Next]_vars
====
```

**Ship it.** `#TLA { ... }` checks your spec at compile time. If invariants hold, it generates a struct with `apply()`. If they break, you get a compiler error showing the trace.

**Find bugs.**
```swift
let spec = TLASpec("Counter") {
    Variable(Var<Int>("x"), 0)
    Act("Inc") { next(x) == x + 1 }
    Act("Dec") { next(x) == x - 1 }
    Inv("NonNeg") { x >= 0 }
}
let result = try ModelChecker(spec: spec).check()
// INVARIANT VIOLATED: NonNeg
// Counterexample trace:
//   0. [init] {x = 0}
//   1. [Dec]  {x = -1}
```

**Reuse specs.** Each example has a shared definition. Tests import it. The demo runs it. You can build on it.
```swift
import SwiftTLAExamples
let graph = try ModelChecker(spec: HourClockSpec.spec).exploreGraph()
// graph.states.count == 12
```

---

## Reference

| TLA+ operator | SwiftTLA |
|---|---|
| `x' = x + 1` | `next(x) == x + 1` |
| `x \in S` | `x ∈ S` |
| `S \cup T` | `S ∪ T` |
| `\A x \in S : P` | `forAll(S) { predicate }` |
| `EXCEPT` | `except(f, at: x, value: e)` |
| `[]<>P` | `Temporal("name", .alwaysEventually(p))` |
| `WF(A)` | `Fairness(.weakFairness("A"))` |

Types help. `Var<Int>` and `Var<TLASet>` are different — you can't union an integer into a set by accident.

---

## Run it

```
swift run demo
```

## Use it

```swift
.package(url: "https://github.com/RoyalPineapple/SwiftTLA", branch: "main")
```
`import SwiftTLA` for the DSL and checker. `import SwiftTLAMacros` for `#TLA`.
