# TLA+ for Swift Engineers

A mapping of TLA+ concepts to Swift that will make you dangerous in formal methods by dinner.

## The Big Idea

TLA+ describes **what** a system does, not **how**. You write math, the model checker proves it correct. In Swift, we do the same — but with enums, protocols, and result builders instead of LaTeX.

## Safety vs Liveness

```swift
// Safety: "nothing bad ever happens" — checked at every state
Inv("NoOverdraft") { balance >= 0 }

// Liveness: "something good eventually happens" — checked over infinite traces
Temporal("RequestGetsResponse") { .leadsTo(requestMade, responseSent) }
```

Safety is `assert()` at every line. Liveness is "will this loop eventually exit?"

## Variables and State

| TLA+ | SwiftTLA | Means |
|---|---|---|
| `VARIABLES x` | `Variable(x, 0)` | x starts at 0 |
| `x = 5` | `x >= 0` in `Inv{}` | Predicate on current state |
| `x' = x + 1` | `next(x) == x + 1` | x in next state equals x+1 |

## Actions = State Transitions

```swift
// TLA+: Fill3 == jug3' = 3 /\ UNCHANGED jug5
Act("Fill3") { next(jug3) == 3 }
// jug5 unchanged because we didn't mention it (stuttering)

// TLA+: Pour3to5 == IF jug3 + jug5 <= 5 THEN ...
Act("Pour3to5") {
    ((jug3 + jug5 <= 5) && (next(jug5) == jug3 + jug5) && (next(jug3) == 0))
    || (!(jug3 + jug5 <= 5) && (next(jug5) == 5) && (next(jug3) == jug3 - (5 - jug5)))
}
```

## Sets — TLA+'s Superpower

```swift
x ∈ nodes               // membership
a ⊆ b                   // subset
a ∪ b, a ∩ b            // union, intersection
setDifference(a, b)     // set minus
cardinality(s)          // size
powerSet(s)             // all subsets
unionAll(s)             // flatten set of sets
{x ∈ s : predicate}     // set filter
{expr : x ∈ s}          // set map
```

## Tuples & Records & Functions

```swift
tupleExpr([1, 2, 3])           // <<1, 2, 3>>
t[1]                           // element at index 1
tupleLength(t)                 // Len(t)
tupleAppend(t, x)              // Append(t, x)
tupleConcatenate(a, b)         // a \o b

recordExpr(["name": x, "age": y])  // [name |-> x, age |-> y]
r.field                      // record access
domain(f)                    // keys of record/function

[x ∈ domain ↦ expr]          // function literal
f[x]                         // function application
```

## Invariants vs Temporal Properties

```swift
// Safety — must hold in every reachable state
Inv("TypeOK") { hr >= 1 && hr <= 12 }

// Liveness — must hold for every possible execution
Temporal("Eventually12") { .eventually(hr == 12) }
Temporal("LeadsToMidnight") { .leadsTo(hr == 11, hr == 12) }
```

## Running It

```swift
let spec = TLASpec("HourClock") {
    Variable(hr, 1)
    Act("Tick") { (hr < 12 && next(hr) == hr + 1) || (hr == 12 && next(hr) == 1) }
    Inv("ValidHour") { hr >= 1 && hr <= 12 }
}

let checker = ModelChecker(spec: spec)
let result = try checker.check()

// Or generate the state machine:
let graph = try checker.exploreGraph()
let code = StateMachineGenerator(graph: graph).generate()
// code is a valid Swift struct you can check in

// Or emit TLA+ to validate with TLC:
print(spec)  // description IS valid TLA+
```

## The Type System Has Your Back

```swift
let x = Var<Int>("x")        // x is an Int variable
let nodes = Var<TLASet>("nodes")  // nodes is a Set variable

x + 1        // compiles — Int arithmetic
x ∈ nodes    // compiles — membership check
x ∪ nodes    // compile error — Int ∪ Set is nonsense

// Invariants can't use next():
Inv("Bad") { next(x) >= 0 }  // compile error — PrimedVar not StateExpr
```

## Generated Backbone

After verifying your spec, generate code:

```
swift run swift-tla generate hourclock
```

Produces a `struct HourClock` with a `transitions` switch table, `Action` enum, and `apply()` method. The spec IS the design document AND the skeleton. Change the spec, regenerate, the compiler tells you what broke.

## Where Swift Falls Short of Full TLA+

We're missing (today): `CHOOSE`, quantifiers (`\A`, `\E`), liveness checking, symmetry reduction, and a `.tla` parser. The surface — sets, tuples, records, functions, safety checking — is complete.
