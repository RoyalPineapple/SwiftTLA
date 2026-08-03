# SwiftTLA

Write TLA+ in Swift. The compiler proves your spec correct.

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

// Expands to a verified struct. 12 reachable states.
// Change the spec, the behavior changes. The compiler won't let invariants break.
```

---

## The pipeline

**Write.** A `TLASpec` is a Swift value.
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

**Check.** BFS model checker — same algorithm as TLC.
```swift
let result = try ModelChecker(spec: spec, maxStates: 20).check()
// .ok(statesCount: 12)
```

**Export.** `.description` is valid TLA+. Feed it to TLC for independent verification.
```tla
---- MODULE HourClock ----
VARIABLES hr
Init == hr = 1
Tick == ((((hr >= 1) /\ (hr <= 11)) /\ hr' = (hr + 1)) \/ ((hr = 12) /\ hr' = 1))
Next == Tick
Spec == Init /\ [][Next]_vars
====
```

**Ship.** `#TLA { ... }` macro runs the checker at compile time. If invariants hold, generates a runnable struct. If they break, you get a compiler error with the counterexample trace.
```swift
#TLA {
    Variable(hr, 1)
    Act("Tick") { (hr <= 11 && next(hr) == hr + 1) || (hr == 12 && next(hr) == 1) }
}
var clock = TLA(hr: 1)
clock.apply(.tick)  // hr → 2
clock.apply(.tick)  // hr → 3
// Verified: ticks forever with exactly 12 states
```

---

## How it works

2,000 lines of Swift. No parser, no lexer, no VM. Swift compiles the DSL, checks the types, runs the checker.

| TLA+ | SwiftTLA |
|---|---|
| `x' = x + 1` | `next(x) == x + 1` |
| `\A x \in S : P(x)` | `forAll(S, predicate)` |
| `S \cup T` | `S ∪ T` |
| `[f EXCEPT ![x] = e]` | `except(f, at: x, value: e)` |
| `[]<>P` | `.alwaysEventually(p)` |
| TLC model checker | `ModelChecker.check()` |
| `.tla` file | `.description` |
| PlusCal compiler | Swift's compiler |
| 50,000 lines of Java | 2,000 lines of Swift |

---

## Typed variables

`Var<T>` carries the type in the type system. Mixing types is a compile error.

```swift
let x = Var<Int>("x")       // arithmetic: x + 1 ✓
let nodes = Var<TLASet>("n") // sets: n ∪ {3} ✓
x ∪ nodes                    // compile error: Int ∪ Set
```

---

## Examples

```swift
import SwiftTLAExamples

// HourClock — 12 reachable states
let clock = try ModelChecker(spec: HourClockSpec.spec).exploreGraph()
// clock.states.count == 12

// DieHard — 16 reachable states, finds jug5=4
// CoffeeCan — parity game
// TeachingConcurrency — functions, EXCEPT, quantifiers
// MovingCat — non-deterministic init
// Major — Boyer-Moore majority vote
```

---

## Getting started

```swift
.package(url: "https://github.com/RoyalPineapple/SwiftTLA", branch: "main")
```

Two imports:
- `import SwiftTLA` — DSL, checker, liveness (zero dependencies)
- `import SwiftTLAMacros` — `#TLA` compile-time macro

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

## Run the demo

```bash
swift run demo
```
