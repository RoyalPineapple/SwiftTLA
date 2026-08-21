# Temporal and symmetry conformance

Temporal and symmetry conformance is a bounded evidence process. It does not
prove all temporal or symmetry behavior in SwiftTLA.

Published TLA+ semantics are authoritative. TLC is a pinned executable
reference. TLC source and tests are white-box diagnostic evidence. They do
not define a hidden oracle.

## Run the hosted gate

GitHub Actions validates the checked-in registers, then creates a current core
admission and a current P3 run. Local broad gate execution requires explicit
authorization and is diagnostic-only. The latest report is:

```text
.build/temporal-symmetry-support-gate/support-admission.json
```

The immutable P3 artifacts are under:

```text
.build/temporal-symmetry-support-gate/runs/<p3-gate-run-id>/
```

Do not use an old report as current evidence. Each report binds its cases,
comparison artifacts, core admission, digests, and run IDs to one P3 run.

## Read the result

The report has one entry for every support-surface entry. An entry is
`admitted`, `blocked`, or `unsupported`.

| Exit | Meaning | Action |
|---:|---|---|
| `0` | Every requested entry is admitted. | Retain the report with the change evidence. |
| `1` | A complete evaluation blocks a requested entry. | Read `reasonCodes` and resolve the reported mismatch. |
| `2` | The evaluation is unavailable or unsafe. | Restore the missing, stale, partial, foreign, or invalid evidence. |

The hosted workflow preserves all three exit values.
An unavailable result never becomes a passing result.

The report can admit only a requested entry with current, complete, exact
evidence. A visible `unsupported` entry does not establish support for that
behavior.

## Declared boundaries

The source of truth is the following register set:

- `Verification/TemporalSymmetryConformance/cases.json`
- `Verification/TemporalSymmetryConformance/support-surface.json`
- `Verification/TemporalSymmetryConformance/baselines/manifest.json`

Requested temporal entries use the three-state `TemporalMatrix` fixture. They
cover `AlwaysP`, `EventuallyP`, `AlwaysEventuallyP`, `EventuallyAlwaysP`, and
`LeadsToPQ` with the declared no-fairness, weak-fairness, or strong-fairness
settings. The exact property, actions, stuttering rule, and finite bounds are
in the register.

Requested symmetry entries use one binary-valued `SymmetricCollection` with
opaque members at exact scopes 2, 3, and 4. Each scope has a separate entry.

The following controls are explicitly unsupported:

- Symmetry scope 5 and larger scopes.
- Temporal properties evaluated through symmetry reduction.
- Multiple collections.
- Direct `Symmetry` declarations.
- Symmetry over nested member-bearing values.

These controls make the boundary visible. They do not establish support.

## Temporal evidence

SwiftTLA searches the complete finite graph for a reachable fair lasso. It
adds an implicit stutter behavior at each reachable state. Fairness uses
non-stuttering named-action occurrences and their enabledness.

The retained temporal comparison records the property, fairness, initial
states, enabledness, fair and rejected recurrent components, outcome,
diagnostic, and applicable lasso or trace reference. A Boolean result alone
cannot admit a claim.

`AlwaysP` uses two TLC passes. The property pass retains the TLC property
outcome. The separate complete-graph pass uses the declared graph
configuration and a different run ID. The separate pass is required because a
property run can stop after a violation and cannot establish the complete
graph by itself.

Both passes use the same pinned module, arguments, TLC identity, Java
identity, and bridge identity. The gate rejects a missing pass, reused run ID,
or mismatched input.

## Symmetry evidence

Each symmetry case retains four explorations:

1. SwiftTLA without reduction.
2. SwiftTLA with the declared reduction.
3. TLC without `SYMMETRY`.
4. TLC with the matching `SYMMETRY` configuration.

The orbit adapter applies the declared permutation group to canonical raw
states. It records each complete orbit, its semantic representative, both
executable representatives, raw transition witnesses, and the derived labeled
quotient transitions.

The gate requires complete raw state and transition coverage. It also requires
both reduced graphs to equal the derived quotient relation. State counts alone
cannot establish symmetry equivalence.

## Pins and bridge changes

Each case pins the TLC version and commit, JAR digest, Java distribution and
archive digest, source input, configuration, arguments, and graph bridge.
The bridge pin contains the `LosslessStateWriter` class plus source and binary
digests.

When the bridge changes, update the declared source and binary pins together.
Then create fresh P3 evidence. Do not mix evidence from the old bridge with
evidence from the new bridge. A digest mismatch makes the evaluation
unavailable.

## Diagnose a block

1. Read `support-admission.json` and find the blocked requested entry.
2. Read its `reasonCodes`, case IDs, correlations, and evidence references.
3. Inspect the matching directory under `runs/<p3-gate-run-id>/`.
4. For temporal cases, inspect the property result, enabledness, lasso, trace,
   graph events, and diagnostics.
5. For symmetry cases, inspect raw and reduced graphs, orbit evidence,
   quotient evidence, and configuration records.
6. Correct the model, compiler, or declared formal bundle, then run the
   release check again.

A mismatch blocks the claim. Its retained canonical graphs and first exact
difference identify the correction.
