# SwiftTLA

Write specs in Swift. The compiler checks them. Output a `.tla` file that TLC can verify independently.

```swift
import SwiftTLA
import SwiftTLAMacros

let hr = Var<Int>("hr")

#TLASpec {
    Variable(hr, 1)
    Act("Tick") {
        (hr <= 11 && hr.next == hr + 1) || (hr == 12 && hr.next == 1)
    }
}
// → struct TLA with apply(), 12 states verified
```

---

## Externally auditable

Every spec produces a valid `.tla` file. TLC can verify it independently. Same results, different toolchain — that's the proof.

```swift
let spec = TLASpec("HourClock") {
    Variable(hr, 1)
    Act("Tick") { (hr <= 11 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
}
print(spec)
```

Output:
```tla
---- MODULE HourClock ----
VARIABLES hr
Init == hr = 1
Tick == ((((hr >= 1) /\ (hr <= 11)) /\ hr' = (hr + 1)) \/ ((hr = 12) /\ hr' = 1))
Next == Tick
Spec == Init /\ [][Next]_vars
====
```

---

## Always checked

`#TLASpec` runs the model checker at compile time. Invariant holds → struct generated. Invariant broken → compiler error.

```swift
let x = Var<Int>("x")
#TLASpec {
    Variable(x, 0)
    Act("Inc") { x.becomes(x + 1) }
    Act("Dec") { x.becomes(x - 1) }
    Invariant("NonNeg") { x >= 0 }
}
// Compiler error: Invariant 'NonNeg' violated
//   init {x=0} → Dec {x=-1}
```

---

## API

```swift
Variable(x, 0)                      // variable, starts at 0
Act("Name") { x.becomes(expr) }     // action — what happens next
Invariant("Name") { predicate }     // must hold in every state
LeadsTo("Name", p, q)               // whenever p, eventually q
AlwaysEventually("Name", p)         // p holds infinitely often
WeakFairness("Act")                 // Act eventually fires if enabled
Constant("N", 5)                    // parameterized specs
DeadlockCheck()                     // detect deadlocked states
```

**Expressions:**
```swift
x.becomes(x + 1)                    // x' = x + 1
x.isIn(S)                           // x ∈ S
S.union(T)                          // S ∪ T
f.applying(a)                       // f[a]
f.updated(at: a, to: e)             // [f EXCEPT ![a] = e]
all(in: S, predicate)               // ∀ x ∈ S : P
pickOne(from: S, matching: p)       // CHOOSE x ∈ S : P
```

---

```
swift run demo
```

```swift
.package(url: "https://github.com/RoyalPineapple/SwiftTLA", branch: "main")
```
`import SwiftTLA` for the DSL. `import SwiftTLAMacros` for `#TLASpec`.
