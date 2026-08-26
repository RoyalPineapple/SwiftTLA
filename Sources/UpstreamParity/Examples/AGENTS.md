# Upstream example porting rules

This directory is a parity corpus. Each port must preserve the published
model's state space and labeled transition relation for its declared finite
configuration. It is not a place to invent a friendlier algorithm.

## Choose the authoring form from the upstream source

1. Read the upstream `.tla` and `.cfg` first.
2. If the source contains a PlusCal algorithm, port it with the scoped DSL:
   `#spec`, `Algorithm`, `Each`, and labeled `Do` blocks. Preserve the shared
   variables, process family, atomic labels, fairness, and formal properties.
3. If the source is direct TLA+, use the typed `#spec` vocabulary directly.
   Do not manufacture an `Algorithm` around it.
4. If an upstream construct is not supported, record the missing construct and
   stop. Do not emulate it with raw `TLAValue`, `StateExpr`, `ActionExpr`, or
   Swift control flow in a new port.

## Typed authoring rules

- Give every finite domain a named `CaseIterable` raw-value enum. The model
  macro derives its finite formal domain.
- Use `TLARecordSchema`, `Record<Schema>`, `TLAField`, and
  `Function<Domain, Range>` for structured state.
- Keep formal string names behind validated variables, fields, and domains.
  Do not expose string-keyed state or add new raw-map access.
- Keep all model logic in the specification. A generated actor, observable,
  test, or demo view may dispatch and render it, but may not reimplement a
  transition guard or state update.

## PlusCal-shaped translation

| Upstream form | SwiftTLA form |
|---|---|
| `variables` | `SharedVar` declarations inside `Algorithm` |
| `process (p \in S)` | `Each(S) { p in ... }` |
| labeled atomic code | `Do(Label.foo) { ... }` |
| `await P` | `When(P)` |
| `x := e` | `Assign(x, to: e)` |
| `if` / `either` | `If` / `Either` |
| `with` / choice | `With` / `Choose` |
| `Seq(S)` in a finite TLC model | `Sequences(of: S, lengths: 0...n)` |
| sorted `Seq(S)` in a finite TLC model | `SortedSequences(of: S, lengths: 0...n)` |
| `s[i]` / `Len(s)` | `sequence[index]` / `sequence.count` |
| `macro M(x) { ... }` / `M(v)` | `let m = Macro { (x: MacroParameter<Value>) in ... }` / `m(v)` inside `Do` |
| `goto` / `skip` / termination | `Goto` / `Skip` / `Stop` |
| process fairness | `Each(S, fairness: .weak)` or `.strong` |
| TLC `CONSTRAINT` bound | `StateConstraint(condition)` inside `Algorithm` |

`Do` is atomic. Every accepted `DoBuilder` statement becomes part of one
formal transition. Do not put an ordinary Swift side effect in a `Do` block.

## Compilation and validation

For an `@TLAModel` port, macro expansion compiles the parsed builder syntax and
records its `CompilationIdentity`. `makeMachine()` compiles `Self.spec` and
requires the same identity before it creates the generated machine.

After a port:

1. Add or preserve the `Example.Entry` metadata and declared finite outcome.
2. Compile the source model and run its focused bounded-exploration test.
3. For an `@TLAModel` port, exercise `makeMachine()` so its compilation-identity
   contract runs.
4. When a pinned reference fixture exists, declare or update its
   `FiniteGraphCase` and run the hosted finite-graph workflow.

## Names and source mapping

- Keep upstream variable names, module names, action labels, and invariant
  names unless the lowerer necessarily creates internal labels.
- File names are PascalCase. Entry IDs retain the upstream category/spec name.
- Record the upstream module and configuration in `Example.Entry`.
- A failure must report the next useful fact: the declaration, action,
  invariant, bound expression, or graph edge that differs.
