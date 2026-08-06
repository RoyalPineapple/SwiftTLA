# SwiftTLA Lean Review

**Date:** 2026-08-06  
**Scope:** Correctness, duplication, dead code, API consistency, tests, examples, build/docs  
**Goal:** Lean and clean — what to keep, what to cut, what to fix

---

## Executive summary

The core of SwiftTLA is coherent: a Swift DSL for TLA+-style specs (`TLASpec` / `Var` / `StateExpr` / `ActionExpr`), an evaluator, action enumeration, BFS model checking, SpecParser, and `@TLAModel` codegen into concrete state machines.

Around that spine sits a lot of weight that does not pull its weight:

- A second, unused parser inside the macro (~200 LOC)
- A decorative `CheckerController` bolted onto real BFS with wrong fallthrough results
- Half-finished APIs (`constraint`, joint `Variable`, symmetry builder, UI codegen)
- Goldens that re-author simplified forks instead of checking shipped examples
- Stub examples under serious names, stale README/docs counts, and overlapping TLC scripts with disagreeing expected counts

**Bottom line:** Keep AST + evaluator + BFS + SpecParser + one codegen path. Delete forks, half-APIs, and theater. Point tests at real examples.

---

## Inventory

### Source modules

| Module | Role | Approx size |
|--------|------|-------------|
| `Sources/SwiftTLA/` | Core library (17 files) | ~3,300 LOC |
| `Sources/SwiftTLAPlugin/` | `@TLAModel` compiler plugin | ~460 LOC |
| `Sources/SwiftTLAMacros/` | `#externalMacro` stub | 2 LOC |
| `Sources/SwiftTLAUI/` | Inspector / graph / generators | ~220 LOC |
| `Sources/TLCValidate/` | Operator matrix CLI for TLC | ~145 LOC |

### Core file map (`Sources/SwiftTLA/`)

| File | Lines | Purpose |
|------|------:|---------|
| `ActionExpr.swift` | 31 | Action AST + `&&` / `\|\|` |
| `StateGraph.swift` | 32 | Reachability graph |
| `TemporalExpr.swift` | 42 | Temporal properties + fairness |
| `Runtime.swift` | 48 | `TLAMachine` protocol, actor, graph DTO |
| `CheckerController.swift` | 81 | Hand-rolled BFS lifecycle machine |
| `TLAValue.swift` | 86 | Runtime values |
| `SwiftSource.swift` | 96 | Spec → Swift DSL printer (partial) |
| `ActionEnumerator.swift` | 131 | Action → next-state enumeration |
| `StateExpr.swift` | 134 | State expression AST |
| `TLASpec+PrettyPrint.swift` | 136 | Spec → TLA+ module, codec, `completeAction` |
| `StateMachineGenerator.swift` | 223 | Graph → concrete machine source |
| `LivenessChecker.swift` | 225 | SCC-based temporal checking |
| `Var.swift` | 273 | Typed vars, operators, binders |
| `ModelChecker.swift` | 301 | BFS explorer + `CheckResult` |
| `Evaluator.swift` | 364 | `StateExpr` interpreter |
| `TLASpec.swift` | 540 | Spec model, builder DSL, decls |
| `SpecParser.swift` | 570 | SwiftSyntax → DSL AST |

### Tests, examples, specs, scripts

| Area | On disk |
|------|---------|
| Tests | `RoundTripTests.swift` (~86 `@Test`), `SpecParserTests.swift` (~46), meta-models; empty `Unit/`, `Integration/`, `Examples/`, `SwiftTLAMacroTests/` |
| Examples | **23** specs under `Examples/Sources/Examples/` (README claims 12) |
| Specs | `Specifications/ModelChecker/*`, `Specifications/BFSExplorer/*` |
| Scripts | `setup-tlc.sh`, `validate_golden.sh`, `validate_operators.sh`, `validate_tlc.sh` |
| Build | Root SPM, nested `Examples/` SPM, Tuist/Xcode proj + workspace |

---

## What is solid

Keep and lean around these:

1. **DSL surface** — `TLASpec` result builder, `Var`, `Action` / `Invariant`, `becomes` / guards
2. **AST** — `StateExpr`, `ActionExpr`, `TLAValue`
3. **Evaluator + ActionEnumerator** — core semantics (with known gaps below)
4. **BFS safety checking** — explore, invariant violation, deadlock, graph build
5. **SpecParser** — single real parse path from Swift syntax
6. **StateMachineGenerator** — graph → concrete `TLAMachine` (when inputs are valid)
7. **Basic UI views** — inspector / step UI themselves are small; generators are the problem

---

## Correctness issues

Severity: **Critical** > **High** > **Medium**.

### Critical / high

#### 1. Constraint polarity inverted (and effectively dead)

```swift
// ModelChecker.swift — skips exploration when constraint is *true*
if let checkConstraint = constraint, evaluate(checkConstraint, current) {
    checker.apply(.stepNoNew)
    continue
}
```

TLC-style state constraints mean: explore only when the constraint holds. Here **true skips**.  

`SpecBuilder` hardcodes `constraint: nil` and there is no `Constraint(...)` decl in the builder switch. Field exists via memberwise init only — wrong semantics + no public builder entry.

**Fix:** Either implement TLC polarity + a builder entry, or delete the field.

#### 2. Majority example is unsatisfiable at init

`Examples/Sources/Examples/Major/Major.swift`:

- `cand` initial value `0`
- TypeOK requires `cand >= 1 && cand <= 3`

Model-checking the shipped example should fail immediately on the initial state. Catalog claims `expectedStates: 5`.

#### 3. ExamplesApp metadata zip is wrong

`ExampleID` is 7 cases ending in `.allocator`.  
`Examples.all[6]` is **MissionariesAndCannibals**, not Allocator.

```swift
// ExamplesApp — zip by index
Dictionary(uniqueKeysWithValues: zip(ExampleID.allCases, Examples.all))
```

Sidebar label/about for `.allocator` become Missionaries metadata while the theme view still shows Allocator.

#### 4. Macro ignores non-invariant check failures

```swift
// ModelMacro.swift
if case .invariantViolated(...) = (try? checker.check()) {
    throw ...
}
// deadlock / depthExceeded / error → ignored; expansion continues
```

Also: `try?` swallows checker throws entirely.

#### 5. Macro UNCHANGED completion is incomplete

Runtime path uses OR-aware `completeAction` (`TLASpec+PrettyPrint.swift`).  
Macro reimplements a flat loop with `assignedVars` — no OR distribution. Relies on enumerator accidents for disjunctive actions.

#### 6. Multi-`choose` is not a Cartesian product

`ActionEnumerator.processDisjunct` handles multiple `choose` actions sequentially/independently.  
`choose(x) && choose(y) && ...` will not jointly bind all combinations.

#### 7. `try!` on invariant / constraint evaluation

```swift
// ModelChecker.swift
{ expression, state in try! Evaluator.evaluateBool(expression, in: state) }
```

Type errors in invariants crash the process instead of `CheckResult.error`.

#### 8. CheckerController fallthrough lies

BFS returns real invariant/deadlock results early. If the loop exits in `phaseViolated` or `phaseDeadlocked`, the switch maps both to **`.depthExceeded`**.

Controller counters also do not match real BFS (`stepDiscover` accounting, processed/queued). Comment claims generation from `CheckerModel.swift`; that file diverges (no violate phase, different Complete/Deadlock guards).

#### 9. Goldens do not validate shipped examples

Golden tests in `RoundTripTests` re-author simplified specs. They diverge from Examples:

| Spec | Golden expectation | Real example / app |
|------|--------------------|--------------------|
| CoffeeCan | 21 (pick actions only) | + Termination + DeadlockCheck; app says 36 |
| MovingCat | 18 (`dir: Int`) | `direction: String`; app says 70 |
| Majority | Stub counter; `count >= 1` | Real Boyer-Moore; cand init broken |
| HourClock | `hr < 12` | `hr != 12` (equiv., but not shared) |
| DieHard | Inlined 3× | Also in Examples |

“TLC-verified golden equivalence” does **not** cover the catalog users run.

#### 10. Macro fails closed on terminal-only specs

Throws if explored graph has zero edges. Valid “init + invariant, no Next” specs cannot use `@TLAModel`.

#### 11. `substituteConstants` drops `initialSet`

Nondeterministic init metadata is stripped when substituting constants → `computeInitialStates` may stop expanding sets.

#### 12. Joint `Variable(_:_:in:where:)` is broken

Creates one fake var `"x+y"` whose initial is a tuple of pairs, not two vars with a constrained product. Not handled by checker init expansion. Should not ship.

#### 13. `Var` discards `value:`

```swift
public init(_ name: String? = nil, value: T? = nil) {
    self.name = name ?? ""
}
```

Docs/examples show typed inits; value is ignored. Default name `""` is a footgun.

#### 14. Liveness semantics are approximate

`LivenessChecker` (untested publicly):

- `.always` / `.eventually` only checked on fair terminal SCCs — not full path semantics
- `.leadsTo` is SCC co-occurrence, not path-sensitive
- Fairness filter drops unfair SCCs rather than restricting behaviors
- `buildPrefix` assumes initial `id == 0` (false with multiple initials)
- `buildCycle` is a greedy walk capped at 10, not a real cycle witness

Looks authoritative; is not TLC-grade.

### Medium

| Issue | Where | Notes |
|-------|-------|-------|
| `setFilter` builds `boundState` then ignores it | `Evaluator.swift` | Eval uses unsubstituted env; fragile for nested binders |
| `divide` ≡ `integerDivide` | Evaluator + StateExpr | Same op, two AST cases, both print `\div` |
| `powerSet` traps on large sets | `1 << elems.count` | Trap/UB for large counts; blowup earlier |
| `caseExpr` assumes even pair list | description + eval | Odd length traps |
| Action expand uses `try?` → `[]` | ModelChecker | Malformed actions look disabled |
| Symmetry auto from every set-valued initial | ModelChecker | Aggressive; `SymmetryDecl` not in SpecBuilder |
| `decode(base64:)` force unwraps | PrettyPrint | Crash on bad input |
| Liveness force unwraps | LivenessChecker | Graph lookup / Tarjan maps |
| SwiftSource incomplete | SwiftSource | `default: description` emits TLA as “Swift”; hardcodes `Var<Int>` |
| String segments in parsers | SpecParser / macro | Quote stripping inconsistent |
| `TLAValue.Comparable` | TLAValue | Total order by type tag — display only, looks semantic |

---

## Duplication

### 1. Full parser fork in the macro (highest LOC waste)

`SpecParser` is the real parser. Hot path in the macro already delegates. Still present and unused:

| Method | Approx lines | Status |
|--------|-------------:|--------|
| `parseSingleAction` | 241–273 | Unused (self-only) |
| `parseBecomesChain` / `unwrapWhen` / `parseBecomes` | 275–304 | Unused; weaker (no `choose`) |
| `parseMethodCall` | 332–380 | Unused |
| `parseStaticCall` | 382–428 | Unused; incomplete |
| `parseMemberAccess` | 430–441 | Unused; no record field fallback |

**~200 lines of zombie parser. Delete; call `SpecParser` only.**

### 2. UNCHANGED completion twice

- `completeAction` + private `assignedVarNames` — `TLASpec+PrettyPrint.swift`
- Public `assignedVars` — `TLASpec.swift` (same as `assignedVarNames`)
- Macro flat loop — `ModelMacro.swift`

Collapse to one: `assignedVars` + `completeAction`. Macro must call `completeAction`.

### 3. Triple StateExpr tree walkers

Nearly identical exhaustive switches:

1. `Evaluator.substituteVariable`
2. `replaceVarInState` (`Var.swift`)
3. `substituteInState` (`TLASpec.swift`)

One `mapChildren` / fold cuts ~150 LOC and prevents missing cases when AST grows.

### 4. Triple checker story (drifted)

| Artifact | Role | Divergence |
|----------|------|------------|
| `ModelCheckerProof.tla` | Abstract BFS proof | Different result vocab; `Reachable` def suspect; TLC-hostile bits |
| `CheckerModel.swift` | DSL meta-spec | No violate phase; Complete when `processed >= queued \|\| maxStates` |
| `CheckerController.swift` | Runtime machine | Has violate; different Complete/Deadlock; claims “generated” but is not |

BFS embeds the controller without verifying correspondence.

### 5. DieHard and other specs cloned in tests

DieHard appears in Examples, ModelCheckerMatrix, and GoldenTests.  
CoffeeCan / MovingCat / Majority goldens are forks, not shared fixtures.

### 6. ActionEnumerator tested three ways

- `VarOperatorMatrix.actionMatrix`
- `ActionExprMatrix`
- `ActionExprCompleteTests`

Overlapping assign/guard/or coverage.

### 7. Operator / enabled naming soup

- Arithmetic/comparison defined on `Var where T == Int`, `StateExpr` statics, and free `StateExprConvertible` functions
- Enabled transitions: `availableTransitions` / `enabledTransitions` / UI wants `enabledActions`

### 8. TLC validate scripts overlap and disagree

`validate_operators.sh` and `validate_tlc.sh` both drive `tlc-validate` with **different expected state counts** for the same operator families (e.g. arithmetic 8 vs 4). At most one is right.

---

## Dead or unused code

| Item | Location | Why dead / broken |
|------|----------|-------------------|
| Macro private parser block | `ModelMacro.swift` ~241–441 | Superseded by SpecParser |
| `statesEqual` | StateMachineGenerator | Never called |
| `extractInt` always returns 0 | StateMachineGenerator | Used by `generateGraph` → broken output |
| `generateGraph` | StateMachineGenerator | No call sites |
| `Runtime` actor | Runtime.swift | No production use |
| `enabledTransitions` alias | Generator + CheckerController | Redundant |
| `Symmetry` / `SymmetryDecl` in builder | TLASpec | Not handled in SpecBuilder switch |
| `constraint` via builder | always nil | Memberwise only |
| Joint `Variable` | TLASpec | Broken |
| Unused SwiftSyntax imports | PrettyPrint, SwiftSource | String concat only |
| `ViewGenerator` locals | varNames, stateDesc | Computed, unused |
| Empty test directories | Tests/... | Abandoned scaffold |
| `states/` TLC debris dirs | repo root | Empty timestamp dirs |

### UI generators do not match codegen

| Generator assumes | Actual codegen |
|-------------------|----------------|
| `TypeName.Machine` | Nested / top-level `StateMachine` |
| `enabledActions` | `availableTransitions` (+ alias `enabledTransitions`) |

`ViewModelGenerator` / `ViewGenerator` output does not compile against current machines. Fix names or delete until needed.

---

## Over-engineering

1. **CheckerController inside BFS** — Second state machine “controlling” the checker adds complexity and wrong mappings. Drive BFS from queue/visited only; keep CheckerController as an *example* machine if desired, not as the explorer’s brain.

2. **SpecComponent + type-erased `as?` chain** — Marker protocol + many decl types + giant if-else. An enum `SpecItem` would be smaller and exhaustive.

3. **Two front doors for one DSL** — Runtime builder executes Swift; macro re-parses syntax with a partial subset. Drift is inevitable (macro misses Assume, Extends, DeadlockCheck, Definition, Theorem, joint Variable, etc.).

4. **Phantom type tags** — `TLASetType` / `TLATupleType` / … always encode empty containers; they do not carry element types.

5. **GraphView is not a graph** — Vertical list + arrow icon; DTO heavier than UI needs.

6. **Macro full model-check at compile time** (cap 10k) — Powerful but couples compile latency to state space and duplicates runtime checking with weaker error handling.

7. **base64 JSON codec** — Crashy; unclear product need next to Codable.

8. **Core library depends on SwiftSyntax** — Model-checker consumers pull the full syntax stack. Parsing/codegen could be a separate target.

---

## API and naming inconsistency

| Issue | Detail |
|-------|--------|
| `availableTransitions` / `enabledTransitions` / `enabledActions` | Same idea, three names |
| `Machine` vs `StateMachine` vs spec struct name | Macro renames to nested `StateMachine`; UI wants `.Machine` |
| `stays` / `UNCHANGED` / `.unchanged` | Three vocabularies |
| `becomes` vs `assign` | DSL vs AST |
| `WeakFairness("A")` vs parser `"Fairness" { ... }` | Runtime free functions vs macro shape |
| Temporal free functions vs macro `Temporal("name")` | Macro/parser shape not aligned with all public APIs |
| `count` vs `cardinality` | Tuple length vs set size |
| `flattened` / `subsets` | Cute Swift names, opaque to TLA readers |
| `CheckResult.depthExceeded` | Also misused for violate/deadlock fallthrough |
| CheckerController phase ints 0–3 | Magic numbers instead of enum |
| `Extends` replaces modules string | Not cumulative; last wins |
| `schedule` on Runtime | Applies immediately; not a scheduler |
| `guard_` | Underscore to avoid keyword — fine but lonely |

---

## Cross-module oddities

### Macros vs runtime

| | Runtime `TLASpec { }` | `@TLAModel` |
|--|----------------------|-------------|
| Path | Execute builder | Re-parse AST |
| UNCHANGED | `completeAction` (OR-aware) | Flat assigned-vars loop |
| Assume / Extends / Deadlock / Theorem / Definition | Yes | Partial / no |
| On invariant fail | `CheckResult` | Compile error |
| On deadlock / depth / error | Result | **Ignored** |
| Output | Spec value | Nested `StateMachine` source |

Plugin depends on **SwiftTLA + SwiftTLAUI** but `ModelMacro` never imports/uses UI — unnecessary edge.

### Package test target is narrow

`SwiftTLATests` depends only on `SwiftTLA` — not macros, UI, or Examples. Macro expansion, UI, and real example integration cannot be tested in-tree without package changes.

### Empty / missing test areas

| Source | Coverage |
|--------|----------|
| LivenessChecker (~225 LOC) | **Zero tests** |
| SwiftTLAUI | No test target dep |
| ModelMacro / Macros | Empty `SwiftTLAMacroTests/`; CI only builds plugin |
| Runtime actor | Untested / unused |
| Real Examples/* | Never imported; goldens are forks |

README claims **62 tests / 12 suites**. On disk: **~132 `@Test`** in two monolith files. Architecture diagram counts are stale.

---

## Examples review

### Full list (23)

Allocator, Bakery, CarTalkPuzzle, CoffeeCan, DieHard, DiningPhilosophers, GameOfLife, HourClock, Major/Majority, MissionariesAndCannibals, MovingCat, MultiPaxos, NQueens, Paxos, Prisoners, ReadersWriters, SingleLaneBridge, SlidingPuzzles, Stones, SumsEven, Termination, TortoiseHare, TransitiveClosure

README claims **12**.

### Quality tiers

**Real-ish ports:** HourClock, DieHard, CoffeeCan, MovingCat, Majority (broken init), Allocator, Bakery, DiningPhilosophers, MissionariesAndCannibals, MultiPaxos, Paxos, TortoiseHare, Stones, SumsEven  

**Name-only stubs** (same counter `x < 10` pattern): ReadersWriters, SingleLaneBridge, SlidingPuzzles, Termination, TransitiveClosure  

**Near-stubs / misleading:** NQueens (place counter), GameOfLife (`cells % 8`), Prisoners (2-action toy), CarTalkPuzzle (nested counter), Paxos/MultiPaxos (flat ints, comments claim records)

### Catalog bugs (`Examples.swift`)

- Duplicate CarTalkPuzzle and Prisoners entries
- Most `expectedStates: 0`
- CoffeeCan 36 / MovingCat 70 disagree with README and goldens
- Folder `Major/` vs type `Majority`
- Spec module name casing inconsistent (`"allocator"` vs `"HourClock"`)

### ExamplesApp

Only 7 of 23 get theme views. Zip bug maps allocator → wrong metadata (see Correctness #3).

---

## Specs vs implementation

### BFSExplorer

TLA (`Specifications/BFSExplorer/BFSExplorer.tla`) and Swift (`BFSExplorerModel.swift`) are not 1:1:

- Swift adds `picked`; TLA bounds successors with `∩ States`; Swift does not
- Different properties (TLA has ReachableClosure / NoDuplicates / Completion)
- Comment claims “1:1 port”; test only asserts `count > 0`
- No script runs TLC compare

### ModelCheckerProof

- `Reachable` definition is not real reachability
- `SeqOfSet` recursive — TLC-hostile
- Result vocabulary differs from Swift phases
- `MC_Instance.tla` function syntax is nonstandard / likely SANY-unfriendly
- No CI runs these specs

### Documentation drift

`Documentation/TLAForSwiftEngineers.md` teaches removed APIs (`Act` / `Inv` / `next(x)`), unicode `∈`, missing choose/quantifiers/liveness, and a nonexistent `swift run swift-tla generate` tool.

README usage samples are closer to reality than the long doc.

---

## Scripts and build weirdness

### Scripts

| Script | Issue |
|--------|--------|
| `setup-tlc.sh` | OK; hardcodes tla2tools version |
| `validate_golden.sh` | Expects per-example executables; Examples package only has `Examples` GUI. Hardcoded `JAVA_HOME`. Only 3 names. Not executable bit. |
| `validate_operators.sh` | Expected counts A |
| `validate_tlc.sh` | Expected counts B ≠ A; overlapping cases |

CI runs `swift test` / `swift build` only — no TLC scripts, no Examples package build.

### Build systems (triple)

1. Root SPM — canonical for CI  
2. Nested `Examples/Package.swift` path-dep on `../`  
3. Xcode/Tuist: `SwiftTLA.xcodeproj` + `Workspace.xcworkspace` (`.gitignore` ignores `*.xcodeproj` / `*.xcworkspace` yet they exist on disk)

### Makefile stale

Points at `swift run demo` / `demo check hourclock` — no such product. Real GUI: `swift run --package-path Examples Examples`.

### Other

- Platforms: macOS 14 only (UI present, no iOS)
- `unsafeFlags(["-warnings-as-errors"])` on library + tests; Examples package has no matching settings
- README references LICENSE file — no LICENSE on disk
- Plugin → UI dependency without use

---

## Ruthless cut list

Delete or stop shipping until fixed:

1. Dead macro parser (~200 LOC in `ModelMacro.swift`)
2. `generateGraph` + `extractInt` stub
3. `Runtime` actor (or actually use it and drop ad-hoc UI state)
4. Joint `Variable(_:_:in:where:)`
5. `Symmetry()` builder API **or** wire it; stop silently symmetrizing every set init
6. `constraint` field **or** fix polarity + builder entry
7. `assignedVarNames` → use only `assignedVars`; macro → `completeAction`
8. `divide` / `integerDivide` collapse
9. Three StateExpr rewriters → one
10. `CheckerController` **out of** BFS loop (keep as example only)
11. `ViewModelGenerator` / `ViewGenerator` until they match real APIs
12. `enabledTransitions` alias — pick one name
13. Stub examples (or mark clearly as stubs / remove from catalog)
14. Duplicate catalog entries
15. One of the two overlapping TLC validate scripts
16. Empty test directory scaffolding
17. Stale Makefile `demo` targets
18. Obsolete doc sections or rewrite to current DSL

---

## Recommended fix order

### Phase 1 — Truth and safety (do first)

1. Fix or delete `constraint` (polarity)
2. Map evaluator errors → `CheckResult.error` (no `try!` on invariant path)
3. Macro: handle all `CheckResult` cases; use `completeAction`; do not require transitions
4. Fix Majority init vs TypeOK
5. Fix `Examples.all` (dedupe, counts) and ExamplesApp zip/metadata
6. Delete dead macro parser

### Phase 2 — One path

7. Goldens import real Example specs (Examples as test dependency or shared fixtures)
8. Collapse assigned-vars / StateExpr walkers / divide
9. Remove CheckerController from BFS; fix fallthrough permanently
10. Align transition property name everywhere; fix or delete UI codegen
11. Drop plugin → SwiftTLAUI dependency if unused

### Phase 3 — Catalog and proof hygiene

12. Cull or rewrite stub examples; refresh README counts
13. Merge TLC scripts; fix `validate_golden.sh` product model
14. Reconcile or delete `Specifications/*` until TLC-runnable and matched
15. Add minimal LivenessChecker tests **or** mark API experimental
16. Macro expansion tests (or drop empty test target)
17. Rewrite/delete `TLAForSwiftEngineers.md`; fix Makefile; add LICENSE or drop claim

### Phase 4 — Structure (optional, after lean)

18. Split `RoundTripTests.swift`
19. Consider splitting SwiftSyntax-heavy parse/codegen from pure checker target
20. Enum `SpecItem` instead of `SpecComponent` + `as?`

---

## Suggested end state (lean architecture)

```
Swift DSL  ──► SpecParser (only) ──► TLASpec
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              ModelChecker      .tlaModule        StateMachineGenerator
              (plain BFS)       pretty-print      (one machine name)
                    │
                    ▼
              CheckResult / StateGraph
                    │
              @TLAModel (thin): parse → completeAction → check → generate
```

No second parser. No controller inside BFS. No goldens that aren’t the shipped specs. No stub examples pretending to be Paxos.

---

## Appendix A — Duplication map

```
DieHard ────────┬── Examples/DieHard
                ├── RoundTripTests ModelCheckerMatrix
                └── RoundTripTests GoldenTests (+ inv twin)

UNCHANGED ──────┬── completeAction + assignedVarNames
                ├── assignedVars
                └── ModelMacro flat loop

StateExpr walk ─┬── Evaluator.substituteVariable
                ├── Var.replaceVarInState
                └── TLASpec.substituteInState

Checker story ──┬── ModelCheckerProof.tla
                ├── CheckerModel.swift
                └── CheckerController.swift  (embedded in BFS)

Parser ─────────┬── SpecParser (live)
                └── ModelMacro private block (dead)

Operator TLC ───┬── validate_operators.sh (expect A)
                └── validate_tlc.sh       (expect B ≠ A)
                     both → tlc-validate

Action enum ────┬── VarOperatorMatrix.actionMatrix
                ├── ActionExprMatrix
                └── ActionExprCompleteTests

Enabled name ───┬── availableTransitions
                ├── enabledTransitions
                └── enabledActions (UI, wrong)
```

---

## Appendix B — Highest-value correctness fixes (checklist)

- [ ] Constraint polarity + expose or remove
- [ ] Stop `try!` on invariant evaluation
- [ ] Multi-choose product in ActionEnumerator
- [ ] Preserve `initialSet` in `substituteConstants`
- [ ] Remove CheckerController fallthrough / remove from BFS
- [ ] Macro: `completeAction`, all check failures, allow zero transitions
- [ ] Delete macro dead parser
- [ ] Fix UI codegen names or stop shipping generators
- [ ] Majority init / TypeOK
- [ ] Examples catalog dedupe + ExamplesApp zip
- [ ] Goldens → real examples
- [ ] Merge disagreeing TLC validate scripts

---

## Appendix C — What not to over-fix

While cleaning:

- Do not invent a new framework for “pluggable explorers”
- Do not add more meta-specs until the existing three checker stories are one
- Do not grow Examples until stubs are gone and goldens bind to real specs
- Do not expand liveness marketing until there are tests and honest semantics docs
- Prefer deletion over abstraction when fixing duplication

---

*End of report.*
