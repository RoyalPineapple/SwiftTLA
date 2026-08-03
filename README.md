# SwiftTLA

Write specs in Swift. The compiler checks them. Every time.

```swift
import SwiftTLA
import SwiftTLAMacros

let hr = Var<Int>("hr")

#TLASpec {
    Variable(hr, 1)
    Act("Tick") {
        (hr <= 11 && next(hr) == hr + 1) || (hr == 12 && next(hr) == 1)
    }
}

// Expands to a verified struct with Action enum, transitions, and apply()
```

---

## Always checked

Every `#TLASpec` block runs the model checker at compile time. If invariants hold, the struct is generated. If they break, you get a compiler error with the counterexample trace.

```swift
let x = Var<Int>("x")

#TLASpec {
    Variable(x, 0)
    Act("Inc") { next(x) == x + 1 }
    Act("Dec") { next(x) == x - 1 }
    Inv("NonNeg") { x >= 0 }
}
// Compiler error: Invariant 'NonNeg' violated
// Counterexample: init {x=0} → Dec {x=-1}
```

---

## What you can write

```swift
Variable(x, 0)                     // variable with initial value
Act("Name") { next(x) == expr }    // action — what can happen next
Inv("Name") { predicate }          // must hold in every state
Temporal("Name", .leadsTo(p, q))   // whenever p, eventually q
Temporal("Name", .alwaysEventually(p)) // p holds infinitely often
Fairness(.weakFairness("Act"))     // Act must eventually fire
Constant("N", 5)                   // parameterized specs
DeadlockCheck()                    // detect deadlocked states
```

Types prevent mistakes.
```swift
let x = Var<Int>("x")          // x + 1 ✓
let nodes = Var<TLASet>("n")   // nodes ∪ {3} ✓
x ∪ nodes                      // compile error
```

---

## Generated code

`#TLASpec` produces working Swift. `apply()`, `transitions`, `availableActions`. Change the spec, the behavior changes.

```
swift run demo
```

```swift
.package(url: "https://github.com/RoyalPineapple/SwiftTLA", branch: "main")
```
`import SwiftTLA` for the DSL. `import SwiftTLAMacros` for `#TLASpec`.
