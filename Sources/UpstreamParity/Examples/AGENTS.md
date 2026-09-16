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
4. If an upstream construct is unsupported, implement its compiler support before declaring the port complete.
   Do not replace it with raw `TLAValue`, `StateExpr`, `ActionExpr`, or Swift control flow.
   Do not simplify the upstream algorithm or disable its checks.

## Typed authoring rules

- Use model-owned finite domains and typed scenario bindings.
- Use ordinary Swift structs, enums, arrays, and sets for model values.
- Generate formal projections from the resolved types instead of declaring parallel record schemas.
- Retain `Function<Domain, Range>` only for total finite functions, not as a replacement for ordinary dictionaries.
- Use typed field and indexed assignments for supported writable locations.
- Preserve resolved types, declaration identities, and source locations until backend emission.
- Keep formal string names behind validated variables, fields, and domains.
  Do not expose string-keyed state or add new raw-map access.
- Keep all model logic in the specification.
  A generated actor, observable, test, or demo view can dispatch actions and render state.
  Do not reimplement transition guards or updates in these consumers.

## PlusCal-shaped translation

| Upstream form | SwiftTLA form |
|---|---|
| `variables` | `scope.sharedVar` declarations inside scoped `Algorithm` |
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

The resolved typed model supplies generated native Swift and equivalent formal exports.
Application execution and native checking share the generated transitions.
`makeMachine()` evaluates generated initial state code without runtime compilation or an interpreter fallback.

For each port:

1. Read the pinned family inventory in `Verification/UpstreamExamples/inventory.json`.
2. Preserve every applicable upstream module, variant, configuration, property, and expected outcome.
3. Declare typed validation scenarios with the model.
4. Derive implementation registration from those scenarios, not from duplicate scenario bindings.
5. Run focused local diagnostics only through `scripts/local-validation.sh`, as specified by the repository safety rules.
6. Compare complete native initial states and labeled graphs against independently pinned upstream inputs through hosted TLC.
7. Compare all declared property outcomes, including deadlocks, termination, fairness, and temporal properties.
8. Retain actionable counterexample traces and all differences.
9. Remove replaced application APIs, manual schemas, and stale generated evidence.

Expected failures change the validation verdict, not model behavior or check selection.
Missing, unsupported, timed-out, malformed, or truncated results do not establish equivalence.
State counts alone do not establish equivalence.
Hosted checks remain the admission authority for the exact pushed SHA.
Do not run TLC locally.

## Names and source mapping

- Keep upstream variable names, module names, action labels, and invariant
  names unless the lowerer necessarily creates internal labels.
- File names are PascalCase. Fixture names retain the upstream model name.
- Record the upstream module and configuration in `Verification/FiniteGraph/cases.json`.
- A failure must report the next useful fact: the declaration, action,
  invariant, bound expression, or graph edge that differs.
