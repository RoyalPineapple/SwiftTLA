# Symmetric Collections (formal-engine boundary)

New application models do not use `SymmetricCollectionVar`. Author them with
`#spec`, `Algorithm`, `SharedVar`, and typed `Function`, `SetExpr`, and
`Record` values. This document describes the retained formal-engine and parity
support for legacy symmetric-collection fixtures; it is not a second public
authoring language.

A symmetric collection models a finite group of members that are exchangeable
for a checked property. Equivalent symmetry evidence for the canonical
PlusCal-shaped collection vocabulary is required before this legacy boundary
can be removed.

## Compiler pipeline

SwiftTLA is a compile-time behavioral compiler. Swift types constrain the
model that the DSL can construct. `@TLAModel` and `@TLAActor` then parse the
DSL, check the model's global behavior during compilation, and generate an
executable state-machine or actor surface only after that check succeeds.

```text
Typed Swift DSL -> TLASpec -> CompiledSpecification -> generated runtime
       |                |                  |                       |
       |                |                  +-- failure: diagnostic  +-- state machine or actor
       |                +-- linked TLA+ bundle -> TLC oracle
       +-- types constrain variables, values, and collection operations
```

The generated runtime, the checker input, and the TLA+ export all come from
the same authored DSL. A model that fails macro-time checking does not produce
the generated executable surface.

## Runtime identity and model identity

The retained `SymmetricCollectionVar<Element, Value>` engine API requires
`Element: Identifiable`.
The generated runtime uses `IdentifiedModelCollection<Element, Value>`, keyed
by `Element.ID`, so an application can register and route actions to its real
members (for example, a `UUID`). The runtime population is not capped by the
verification scope.

The verification model does not contain those IDs. For each selected scope,
SwiftTLA creates a separate finite domain of opaque model values. The modeled
collection is a function from those values to `Value`. Those opaque values are
the only identities TLC permutes; a concrete `Element.ID` must never enter the
verification AST, `TLAValue`, generated TLA+ module, or TLC configuration.

For new models, represent the finite relation directly in the canonical
language—for example, a `SharedVar` initialized with a typed
`Function<Device, Record<...>>` or `SetExpr<Record<...>>`, and update it in a
labeled `Do` block. Keep identity distinctions in modeled state rather than
introducing a separate collection façade.

At runtime, the corresponding generated collection accepts `insert(_:)` and
the generated action accepts a concrete `Device.ID`. An unknown ID or an
action that is not enabled for the selected live entry reports a typed
`SymmetricCollectionRuntimeError`.

## DSL lowering and the symmetry contract

The legacy `SymmetricCollection` declaration creates a modeled function initialized uniformly over
its opaque member domain. `CollectionAction` lowers its closure to an
existential action over that function's domain. A read such as `phases[member]`
lowers to function application; `phases.update(member, to:)` lowers to the
corresponding function update. `allSatisfy` and `contains(where:)` quantify
over the same modeled domain.

### Predicate macro contract

`@TLAModel` and `@TLAActor` support both named and shorthand predicate
parameters: `phases.allSatisfy { phase in ... }`,
`phases.allSatisfy { $0 ... }`, `phases.contains(where: { phase in ... })`,
and `phases.contains(where: { $0 ... })`. The parser rewrites the closure
value to an application of the modeled function, then lowers `allSatisfy` to
`forAll` and `contains(where:)` to `exists` over that function's domain.

This applies in invariant bodies and in guards of ordinary `Action`s, so the
macro-time checker, generated specification, and direct DSL use retain the
same nontrivial quantified expression. An unsupported predicate body is a
source-anchored macro diagnostic; it is not discarded or silently replaced by
`true`.

### Selected-entry runtime contract

An ID-routed generated `CollectionAction` first finds the selected live
`Element.ID` entry. It evaluates the authored guard against that entry and,
when enabled, applies the authored update to that one entry only. All peers
remain unchanged; an unknown ID or disabled selected entry raises
`SymmetricCollectionRuntimeError` without changing any live entry.

The corresponding verifier action existentially selects one opaque member and
lowers the update to one function `EXCEPT`, preserving every unselected model
entry. For an ordinary generated action whose guard uses a collection-wide
predicate, the runtime temporarily projects every live collection value onto
opaque existing or synthetic model keys, evaluates the complete authored
guard, then restores the bounded collection state before committing the
ordinary state transition. Thus `allSatisfy` and `contains(where:)` observe the
live collection rather than only the bounded verification population.

The `member` parameter is deliberately opaque. Within its original
`CollectionAction`, it may only select or update its owning collection.
These uses preserve the claim that permuting member names does not change the
meaning of the model.

Forbidden uses include observing or exporting identity: comparison or
ordering, string interpolation, persistence or returning/escaping the token,
capturing it, using the raw member domain, or selecting another collection with
the token. If a behavior needs such a distinction, represent it as member
state or model that collection without symmetry.

## Scope and proof boundary

`verificationScope` is a positive, explicit finite bound. For example,
`verificationScope: 4` checks exactly four exchangeable model members in that
run. It does not cap the number of concrete members in the runtime collection.

A successful fixed-scope check is evidence for that modeled scope only. It is
not proof for larger populations, arbitrary population sizes, or membership
churn that the model does not represent. Symmetry reduction can reduce a
finite state space; it does not turn a finite `N` into an unbounded proof.

Parametric verification is future work. A future locality-checked parametric
proof would be a separate verification technique and must not be inferred from
or reported as the result of this feature's finite symmetry check.

## Soundness and diagnostics

Symmetry is sound only when the checked behavior is identity-blind for every
member declared exchangeable. In particular, the initial values must be
uniform, modeled actions and properties must not distinguish the opaque member
identities, and each collection must own exactly its modeled variable.

The reduction canonicalizes complete states, not merely the top-level
collection function. Each permitted permutation is a bijective renaming of a
collection's opaque members everywhere they occur, including nested keys and
values. The checker keeps the deterministic minimum state encoding over those
renamings. Multiple symmetric collections have independent permutation groups;
their Cartesian product must fit the configured budget or validation fails.

The parser and macro report source-aware diagnostics for unsupported member
uses. Validation also rejects an empty or duplicate collection name, a
non-positive scope, invalid modeled ownership or domain, generated-symbol
collisions, and a permutation product above the configured budget. These
diagnostics name the collection and describe the corrective action; the checker
does not silently disable symmetry reduction.

## TLA+ and TLC oracle

For a symmetric collection, the compiled TLA+ bundle declares opaque member
constants, a generated domain such as `DevicesKeys`, and a symmetry operator
such as `SymmDevices == Permutations(DevicesKeys)`. Its root configuration
assigns the member constants to TLC model values and includes
`SYMMETRY SymmDevices`. Ordinary collections without a symmetric declaration
emit none of these artifacts.

TLC is the external oracle for this lowering. Use the checked-in
[temporal and symmetry conformance workflow](../.github/workflows/temporal-symmetry-conformance.yml)
for hosted evidence. The workflow provisions the pinned tools and retains the
bounded comparison artifacts for the selected scopes.

The symmetry gate and its TLC setup are broad validation commands. Do not run
them locally unless the user gives explicit authorization for the exact
command. Repository-safe local diagnostics remain limited to the focused modes
in `scripts/local-validation.sh`. The oracle evidence does not extend the proof
boundary.

## Reviewer checklist

- [ ] The collection has a positive, explicitly stated verification scope, and results repeat that finite scope.
- [ ] The review makes no claim that a fixed scope proves arbitrary `N`, larger populations, or unmodeled membership churn.
- [ ] Any mention of parametric proof labels it as future work, separate from finite symmetry reduction.
- [ ] Runtime storage and action routing use `Element.ID`; concrete IDs do not appear in model values, the verification AST, TLA+ output, or the TLC CFG.
- [ ] Each opaque member token is used only to read or update its own collection inside its original `CollectionAction`.
- [ ] The macro-supported `allSatisfy` and `contains(where:)` forms use either a named parameter or `$0`, lower to nontrivial `forAll`/`exists` predicates in invariants and ordinary action guards, and reject unsupported predicate bodies with an authored-source diagnostic rather than replacing them with `true`.
- [ ] An ID-routed collection action evaluates its guard and update against the selected live entry, changes only that `Element.ID` entry, and preserves peers; its verification counterpart existentially selects one opaque member and performs one `EXCEPT` update.
- [ ] Ordinary generated actions evaluate collection-wide predicate guards over the projected live collection and restore the bounded verification collection before committing ordinary state.
- [ ] Initial member values, actions, invariants, and properties are invariant under renaming exchangeable members; required distinctions are represented as state or use a non-symmetric collection.
- [ ] Validation failures are actionable, and a configured permutation-budget failure remains an error rather than falling back to unsound or unreduced behavior.
- [ ] Every permitted member permutation is a bijective renaming of the complete state, including nested keys and values; the checker retains the deterministic minimum encoding.
- [ ] Multiple symmetric collections use independent permutation groups, and their explicit product fits the configured budget.
- [ ] The generated TLA+ module and CFG contain model-value constants, the generated domain, `Permutations(...)`, and the matching `SYMMETRY` entry; the TLC oracle has been run for the intended scope.
- [ ] Generated state-machine or actor APIs are described as deriving after macro-time global behavioral verification, not as independent hand-written behavior.
