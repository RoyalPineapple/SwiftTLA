# Temporal and symmetry conformance

This check compares bounded SwiftTLA behavior with TLC behavior. Each case in `cases.json` must complete and match.

The hosted workflow runs:

```sh
./scripts/run_temporal_symmetry_conformance.sh --output .build/temporal-symmetry-conformance
```

The command writes evidence to `.build/temporal-symmetry-conformance`.

## Result

| Exit | Meaning |
|---:|---|
| `0` | All declared cases match. |
| `1` | SwiftTLA and TLC differ. |
| `2` | A case did not complete. |

The workflow fails for exits `1` and `2`.

## Temporal cases

SwiftTLA compiles a typed model from the case's
`TemporalCaseConfiguration`. TLC runs the pinned `TemporalMatrix.tla` source
declared by that case, with a configuration rendered from the same property and
fairness values.

Each temporal case declares one `exploration` value. It disables symmetry and
sets the maximum stored-state count. Requiring more states than that limit makes
the case incomplete.

The comparison checks these facts:

- Both tools evaluated the property.
- Both tools reported the same property result.
- The initial states match.
- The complete state sets match.
- The labeled edge multisets match.
- Each reported lasso belongs to its retained graph.

Each temporal case has a complete-graph check and a property check. The
complete-graph check uses `SPECIFICATION Spec` and must report exhaustive
completion. The property check uses the case's property and fairness
configuration and may report a lasso violation. A violation launches trace
capture. Comparison uses the complete graph for state and edge equality and the
property check for the temporal outcome.

## Symmetry cases

Each case uses one compiled specification. SwiftTLA renders both TLC configurations from that specification.

Each case retains four graphs:

1. The unreduced SwiftTLA graph.
2. The reduced SwiftTLA graph.
3. The unreduced TLC graph.
4. The reduced TLC graph.

The compiled runtime produces both SwiftTLA graphs. The orbit checker derives the permutation orbits independently from the unreduced graph.

The comparison checks these facts:

- The unreduced state sets match.
- Each reduced graph contains one state from each orbit.
- Each unreduced transition maps to the quotient relation.
- Each reduced transition belongs to the quotient relation.
- The applicable invariant and deadlock results match.

The declared cases cover one binary symmetric collection at scopes 2 through 5.
Each symmetry case declares `rawExploration` with symmetry disabled and
`reducedExploration` with symmetry enabled and a maximum permutation count.
The checker passes those values unchanged to their respective Swift runs.

## Evidence

Each successful temporal case directory contains `swift-graph.jsonl`,
`tlc-graph.jsonl`, `temporal-comparison.json`, TLC output, and command data.
Failures and unavailable comparisons also retain diagnostics. Violations retain
a counterexample when TLC produces one.
The `complete-graph-pass` directory contains the exhaustive TLC invocation.
The case root contains the property invocation.

Read the case directory when a command reports exit `1` or `2`. The retained files identify the first incomplete or different result.
