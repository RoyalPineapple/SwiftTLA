# SwiftTLA language fragment (B v1)

SwiftTLA aims at **TLA+-compatible finite-state safety checking** for a
defined fragment, with TLC as the external oracle.

## DSL philosophy

- **Builders everywhere.** Every nested scope has a result builder: `Action { }`,
  `Invariant { }`, `Variable(computed:) { }`, `DefineRecursive { }`,
  `forAll(set) { _ in }`, `filterSet(set) { _ in }`, `exists(name, from:) { _ in }`.
- **1:1 structural match.** DSL structure mirrors upstream TLA+ exactly.
  Same action names, same variable decomposition, same invariant names.
- **No manual `ActionDecl`/`InvDecl`.** All Decl structs have internal inits.
  Only builder functions create spec components.

## Language coverage

| Feature | Status | Notes |
|---------|--------|-------|
| **Variables** | ✓ | Int, Bool, String, Set, Tuple, Function, Record |
| **Init — concrete** | ✓ | `Variable(x, 0)` |
| **Init — nondet** | ✓ | `Variable(x, in: range)` cartesian product |
| **Init — computed** | ✓ | `Variable(computed: x) { expr }` evaluates after nondet expansion |
| **Init — correlated** | ~ | `ComputedVariable` (closure-based) — works but not via builder |
| **Actions — assignment** | ✓ | `x.becomes(expr)` |
| **Actions — unchanged** | ✓ | `x.stays`; `completeAction` auto-adds per-branch |
| **Actions — guard** | ✓ | `guard_expr && action` in builder |
| **Actions — and/or** | ✓ | `&&` / `||` in `Action { }` builder |
| **Actions — IF/THEN/ELSE** | ✓ | `ActionExpr.ifElse(cond, then:, else:)` |
| **Actions — `\E x \in S`** | ✓ | `existsAction` + `ActionExpr.exists(name, from:) { _ in }` |
| **Actions — `\E` SUBSET** | — | Need subset enumeration in enumerator |
| **CHOOSE** | ✓ | Cartesian product for multi-choose |
| **`\A` over sets** | ✓ | `forAll(set) { _ in }` builder; `StateExpr.forAll(set, body)` |
| **`\E` over sets** | ✓ | `existsIn(set) { _ in }` builder |
| **`{x \in S : P}` — set filter** | ✓ | `filterSet(set) { _ in }` builder |
| **Functions — apply** | ✓ | `f.applying(key)` |
| **Functions — EXCEPT** | ✓ | `f.updated(at: key, to: val)`; nested; `@` self-ref |
| **Functions — domain** | ✓ | `.domain` |
| **Functions — literal** | ✓ | `functionLiteral(var, in: domain, body)`; `TLAValue.function(dict)` |
| **Records — access** | ✓ | `StateExpr.recordAccess(expr, "field")` |
| **Records — literal** | ✓ | `StateExpr.recordLiteral(["field": expr])` |
| **Sequences — Head/Tail** | ✓ | `.head`, `.tail` |
| **Sequences — Append** | ✓ | `.appending(e)` |
| **Sequences — Len** | ✓ | `.count` |
| **Sequences — element** | ✓ | `.at(i)` |
| **Sequences — concatenate** | ✓ | `.concatenating(other)` |
| **Sets — union/intersection/diff** | ✓ | `.union`, `.intersection`, `.subtracting` |
| **Sets — subset** | ✓ | `.isSubset(of:)` |
| **Sets — cardinality** | ✓ | `.cardinality` |
| **Sets — powerset** | ✓ | `.powerSet` |
| **Sets — filter** | ✓ | See set filter above |
| **Arithmetic** | ✓ | +, −, *, /, %, >=, <=, >, <, =, != |
| **SAFETY — invariants** | ✓ | `Invariant("name") { expr }`; `InvariantBuilder` with `for` loop support |
| **SAFETY — deadlock** | ✓ | `DeadlockCheck()` |
| **Constraint** | ✓ | `Constraint(expr)` filters BFS successors; renders `StateConstraint` in `.tlaModule` |
| **CONSTANTS / ASSUME** | ✓ | `Constant(name, value)` emits `CONSTANTS`+`ASSUME`; parity script copies to `.cfg` |
| **Definitions** | ✓ | `Definition(tlaText)` raw TLA+ passthrough |
| **Theorems** | ✓ | `Theorem(tlaText)` raw TLA+ passthrough |
| **RECURSIVE — raw** | ✓ | `Recursive(tlaText)` raw TLA+ passthrough |
| **RECURSIVE — structured** | ✓ | `DefineRecursive(name, params:) { body }` with `@InvariantBuilder` |
| **RECURSIVE — evaluation** | ~ | Builtin `Sum(f,S)` and `SeqFromSet(S)` iterative evaluation; generic recursion not yet |
| **Fairness (WF/SF)** | ~ | Renders correctly in `.tlaModule`; not checked by ModelChecker |
| **Liveness** | — | Not in v1 scope |
| **Temporal properties** | ✓ | `TemporalDecl`, `LeadsTo`, `Eventually`, `AlwaysEventually` — TLA+ output only |
| **INSTANCE / EXTENDS custom** | — | External module dependencies; most TLC configs |
| **PlusCal** | — | Port post-translation TLA+ (like DiningPhilosophers) |
| **Refinement mappings** | — | Not in v1 scope |
| **Symmetry reduction** | ~ | `SymmetryDecl` exists; not active |
| **LET in actions** | ~ | Swift `let` in `Action { }` builder works for StateExpr; no ActionExpr-level LET |
| **Record field shorthand** | — | `msg.type` via `@dynamicMemberLookup` on StateExpr in builders |
| **Export** | ✓ | `.tlaModule` SANY/TLC-runnable |

## Port inventory

**25/25 TLC parity** — `scripts/validate_upstream_parity.sh` vs [tlaplus/Examples](https://github.com/tlaplus/Examples)

| Spec | States | Key features |
|------|--------|-------------|
| AsynchInterface | 6 | Records, sequences |
| Barrier_N6 | 64 | CHOOSE per-value, counters |
| CatOddBoxes / CatEvenBoxes | 30 / 48 | Nondet init |
| Chameneos M=4,N=4 | 34,534 | RECURSIVE Sum, tuples, @ self-ref, existsAction |
| ChangRoberts N=3 | 137 | CHOOSE per-value, per-node actions |
| Channel | 6 | Sequences |
| CigaretteSmokers | 3 | Sets, invariants |
| CoffeeCan (Max100/Max5) | 5,150 / 125 | Nondet init, constraints |
| DieHard TypeOK | 16 | Records, invariants |
| DiningPhilosophers NP=5 | 67 | Records, per-philosopher actions, ExclusiveAccess |
| EWD840 / SyncTD | 192 / 129 | Sequences, counters |
| EWD998 N=4 | 4,097 | Constraint, forAll, nondet init |
| HourClock / HourClock2 | 12 / 12 | Sequences, arithmetic |
| LamportMutex N=2 | 19 | Constraint, nested functions, Head/Tail, @ self-ref |
| Prisoner N=3 | 16 | Counter choice, VictoryOK |
| SimpleAllocator | 400 | Functions, invariants |
| SingleLaneBridge | 3,605 | forAll/filterSet builders, ifElse, RECURSIVE SeqFromSet |
| TCommit | 34 | State machine, invariants |
| TeachingConcurrency N=2,N=3 | 13 / 23 | PlusCal translation, per-node actions |
| TwoPhase | 288 | Records, invariants |

## Rule

**No feature without an oracle twin** (Swift test and/or TLC script) in the same change.

**Every nested scope gets a builder.**

## Version

Fragment B v1 — 2026-08-07
