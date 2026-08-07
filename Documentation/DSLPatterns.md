# SwiftTLA DSL Patterns

## Core rule: the DSL is the runtime

Every construct in the DSL serves **two roles**:
1. **TLA+ output** — `.tlaModule` renders it as valid TLA+/SANY source
2. **Runtime evaluation** — `Evaluator` interprets it against a `[String: TLAValue]` state

There is never a raw TLA+ string where a DSL construct could express the same thing.
The DSL body IS the implementation.

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

`[String: TLAValue]` is the core state representation but raw strings as keys
are fragile — a typo in a variable name is a silent bug. Every string key must
be derived from a typed source (`Var<T>.name`, `RecursiveFunc.name`, etc.),
never written as a bare string literal.

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
