# SwiftTLA

Write specs in Swift. The compiler checks them. Every time.

```swift
import SwiftTLA
import SwiftTLAMacros

let hr = Var<Int>("hr")             // typed variable

#TLASpec {                          // checked at compile time
    Variable(hr, 1)                 // starts at 1
    Act("Tick") {                   // action: what can happen next
        (hr <= 11 && hr.next == hr + 1) || (hr == 12 && hr.next == 1)
    }
}
// → struct TLA with Action enum, transitions, and apply()
```

---

## Always checked

Every `#TLASpec` block runs the model checker at compile time. Invariants hold → struct is generated. Invariants break → compiler error with counterexample trace.

```swift
let x = Var<Int>("x")

#TLASpec {
    Variable(x, 0)
    Act("Inc") { x.next == x + 1 }
    Act("Dec") { x.next == x - 1 }
    Inv("NonNeg") { x >= 0 }
}
// Compiler error: Invariant 'NonNeg' violated
//   init {x=0} → Dec {x=-1}
```

---

## What you can write

```swift
Variable(x, 0)                      // variable with initial value
Act("Name") { x.next == expr }      // what can happen next
Inv("Name") { predicate }           // must hold in every state
Temporal("Name", .leadsTo(p, q))    // whenever p, eventually q
Temporal("Name", .alwaysEventually(p)) // p holds infinitely often
Fairness(.weakFairness("Act"))      // Act eventually fires if enabled
Constant("N", 5)                    // parameterized specs
DeadlockCheck()                     // detect deadlocked states
```

**Expressions:**
```swift
x.next == x + 1                     // x in next state
x + y, x - y, x * y, x / y          // arithmetic
x < y, x <= y, x >= y, x == y       // comparisons
x.isIn(S)                           // x ∈ S
S.union(T)                          // S ∪ T
S.intersection(T)                   // S ∩ T
S.isSubset(of: T)                   // S ⊆ T
f.applying(a)                       // f[a]
f.updated(at: a, to: e)             // [f EXCEPT ![a] = e]
forAll(S, predicate)                // ∀ x ∈ S : P
exists(S, predicate)                // ∃ x ∈ S : P
```

**Types prevent mistakes:**
```swift
let x = Var<Int>("x")               // x + 1 ✓
let nodes = Var<TLASet>("n")        // nodes.union({3}) ✓
x.union(nodes)                      // compile error
```

---

## Run it

```
swift run demo
```

## Use it

```swift
.package(url: "https://github.com/RoyalPineapple/SwiftTLA", branch: "main")
```
`import SwiftTLA` for the DSL. `import SwiftTLAMacros` for `#TLASpec`.
