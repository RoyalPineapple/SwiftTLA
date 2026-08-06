# Porting Rules

How to port an upstream TLA+ spec from `tlaplus/Examples` into `Sources/UpstreamParity/Examples/`.

## 1. Read the upstream first

Read the `.tla` file completely before writing any Swift. Understand:
- What the spec models
- Every variable, its type, and initial value
- Every action and its guard/update logic
- Every invariant
- The `.cfg` file: CONSTANTS, SPECIFICATION name, INVARIANTS

## 2. File structure

Each port lives in a single file under `Sources/UpstreamParity/Examples/<Name>.swift`.

```swift
import SwiftTLA

// <One-line description of the spec.>
// Upstream: specifications/<path>/<file>.tla
// Port: 1:1 faithful translation. <Safety property checked>. <N> states.

extension Example {
    static let <camelCaseName> = Example.Entry(
        id: "<Category>/<Name>",
        upstreamSpec: "<category>",
        upstreamModule: "specifications/<path>/<file>.tla",
        upstreamCfg: "<path>.cfg",     // or nil
        expectedDistinct: <TLC count>,
        expectedResult: "success",
        spec: <specFunctionName>(),
        notes: "<brief note>",
        matchesUpstreamTLC: true
    )
}
```

## 3. Spec function structure

The private spec function follows the upstream structure exactly:

```swift
private func <name>Spec() -> TLASpec {
    // ---------- VARIABLES ----------
    // Each with a comment describing its role and range.
    let <var> = Var<T>("<name>", value: <initial>)
    let <var> = Var<TLAFunctionType>("<name>")

    return TLASpec("<ModuleName>") {
        Extends("Naturals")  // or "Integers"

        // ---------- INITIAL PREDICATE ----------
        // Comment explaining init.
        Variable(<var>, <initial>)
        Variable(<var>, in: <values>)  // for nondeterministic init

        // ---------- TYPE INVARIANT ----------
        // Comment explaining what TypeOK checks.
        Invariant("TypeOK") { <condition> }

        // ---------- ACTIONS ----------
        // Each action gets a brief comment.

        // <Action description>
        Action("<Name>") {
            <guard> && <variable>.becomes(<expression>)
            && <other>.stays
        }

        // <Other invariants>
        Invariant("<Name>") { <condition> }
    }
}
```

## 4. DSL mappings

| TLA+ | Swift DSL |
|------|-----------|
| `EXTENDS Naturals` | `Extends("Naturals")` |
| `EXTENDS Integers, FiniteSets` | `Extends("Integers, FiniteSets")` |
| `CONSTANT N` | Not in spec; use the value directly |
| `VARIABLES x` | `let x = Var<Int>("x")` |
| `VARIABLES f` (function) | `let f = Var<TLAFunctionType>("f")` |
| `VARIABLES s` (set) | `let s = Var<TLASetType>("s")` |
| `x = 0` | `Variable(x, 0)` |
| `x \in {0,1,2}` | `Variable(x, in: 0..<3)` or `Variable(x, in: [0,1,2])` |
| `x \in [Node -> Bool]` | Enumeration or `Variable(computed: x, expr)` |
| `x' = e` | `x.becomes(e)` |
| `UNCHANGED x` | `x.stays` |
| `x' \in S` | `choose(x, from: S)` |
| `f[k]` | `f.applying(k)` |
| `[f EXCEPT ![k] = v]` | `f.updated(at: k, to: v)` |
| `\A p \in S : P` | `StateExpr.forAll(p, in: S, body)` |
| `\E p \in S : P` | `StateExpr.exists(p, in: S, body)` |
| `CHOOSE p \in S : P` | `StateExpr.choose(p, from: S, matching: predicate)` |
| `4..6` (range) | `4...6` (Swift range) or `StateExpr.set([4,5,6])` |
| `IF/THEN/ELSE` | `StateExpr.if(cond, then: x, else: y)` |

## 5. Naming

- Variable names match upstream exactly (case-sensitive): `big`, `small`, `rmState`
- File names use PascalCase: `DieHard.swift`, `TwoPhase.swift`
- ID strings use `Category/SpecName`: `"DieHard/TypeOK"`, `"transaction_commit/TwoPhase"`
- Action names match upstream: `"FillSmallJug"`, `"TMRcvPrepared"`

## 6. Invariants

- Always include TypeOK if upstream has it
- Safety invariants only — skip liveness PROPERTIES
- Don't include invariants that are SUPPOSED to fail (like NotSolved in DieHard)

## 7. Validation

After writing the port:
1. `swift build` — must compile
2. `swift test --filter UpstreamParity` — ModelChecker count must match expectedDistinct
3. `make parity` — TLC count must match
4. Update `Example.all` in `Example.swift`
5. Update `Documentation/UpstreamParity.md` table
