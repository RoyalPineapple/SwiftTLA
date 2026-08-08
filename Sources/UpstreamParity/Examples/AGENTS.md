# Porting Rules

How to port an upstream TLA+ spec into `Sources/UpstreamParity/Examples/`.

## Before you start

Read the upstream `.tla` file and its `.cfg` file. Understand:

- What the spec models.
- Each variable, its type, and its initial value.
- Each action and what it changes.
- Each invariant.

## File structure

One port lives in one file under `Sources/UpstreamParity/Examples/<Name>.swift`.

```swift
import SwiftTLA

// (One-line summary of the spec.)
// Upstream: specifications/<path>/<file>.tla
// Port: 1:1 translation. <Safety property>. <N> states.

extension Example {
    static let <name> = Example.Entry(
        id: "<Category>/<Spec>",
        upstreamSpec: "<category>",
        upstreamModule: "specifications/<path>/<file>.tla",
        upstreamCfg: "<path>.cfg",
        expectedDistinct: <N>,
        expectedResult: "success",
        spec: <name>Spec(),
        notes: "<note>"
    )
}
```

## Spec function

The spec function follows the upstream structure. Use the same variable names and the same order.

```swift
private func <name>Spec() -> TLASpec {
    // ---------- VARIABLES ----------
    // (description of each variable and its range)
    let <var> = Var<T>("<name>", value: <initial>)
    let <var> = Var<TLAFunctionType>("<name>")

    return TLASpec("<ModuleName>") {
        Extends("Naturals")

        // ---------- INITIAL PREDICATE ----------
        // (explanation of init)
        Variable(<var>, <initial>)
        Variable(<var>, in: <values>)

        // ---------- TYPE INVARIANT ----------
        // (what TypeOK checks)
        Invariant("TypeOK") { <condition> }

        // ---------- ACTIONS ----------
        // (what this action does)
        Action("<Name>") {
            <guard> && <var>.becomes(<expr>)
            && <other>.stays
        }
    }
}
```

## TLA+ to Swift map

| TLA+ | Swift |
|------|-------|
| `EXTENDS Naturals` | `Extends("Naturals")` |
| `VARIABLES x` | `let x = Var<Int>("x")` |
| `VARIABLES f` (function) | `let f = Var<TLAFunctionType>("f")` |
| `x = 0` | `Variable(x, 0)` |
| `x \in {0,1,2}` | `Variable(x, in: 0..<3)` |
| `x' = e` | `x.becomes(e)` |
| `UNCHANGED x` | `x.stays` |
| `x' \in S` | `choose(x, from: S)` |
| `f[k]` | `f.applying(k)` |
| `[f EXCEPT ![k] = v]` | `f.updated(at: k, to: v)` |
| `IF c THEN t ELSE e` | `StateExpr.if(c, then: t, else: e)` |
| `\A v \in S : P` | `StateExpr.forAll(v, in: S, P)` |
| `\E v \in S : P` | `StateExpr.exists(v, in: S, P)` |
| `CHOOSE v \in S : P` | `StateExpr.choose(v, from: S, matching: P)` |

## Names

- Variable names must match the upstream exactly: `big`, `small`, `rmState`.
- File names use PascalCase: `DieHard.swift`, `TwoPhase.swift`.
- ID strings use `Category/SpecName`: `"DieHard/TypeOK"`.
- Action names must match the upstream: `"FillSmallJug"`, `"TMCommit"`.

## Invariants

- Include TypeOK when the upstream has it.
- Check safety invariants only. Skip liveness PROPERTIES.
- Do not include invariants that must fail (for example, NotSolved in DieHard).

## Validation

After you write the port:

1. `swift build` — must compile.
2. `swift test --filter UpstreamParity` — the ModelChecker count must match `expectedDistinct`.
3. `make parity` — the TLC count must match.
4. Add the entry to `Example.all` at the top of `Example.swift`.

## Key porting patterns

### Action structure

Match the upstream action structure exactly. If the upstream has named per-instance
actions (for example, `Loop(p)`, `Think(p)`, `Eat(p)` with `Next == \E self : ...`), create
named actions in a `for` loop — do not inline everything into one `existsAction`.

```swift
Action("Loop_\(p)") {
    pc.value == loop
    && (passLeft || passRight || keepForks)
    && (goEat || stayLoop || goThink)
}
```

### UNCHANGED

Do not add manual UNCHANGED inside action branches. Let `completeAction` handle
missing variable assignments. Only assign the variables that change in each branch.
If a branch does not change a variable, do not mention it — `completeAction` adds
the necessary UNCHANGED per disjunct.

### ExistsAction vs named actions

Use `existsAction` only for simple nondeterministic choices (for example,
`\E p \in Prisoner` in a single-action spec). If the upstream uses `\E` with named
sub-actions, prefer per-instance named actions.

### Records in functions

Access record fields with `StateExpr.recordAccess(func.applying(key), "field")`.

```swift
let hld = StateExpr.recordAccess(forks.value.applying(p), "holder")
let lc = StateExpr.recordAccess(forks.value.applying(p), "clean")
```

### Constants and TLC parity

Wrap constant values in `Constant()` to emit `CONSTANTS` / `ASSUME` in the TLA+ output.
The parity script automatically copies `ASSUME` lines as `CONSTANT` assignments in the `.cfg`.

### Invariant names

The parity script detects these invariants: `TypeOK`, `TypeInvariant`, `VictoryOK`,
`ExclusiveAccess`, `SumMet`, `HCini`. Use one of these names when possible.
Add new invariant names to the script if needed.

### InvariantBuilder

Supports `for` loops (via `buildArray`) and `let` bindings.
Use loops freely instead of unrolling.

```swift
Invariant("TypeOK") {
    for i in 1...NP { typeOkLine(i) }
}
```
