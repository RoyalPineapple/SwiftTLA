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

The older raw ports remain evidence while they are being migrated. Do not use
them as templates for new work.

## Typed authoring rules

- Give every finite domain a named `FiniteDomainKey` enum.
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
| `macro M(x) { ... }` / `M(v)` | `let m = Macro<Value> { x in ... }` / `m(v)` inside `Do` |
| `goto` / `skip` / termination | `Goto` / `Skip` / `Stop` |
| process fairness | `Each(S, fairness: .weak)` or `.strong` |

`Do` is atomic. Every accepted `DoBuilder` statement becomes part of one
formal transition. Do not put an ordinary Swift side effect in a `Do` block.

## Fidelity and validation

The macro parser and the constrained runtime builder independently construct
the formal model. Their semantic alpha-equivalence gate must pass before the
generated runtime is trusted. A structural fingerprint may speed diagnostics,
but it is not the authority.

After a port:

1. Add or preserve the `Example.Entry` metadata and expected finite outcome.
2. Run the focused `UpstreamParityTests` case. It must check the declared
   state count through the parser–builder fidelity gate.
3. Run the relevant TLC parity command when the upstream module and bounded
   configuration are available.
4. For a supported core case, refresh only the declared evidence through the
   core-conformance workflow. Do not edit pins by hand.

## Names and source mapping

- Keep upstream variable names, module names, action labels, and invariant
  names unless the lowerer necessarily creates internal labels.
- File names are PascalCase. Entry IDs retain the upstream category/spec name.
- Record the upstream module and configuration in `Example.Entry`.
- A failure must report the next useful fact: the declaration, action,
  invariant, bound expression, or graph edge that differs.
