# SwiftTLA language design

SwiftTLA lets an engineer write a bounded formal algorithm in a shape that
feels native to Swift: typed values, scoped result builders, enums for finite
domains, records for structured state, and generated machines for execution.
One authored application model becomes a compiled formal AST, a linked TLA+
bundle, and a typed Swift state machine.

## One public authoring form and a formal core

New application models use the Swift-shaped PlusCal form. The direct TLA+
builders remain formal-core tools for imported modules and parity fixtures.
They are not a competing public authoring form.

```
Swift-shaped PlusCal                         Direct TLA+
#spec { Algorithm { … } }                    TLASpec { Variable / Action / … }
          │                                           │
          ▼                                           │
     Algorithm IR                                     │
          │                                           │
          └──────────── lower once ───────────────────┘
                               ▼
                          TLASpec
                    ┌──────────┼───────────┐
                    ▼          ▼           ▼
                 checker   generated Swift  compiled TLA+ bundle
```

Swift-shaped PlusCal is the normal application path. Its parser and constrained
builder independently produce equivalent `Algorithm` IR, then the fidelity gate
compares that IR before either path lowers it. A second alpha-equivalence gate
compares the resulting TLA+ specifications. Diagnostics identify the first
semantic node, expected value, actual value, preserved state, and next safe
action.

Direct TLA+ is the formal-engine path for faithful upstream ports, imported
standard/community modules, and exact parity fixtures. It builds the TLA+ AST
directly and deliberately has no reverse conversion into Algorithm IR.

`#spec` is the authoring boundary. It makes Swift declaration sugar such as
`let count = SharedVar(initial: 0)` available to the scoped builder while the
source parser reads the original declaration independently. New conveniences
preserve this two-path construction.

## A small family of scoped builders

SwiftTLA has a small, fixed family of builders. Each builder represents a
formal scope and gives that scope a clear Swift spelling. The type checker uses
those scopes to guide correct construction before macro parsing or model
checking begins.

| Scope | Builder | It accepts | It produces |
|---|---|---|---|
| A complete specification | `#spec { ... }` / `SpecBuilder` | declarations, an `Algorithm`, and formal properties | `TLASpec` components |
| One PlusCal algorithm | `Algorithm { ... }` / `AlgorithmBuilder` | shared state, process families, and formal properties | algorithm components |
| One concurrent process family | `Each(domain) { self in ... }` | labeled atomic regions | one process definition for each finite member |
| One atomic region | `Do(label) { ... }` / `DoBuilder` | guards, assignments, local bindings, branching, and control transfer | one `StepStatement` list, lowered as one transition |

`DoBuilder` produces formal statements for one atomic transition. The generic
part of the API is the data that flows through it: `SharedVariable<Value>`,
`LocalVariable<Value>`, typed records, finite maps, finite domains, and typed
expressions. This keeps an atomic block strongly typed while making its
formal boundary obvious.

```swift
Algorithm("Counter") {
    let count = SharedVar(initial: 0)

    Each(Node.all) { _ in
        Do(Step.advance) {
            When(count < 1)
            Assign(count, to: count + 1)
            Stop()
        }
    }
}
```

Here, `SharedVar` belongs to the algorithm scope, `Each` introduces
independently scheduled finite processes, and `Do` groups the guard,
assignment, and stop into one atomic formal step. The builder layer makes
scope visible in the source and gives Swift a first opportunity to validate
the model.

### Typed formal data

Formal data has the same boundary. A record is declared in the specification
with a named schema, then used through a typed record expression; a finite map
is a typed function; and a finite Swift enum provides the members of a formal
domain. These are not UI-only descriptions. They survive parsing, lowering,
checking, TLA+ emission, and generated Swift state.

| Formal concept | SwiftTLA type | Example |
|---|---|---|
| finite member set | `FiniteDomainKey` enum | `CarID`, `Floor`, `Rider` |
| named total record | `TLARecordSchema` + `Record<Schema>` | a car’s floor, door, and rider |
| named record field | `TLAField<Schema, Value>` | `CarSchema.floor` |
| finite total map | `Function<Domain, Range>` | `Function<CarID, Record<CarSchema>>` |
| shared formal state | `SharedVariable<Value>` | `cars` |

The working elevator model is the reference implementation of this pattern:
`CarSchema` defines validated fields, `cars` is a typed finite function, and
all updates use typed fields rather than string subscripts.

Generated state and transition results use these named Swift types. Formal
names remain behind validated variables, fields, and domains.

### Adding a builder

Each new builder represents a formal scope with its own statements and
lowering rule. A future procedure, macro, or process-local scope may earn a
specific builder; expressions and assignments stay in the scopes that own
them.

Finite nondeterministic initialization is also formal semantics. For example,
`SharedVar(in: SetExpr<Record<CarSchema>>.literal(...))` means that the
initial predicate chooses one member of that typed, finite set. Both paths
retain the complete `initialSet`; it is compared by the fidelity gate and is
not reduced to a Swift collection or display hint.

## Compilation and execution phases

The two paths carry the authored model through the following phases:

1. The Swift compiler type-checks the `#spec` closure. Its result builders
   accept only the supported authoring vocabulary.
2. The `#spec` macro performs syntax-only desugaring. For example, it makes a
   `let count = SharedVar(initial: 0)` declaration visible to the runtime
   builder.
3. For an `Algorithm`, the model macro parses the original source into
   Algorithm IR. The constrained builder independently creates Algorithm IR.
4. SwiftTLA compares those two IR values, then lowers each through the one
   Algorithm lowerer into a TLA+ specification.
5. SwiftTLA compares the resulting specifications with semantic
   alpha-equivalence.
6. For direct TLA+ authoring, the macro and builder create only the TLA+ AST;
   no Algorithm IR is invented.
7. The checker, TLA+ emitter, and generated machine consume the validated
   TLA+ specification.

After construction and comparison, the generated machine holds its canonical
state machine and applies enabled transitions.

A structural fingerprint gives a fast diagnostic and cache key. Semantic
alpha-equivalence supplies the formal comparison: it recognizes equivalent
bound-variable names and identifies the semantic node that differs when the
models diverge.

```swift
@TLAModel
struct Counter {
    enum Node: String, FiniteDomainKey { /* bounded members */ }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)
                Each(Node.all) { _ in
                    Do("advance") {
                        When(count < 1)
                        Assign(count, to: count + 1)
                        Stop()
                    }
                }
            }
        }
    }
}
```

The `#spec` expansion registers `count` with the constrained runtime builder,
while the model macro parses the original declaration into the formal AST.

## Algorithm rendering

Algorithm IR has one semantic lowerer: `Algorithm IR → TLA+ AST`. It owns
atomic `Do` blocks, old-state simultaneous assignment, process state, `With`
and `Choose` bindings, procedures, and fairness.

`AlgorithmPlusCalRenderer` is not another lowerer. It consumes Algorithm IR
and prints retained, readable PlusCal source inside a valid TLA+ module; it
must not invent semantics or reimplement lowering.

## Capability claims use five levels

SwiftTLA does not call a feature “supported” merely because an AST case or an
evaluator branch exists. Every capability has five independent levels:

| Level | Meaning |
|---|---|
| Implemented | The engine can represent, evaluate, lower, or emit the concept. |
| Canonically authorable | A developer can express it through `#spec` and `Algorithm` without escaping to direct TLA+. |
| Fidelity-checked | The macro parser and constrained builder demonstrably retain the same formal model. |
| Generated cleanly | The model produces typed public state, actions, results, and generated tests. |
| Externally admitted | A declared finite model/configuration has retained TLC comparison evidence. |

An implementation-level result never implies the next level. For example,
formal operator application can exist in the evaluator while its canonical
Algorithm spelling, generated machine, or imported-module TLC witness remains
in progress. Reports state the achieved level and the next missing boundary.

For selected finite core models, the core-conformance command compares the
complete labeled transition relation from SwiftTLA with a pinned TLC run. This
includes initial states, state bindings, action labels, edges, and outcomes.
See `Documentation/CoreGraphConformance.md` and
`Documentation/CoreSupport.md` for the supported cases and commands.

## Finite graph conformance flow

`ModelChecker.explore()` produces one immutable exploration result: its BFS
graph, initial state IDs, checker outcome, and derived completeness come from
the same traversal. The Swift adapter canonicalizes that result without TLC
imports. Separately, TLC invokes the version-bound `LosslessStateWriter`,
which records callbacks as JSONL. The TLC adapter verifies the stream and
provenance, then canonicalizes it. The comparator checks the finite initial
set, state bindings, edge multiset, and outcome after the declared mappings.

The bridge carries complete graph evidence between the Swift and TLC runs.
Trace and replay files make a difference inspectable. Published TLA+ semantics
remain authoritative, with TLC serving as the pinned executable reference.

## Macro and package evidence boundary

The [public workflow conformance](PublicWorkflowConformance.md) command keeps
fixture results for `@TLAModel`, `@TLAActor`, and `@TLAObservable`, together
with the public-library macOS build. It is the release evidence for the
generated public interfaces.

## Generated-machine boundary

The macro derives a canonical Swift machine from the parsed `TLASpec`. The
machine generates typed `State`, `Variables`, `ActionLabel`, and
`TransitionResult` types. A transition result records the typed action and
typed state before and after one successful transition.

The formal engine retains its string-keyed state representation internally.
Application-facing APIs do not expose that map. `TLAStateProjection` validates
formal keys and values before formal tooling can inspect a state. A failed
projection produces a typed diagnostic instead of a partially valid map.

Nested `@TLAActor` and `@TLAObservable` declarations adapt the same canonical
model type. The actor provides isolated access. The nested observable is
main-actor isolated and invokes a typed callback after a transition commits.
Every public generated value is `Sendable`. See
[Generated machines](GeneratedMachines.md) and the SwiftTLA DocC catalog for
the supported surface.

## Ownership boundaries

The repository may keep its current files while the language work is moving,
but its ownership boundaries are fixed:

| Area | Owns | Must not own |
|---|---|---|
| `SwiftTLA` formal core | TLA+ AST, finite evaluation, module rendering, Algorithm IR, lowering, and PlusCal rendering | SwiftUI, application adapters, or macro-only semantics |
| `SwiftTLAPlugin` | syntax recovery, source spans, fidelity diagnostics, and typed generated surfaces | Algorithm lowering or TLA+ evaluation semantics |
| direct-TLA parity corpus | faithful direct-TLA modules, imports, and direct-TLA graph comparisons | application-shaped Algorithm fixtures |
| algorithm conformance corpus | canonical `#spec`/`Algorithm` fixtures, including upstream PlusCal ports and their retained authored PlusCal source | duplicate direct-TLA implementations of the same algorithm |
| `Examples/` consumers | demos and Apple integration shims that import the public package | a second state machine, availability policy, or formal evaluator |

The separate ValidationEvidence repository owns PlusCal-shaped fixtures and
their retained external evidence. This keeps core semantic tests independent
of the upstream corpus and keeps direct parity evidence distinct from
algorithm evidence.

## DSL philosophy

- **One authoring path.** Application models use `#spec` plus `Algorithm`,
  `SharedVar`, `LocalVar`, `Each`, `Procedure`, and `Do`. The algorithm builder
  creates formal IR; it does not execute ordinary Swift behavior.
- **Builders everywhere.** Every nested formal scope has a result builder:
  `Algorithm { }`, `Do { }`, `Action { }`, `Invariant { }`,
  `DefineRecursive { }`, `forAll(set) { _ in }`, and `filterSet(set) { _ in }`.
- **1:1 structural match.** DSL structure mirrors upstream TLA+ exactly.
  Same action names, same variable decomposition, same invariant names.
- **Direct TLA is an engine boundary.** `Var`, `Variable`, and `Action` remain
  available for imported TLA+ modules and upstream parity fixtures. They are
  not documented as a parallel application-model style.
- **No manual declarations.** All declaration structs have internal inits.
  Only builders create formal components.

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
| **Actions — `\E` SUBSET** | ✓ | `ActionExpr.existsSubset(name, of:) { _ in }` via `powerSet` |
| **CHOOSE** | ✓ | Cartesian product for multi-choose |
| **`\A` over sets** | ✓ | `forAll(set) { _ in }` builder; `StateExpr.forAll(set, body)` |
| **`\E` over sets** | ✓ | `existsIn(set) { _ in }` builder |
| **`{x \in S : P}` — set filter** | ✓ | `filterSet(set) { _ in }` builder |
| **Functions — apply** | ✓ | `f.applying(key)` |
| **Functions — EXCEPT** | ✓ | `f.updated(at: key, to: val)`; nested; `@` self-ref |
| **Functions — domain** | ✓ | `.domain` |
| **Functions — literal** | ✓ | `functionLiteral(var, in: domain, body)`; `TLAValue.function(dict)` |
| **Records — access** | ✓ | `StateExpr.recordAccess(expr, "field")`; `@dynamicMemberLookup` on `Var` for shorthand `msg.type` |
| **Records — literal** | ✓ | `StateExpr.recordLiteral(["field": expr])` |
| **Sequences — Head/Tail** | ✓ | `.head`, `.tail` |
| **Sequences — Append** | ✓ | `.appending(e)` |
| **Sequences — Len** | ✓ | `.count` |
| **Sequences — element** | ✓ | `sequence[index]` or `.at(i)` |
| **Bounded sequence domain** | ✓ | `Sequences(of: values, lengths: 0...n)` |
| **Bounded sorted integer sequence domain** | ✓ | `SortedSequences(of: values, lengths: 0...n)` |
| **Sequences — concatenate** | ✓ | `.concatenating(other)` |
| **Sets — union/intersection/diff** | ✓ | `.union`, `.intersection`, `.subtracting` |
| **Sets — subset** | ✓ | `.isSubset(of:)` |
| **Sets — cardinality** | ✓ | `.cardinality` |
| **Sets — powerset** | ✓ | `.powerSet` |
| **Sets — filter** | ✓ | See set filter above |
| **Arithmetic** | ✓ | +, −, *, /, %, >=, <=, >, <, =, != |
| **SAFETY — invariants** | ✓ | `Invariant("name") { expr }`; `InvariantBuilder` with `for` loop support |
| **SAFETY — deadlock** | ✓ | `DeadlockCheck()` |
| **Constraint** | ✓ | `Constraint(expr)` filters BFS successors; compiled bundle output includes `StateConstraint` |
| **CONSTANTS / ASSUME** | ✓ | `Constant(name, value)` emits `CONSTANTS`+`ASSUME`; parity script copies to `.cfg` |
| **Definitions** | ✓ | `Definition(tlaText)` raw TLA+ passthrough |
| **Theorems** | ✓ | `Theorem(tlaText)` raw TLA+ passthrough |
| **RECURSIVE — raw** | ✓ | `Recursive(tlaText)` raw TLA+ passthrough |
| **RECURSIVE — structured** | ✓ | `DefineRecursive(name, params:) { body }` with `@InvariantBuilder` |
| **RECURSIVE — evaluation** | ~ | Builtin `Sum(f,S)` and `SeqFromSet(S)` iterative evaluation; generic recursion not yet |
| **Fairness (WF/SF)** | ~ | Compiled bundle output contains the fairness condition; ModelChecker does not check it |
| **Liveness** | — | Not in v1 scope |
| **Temporal properties** | ✓ | `TemporalDecl`, `LeadsTo`, `Eventually`, `AlwaysEventually` — TLA+ output only |
| **INSTANCE / EXTENDS custom** | — | External module dependencies; most TLC configs |
| **PlusCal-shaped algorithms** | ~ | Bounded `Algorithm`, `Each`, `Do`, `When`, `Assert`, `Assign`, `If`, `Either`, `Choose`, `With`, `Goto`, `Stop`; parser and runtime builder have a mandatory semantic-equivalence gate |
| **Refinement mappings** | — | Not in v1 scope |
| **Symmetry reduction** | ~ | `SymmetryDecl` exists; not active |
| **LET in actions** | ✓ | Swift `let` in `Action { }` builder for StateExpr; no ActionExpr-level LET needed |
| **Record field shorthand** | ✓ | `@dynamicMemberLookup` on `Var` — `msg.type` works in builders |
| **Export** | ✓ | `try spec.compile().renderedTLAModuleBundle()` produces linked SANY/TLC input |

## Port inventory

**Selected TLC parity ports** — ported from [tlaplus/Examples](https://github.com/tlaplus/Examples) with in-process distinct-state regression tests; exact finite graph comparison for the declared core cases runs through the pinned core-conformance toolchain.

| Spec | States | Key features |
|------|--------|-------------|
| AsynchInterface | 6 | Records, sequences |
| Barrier_N6 | 64 | CHOOSE per-value, counters |
| BinarySearch | 27,963 | PlusCal `while`, scoped `with`, bounded sorted sequences |
| Consensus | 4 | PlusCal parameterless `macro`, `when`, scoped `with`, weak fairness |
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
| 2PCwithBTM | 1,245 | PlusCal macros, three fair process families, typed function state |
| TeachingConcurrency N=2,N=3 | 13 / 23 | PlusCal translation, per-node actions |
| TwoPhase | 288 | Records, invariants |

## Rule

**No feature without independent verification**: add a Swift regression test
and, where a bounded external comparison applies, a pinned TLC comparison in
the same change.

**Every nested scope gets a builder.**

## Version

Fragment B v1 — 2026-08-07
## System Flow

```mermaid
graph TD
    subgraph Compile["Compile Time"]
        direction TB
        DSL["@TLAModel struct { var spec: TLASpec { ... } }"]
        PARSER["SpecParser.parseSpecClosure()<br/>→ ParsedSpecComponents<br/>variables, actions, invariants, constants, temporal, fairness"]
        SPEC["TLASpec init<br/>14 SpecComponent types handled<br/>auto-UNCHANGED via completeAction"]
        CHECK["ModelChecker.check()<br/>maxStates=10k, BFS"]
        EMIT["emit: runtime property"]
        DSL --> PARSER --> SPEC --> CHECK -->|pass| EMIT
        CHECK -->|fail| ERROR["compile error + invariant trace"]
    end

    subgraph Data["Data Types"]
        SE["StateExpr — 51 cases<br/>value, variable, arithmetic(7), comparison(6), logic(4), ifThenElse,<br/>sets(11), tuples(7), records/functions(6), quantifiers(4), enabledAction,<br/>sequenceFromSet, setSum, recursiveCall"]
        AE["ActionExpr — 8 cases<br/>assign, unchanged, guard_, chooseAction, existsAction, ifElse, and, or"]
        TV["TLAValue — 8 cases<br/>int, bool, string, set, tuple, record, function, constant"]
        AE --> SE
    end

    subgraph BFS["ModelChecker BFS"]
        direction TB
        SUB["substituteConstants()<br/>inlines CONSTANT values<br/>also handles temporals via substituteInTemporal"]
        INIT["CompiledRuntime.initialStates()<br/>nondet sets → cartesian → initExpr"]
        LOOP["BFS loop: queue, visited set"]
        EXPAND["for each action: CompiledActionEnumerator.enumerate()<br/>→ filter successors by constraint"]
        DIST["distributeOr()<br/>single canonical function<br/>or→split, and→distribute, ifElse→guard+split, exists→pushInto"]
        PDIS["compiled action branches<br/>bindings → guards → assignments → slot-backed successor"]
        EVAL["CompiledEvaluator<br/>typed expressions and scoped bindings"]
        INV["check compiled invariants"]
        RESULT["CheckResult<br/>.ok | .invariantViolated | .deadlocked | .depthExceeded | .error"]
        GRAPH["StateGraph<br/>states + transitions + variableNames"]

        SUB --> INIT --> LOOP --> EXPAND --> DIST --> PDIS --> EVAL
        LOOP --> INV --> EVAL
        LOOP --> RESULT --> GRAPH
    end

    subgraph Export["Compiled bundle export"]
        TLASPEC["TLASpec"] --> COMPILE["compile()<br/>→ CompiledSpecification"]
        COMPILE --> BUNDLE["validated linked TLAModuleBundle<br/>root + transitive imports + CFG"]
        BUNDLE --> MATERIALIZE["materializeModuleBundle(to:)<br/>atomic sibling-directory publication"]
    end

    subgraph Parity["Evidence corpora"]
        DIRECT["Broad direct-TLA example catalogue<br/>semantic regression coverage<br/>not the external canonical corpus"]
        CORPUS["Canonical PlusCal corpus<br/>source-owned models and bundle manifests"]
        EXPORTER["Canonical corpus export<br/>writes the source-owned rendered bundle artifact"]
        EVIDENCE["ValidationEvidence hosted workflow<br/>official PlusCal translation + pinned TLC<br/>exact canonical graph comparison"]
        CORPUS --> EXPORTER
        BUNDLE --> EXPORTER
        EXPORTER --> EVIDENCE
    end

    subgraph Self["Self-Proof"]
        BFSGEN["TLASpec.bfsChecker(maxStates:)<br/>generates BFS lifecycle spec"]
        BFSCK["@TLAModel struct BFSChecker<br/>hardcoded maxStates=20"]
        BFSGEN --> CHECK
        BFSCK --> CHECK
    end
```

## Component Inventory

| Component | File | Input | Output |
|-----------|------|-------|--------|
| `StateExpr` | StateExpr.swift | — | 51-case expression AST |
| `ActionExpr` | ActionExpr.swift | — | 8-case action AST |
| `TLAValue` | TLAValue.swift | — | 8-case runtime value |
| `Var<T>` | Var.swift | name | `.becomes`, `.stays`, `@dynamicMemberLookup` |
| `TLASpec` | TLASpec.swift | DSL builder | immutable spec with 14 component types |
| `CompiledEvaluator` | CompiledEvaluator.swift | CompiledStateExpr + FormalState | CompiledValue |
| `CompiledActionEnumerator` | CompiledActionEnumerator.swift | CompiledAction + FormalState | slot-backed successors |
| `ModelChecker` | ModelChecker.swift | TLASpec | CheckResult + StateGraph |
| `CompiledRuntime` | CompiledRuntime.swift | CompiledSpecification | FormalState successors and invariant results |
| `SpecParser` | SpecParser.swift | SwiftSyntax | DSL types (7 public methods) |
| `ModelMacro` | ModelMacro.swift | struct source | extension + runtime property |
| `PrettyPrint` | TLASpec+PrettyPrint.swift | TLASpec | .tla string (13-step generation) |
| `distributeOr` | TLASpec+PrettyPrint.swift | ActionExpr | [[ActionExpr]] disjuncts |
| `completeAction` | TLASpec+PrettyPrint.swift | ActionExpr + vars | completed ActionExpr with per-branch UNCHANGED |
| `substituteConstants` | TLASpec.swift | TLASpec | TLASpec with constants inlined |

## Package Structure

```
SwiftTLA (library)
├── SwiftParser, SwiftBasicFormat, SwiftSyntaxBuilder (swift-syntax 600)
│
├── SwiftTLAPlugin (macro)
│   └── SwiftTLA, SwiftCompilerPlugin, SwiftSyntax, SwiftSyntaxMacros
│
├── SwiftTLAMacros (library)
│   └── @attached(member) @attached(extension) macro TLAModel
│
├── SwiftTLAModels (library)
│   └── BFSChecker (@TLAModel), BFSExplorer
│
├── UpstreamParity (library)
│   └── direct-TLA examples and canonical upstream corpus
│
├── tlc-validate (executable)
│   └── emits compiled TLA+ bundles for parity validation
│
└── SwiftTLATests (tests)
    └── 133 tests in 30 suites
```

## All Issues Resolved

| # | Issue | Resolution |
|---|-------|-----------|
| 1 | ComputedInitDecl dead code | Removed |
| 2 | SymmetryDecl dead code | Removed |
| 3 | Duplicate init state computation | CompiledRuntime owns initial-state construction |
| 4 | substituteConstants skipped temporals | Added `substituteInTemporal` |
| 5 | Two OR-distribution algorithms | Consolidated to single `distributeOr` |
| 6 | Var.init `value:` parameter | Intentional — type documentation |
| 7 | recursiveCall in substituteVariable | Already handled |
| 8 | SpecBuilder missing overloads | Removed with dead types |

## State (2026-08-07)

- **25/25** TLC parity
- **133** tests in **30** suites
- **51** StateExpr cases, **8** ActionExpr cases, **8** TLAValue cases
- **14** SpecComponent types handled by builder init
