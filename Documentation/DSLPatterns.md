# SwiftTLA DSL Patterns

## Core rule: the DSL is the runtime

Every construct in the DSL serves **two roles**:
1. **TLA+ output** — `.tlaModule` renders it as valid TLA+/SANY source
2. **Runtime evaluation** — `Evaluator` interprets it against an internal formal state

There is never a raw TLA+ string where a DSL construct could express the same thing.
The DSL body IS the implementation.

## Compiler rule: verified models become executable behavior

`@TLAModel` is a compile-time behavioral compiler. Swift types constrain which
models can be constructed; the macro parses the supported DSL into the existing
AST, runs global model checking, and emits executable state-machine or actor
behavior only after that check succeeds. The generated runtime reuses the
verified model's actions rather than accepting a separate implementation.

## Legacy symmetric-collection boundary

`SymmetricCollectionVar<Element, Value>` is retained for formal-engine and
parity fixtures only. Do not use it in new application models, demos, or
authoring documentation. New models use `#spec` with `Algorithm`, `SharedVar`,
and typed `Function`, `SetExpr`, and `Record` expressions.

The retained engine surface separates two identity domains.
Runtime storage is keyed by concrete `Element.ID` values and may contain an
arbitrary number of live entries. Verification derives exactly
`verificationScope` opaque `.constant` model members; concrete IDs, including
Bluetooth UUIDs, never enter `StateExpr`, `TLAValue`, generated TLA+, or TLC
artifacts.

The collection API does not add a parallel expression language. It lowers to
established AST forms:

- A selected read is function application.
- `allSatisfy` lowers to `forAll` over the collection function domain and
  `contains(where:)` lowers to `exists` over that domain. Both value-only
  predicates are supported in runtime-built specifications and in `@TLAModel`
  parsing.
- `CollectionAction` existentially selects one opaque member. Its selected
  update lowers to a function `EXCEPT`, leaving every unselected entry
  unchanged. The generated runtime action instead receives an `Element.ID`,
  evaluates the authored guard and effect against that selected live entry, and
  preserves its peers.

The selection token is intentionally opaque: it may select or update only its
own collection within its `CollectionAction`. It cannot be compared, ordered,
stringified, persisted, or used to observe a model member's identity. This
identity blindness is what permits symmetry reduction.

The checker canonicalizes the complete state under every permitted bijection of
each collection's opaque members, including nested keys and values, and retains
the deterministic minimum encoding. Collections use independent permutation
groups and must fit the configured product budget; the checker never silently
falls back to an unsound reduction.

## Symmetric collection oracle and proof boundary

The TLA+ bundle declares distinct generated constants and its CFG assigns each
one to a TLC model value, then declares the matching `Permutations(domain)`
symmetry operator. Do not use quoted strings as member identities: TLC model
values are the oracle contract. A feature change must run TLC on the generated
module/CFG at the selected scope and compare its result with the internal
checker, alongside ordinary DSL tests.

A successful run verifies only the explicitly selected finite scope. It is not
evidence for larger or arbitrary populations, and it makes no `N → infinity`
claim. Locality-checked parametric verification is future work; it requires a
separate proof rather than extrapolation from bounded runs.

## Builder rule: every nested scope gets a builder

| Construct | Builder | Result |
|-----------|---------|--------|
| `TLASpec("Name") { ... }` | `@SpecBuilder` | `SpecComponent[]` |
| `Action("Name") { ... }` | `@ActionBuilder` | `ActionExpr` |
| `Invariant("Name") { ... }` | `@InvariantBuilder` | `StateExpr` |
| `Variable(computed: x) { ... }` | `@InvariantBuilder` | `StateExpr` (initExpr) |
| `DefineRecursive("Name", params:) { ... }` | `@InvariantBuilder` | `StateExpr` (body) |
| `forAll(set) { _ in ... }` | `@InvariantBuilder` | `StateExpr` |
| `filterSet(set) { _ in ... }` | `@InvariantBuilder` | `StateExpr` |
| `exists(name, from:) { _ in ... }` | `(StateExpr) -> ActionExpr` | `ActionExpr` |

## Naming rule: enums, never string literals

Every known set of identifiers uses a `String`-backed enum:

| Domain | Enum | Location |
|--------|------|----------|
| State method calls | `StateMethod` | SpecParser |
| Temporal constructors | `TemporalMethod` | SpecParser |
| Fairness constructors | `FairnessMethod` | SpecParser |
| Recursive function builtins | `RecursiveFunction` | Evaluator |

No bare string literals in pattern-matching switches.

## Type safety rule: no bare-string-keyed collections

The formal engine uses `[String: TLAValue]` internally. This representation is
not an application-facing API. Engine code derives every key from a typed source
such as `Var<T>.name` or `RecursiveFunc.name`; it never writes a bare key.

Generated application APIs expose typed `State`, `Variables`, `ActionLabel`,
and `TransitionResult` values. `TLAStateProjection` is the guarded bridge for
formal tooling that must inspect a formal state. See
[Generated machines](GeneratedMachines.md) for the public contract.

## Construct rule: one way to build

There is exactly one builder function per construct type. Internal `*Decl` structs have
internal initializers — only the builder function can create them.

| Builder function | Creates | Internal type |
|-----------------|---------|---------------|
| `Variable(x, 0)` | `VarDecl` | `VarDecl` |
| `Variable(x, in: set)` | `VarDecl` | `VarDecl` |
| `Variable(computed: x) { ... }` | `VarDecl` | `VarDecl` |
| `Action("Name") { ... }` | `ActionDecl` | `ActionDecl` |
| `Invariant("Name") { ... }` | `InvDecl` | `InvDecl` |
| `Constant("N", value)` | `ConstantDecl` | `ConstantDecl` |
| `Constraint(expr)` | `ConstraintDecl` | `ConstraintDecl` |
| `Assume(expr)` | `AssumeDecl` | `AssumeDecl` |
| `Extends("Naturals")` | `ExtendsDecl` | `ExtendsDecl` |
| `DefineRecursive("F", params:) { ... }` | `RecursiveFuncDecl` | `RecursiveFuncDecl` |
| `Recursive(tlaText)` | `RecursiveDecl` | `RecursiveDecl` |
| `RuntimeFunc("F", tla:, impl:)` | `RuntimeFuncDecl` | `RuntimeFuncDecl` |
| `DeadlockCheck()` | `DeadlockDecl` | `DeadlockDecl` |

## Validation rule: upstream parity or oracle twin

Every ported spec must match TLC state count. Every new DSL feature must be
exercised by at least one port. No feature without an oracle.

## Composition rule: every struct composes

- `TLASpec.extending(other)` — merges two specs (checker + user)
- `TLASpec.instantiating(constants)` — overrides CONSTANT values
- `substituteConstants(spec)` — inlines constants across all fields
- `distributeOr(action)` — single canonical OR-distribution, shared by enumerator and completeAction
- `computeInitialStates(spec)` — shared between ModelChecker and SpecRuntime

## What goes where

| File | Role | Must have |
|------|------|-----------|
| `StateExpr.swift` | Expression AST | 51 cases, description, Codable/Sendable/Equatable |
| `ActionExpr.swift` | Action AST | 8 cases, overloading operators |
| `TLAValue.swift` | Runtime value | 8 cases, Comparable, ExpressibleBy*
| `Var.swift` | Variable refs | Type-safe, operators, @dynamicMemberLookup |
| `Evaluator.swift` | Expression eval | Every StateExpr case handled |
| `ActionEnumerator.swift` | Action expansion | distOr + processDisjunct phases |
| `ModelChecker.swift` | BFS verification | BFS + invariants + constraints |
| `SpecRuntime.swift` | Interactive runtime | Wraps ActionEnumerator + Evaluator |
| `TLASpec.swift` | Spec container | Builder init, global builder fns, component types |
| `TLASpec+PrettyPrint.swift` | TLA+ export | 13-step generation order, distributeOr, completeAction |
| `SpecParser.swift` | SwiftSyntax → DSL | parseStateExpr, parseSpecClosure, enums |
| `StateGraph.swift` | BFS output | States + transitions |
| `TemporalExpr.swift` | Temporal AST | 5 cases |
| `SwiftSource.swift` | Swift → Swift | Round-trip for tests |
| `BFSCheckerSpec.swift` | Self-proof | TLAModelType, bfsChecker factory |
| `ModelMacro.swift` | @TLAModel | Compile-time check + emit runtime |
