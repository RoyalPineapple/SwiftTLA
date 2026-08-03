# SwiftTLA

Write TLA+ in Swift. The compiler is your model checker.

```swift
import SwiftTLA
import SwiftTLAMacros

let hr = Var<Int>("hr")

#VerifiedStateMachine {
    Variable(hr, 1)
    Act("Tick") {
        (hr <= 11 && next(hr) == hr + 1) || (hr == 12 && next(hr) == 1)
    }
}
```

That's a verified clock. 12 reachable states. Compiler won't let you create invalid ones.

---

## Show, don't tell

**The spec:**
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

**The check:**
```swift
let result = try ModelChecker(spec: spec, maxStates: 20).check()
// result == .ok(statesCount: 12)
```

**What it generates (`print(spec)` is valid TLA+ that TLC verifies):**
```tla
---- MODULE HourClock ----
EXTENDS Naturals, FiniteSets, Sequences
VARIABLES hr
Init == hr = 1
Tick == ((((hr >= 1) /\ (hr <= 11)) /\ hr' = (hr + 1)) \/ ((hr = 12) /\ hr' = 1))
Next == Tick
Spec == Init /\ [][Next]_vars
====
```

**The state machine (generated at compile time):**
```swift
#VerifiedStateMachine {
    Variable(hr, 1)
    Act("Tick") { (hr <= 11 && next(hr) == hr + 1) || (hr == 12 && next(hr) == 1) }
}

// Expands inline to:
var clock = VerifiedStateMachine(hr: 1)
clock.apply(.tick)  // hr → 2
clock.apply(.tick)  // hr → 3
// ... after 12 ticks:
clock.apply(.tick)  // hr → 1 — verified wrap
```

---

## How it works

**2,000 lines of Swift** replacing 50,000 lines of Java. No parser, no lexer, no VM. Swift's compiler handles parsing, types, and memory. Swift's type system handles correctness.

| TLA+ | SwiftTLA |
|---|---|
| `x' = x + 1` | `next(x) == x + 1` — compiled by Swift, verified by checker |
| `\A x \in S : P(x)` | `forAll(S, predicate)` — every operator as a function |
| `S \cup T` | `S ∪ T` — set algebra with native operators |
| `[f EXCEPT ![x] = e]` | `except(f, at: x, value: e)` — pointwise function update |
| `[]<>P` | `.alwaysEventually(p)` — liveness via Tarjan SCC |
| TLC model checker | `ModelChecker.check()` — same algorithm, same results |
| `.tla` file | `.description` — valid TLA+ that TLC can verify independently |

**Var<T> types prevent mistakes:**
```swift
let x = Var<Int>("x")       // arithmetic: x + 1 ✓
let nodes = Var<TLASet>("n") // sets: n ∪ {3} ✓
x ∪ nodes                    // compile error: Int ∪ Set
```

---

## The complete picture

1. Write your spec in Swift — it's a `TLASpec` value
2. `.description` produces a `.tla` file — feed it to TLC to prove equivalence
3. `#VerifiedStateMachine` macro expands at compile time — generates a runnable struct
4. If invariants fail, the macro produces a compiler error with the counterexample trace
5. The generated struct IS the implementation — change the spec, behavior changes

---

## Getting started

```swift
.package(url: "https://github.com/RoyalPineapple/SwiftTLA", branch: "main")
```

Two imports:
- `import SwiftTLA` — DSL, checker, liveness (zero dependencies)
- `import SwiftTLAMacros` — `#VerifiedStateMachine` macro

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
