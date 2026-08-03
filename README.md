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
// Expands to a verified struct with Action enum, transitions, and apply()
```

---

## Two ways to write specs

**Compile-time:** `#TLA { ... }` checks the spec during compilation. Pass → generates a runnable struct. Fail → compiler error with the counterexample.

**Runtime:** `TLASpec("Name") { ... }` returns a value you can inspect, check, compose, and share between tests and apps.

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

---

## What you get

**Export to TLA+.** `.description` is a valid `.tla` file. Run it through TLC to independently verify.

**Reuse.** Shared specs in `SwiftTLAExamples`. Tests and the demo import the same definition.

**Type safety.** `Var<Int>` and `Var<TLASet>` are distinct. The compiler won't let you mix them.

**Generates working code.** `#TLA` produces a struct with `apply()`. Change the spec, behavior changes.

---

## Reference

| TLA+ | SwiftTLA |
|---|---|
| `x' = x + 1` | `next(x) == x + 1` |
| `x \in S` | `x ∈ S` |
| `S \cup T` | `S ∪ T` |
| `\A x \in S : P` | `forAll(S, predicate)` |
| `[f EXCEPT ![x] = e]` | `except(f, at: x, value: e)` |
| `[]<>P` | `Temporal("name", .alwaysEventually(p))` |
| `WF(A)` | `Fairness(.weakFairness("A"))` |

---

```
swift run demo
```

```swift
.package(url: "https://github.com/RoyalPineapple/SwiftTLA", branch: "main")
```
