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

SwiftTLA analyzes the complete bounded graph with `LivenessChecker`. TLC analyzes the rendered specification with the pinned toolchain.

The comparison checks these facts:

- Both tools evaluated the property.
- Both tools reported the same property result.
- The initial states match.
- The complete state sets match.
- The labeled edge multisets match.
- Each reported lasso belongs to its retained graph.

A property run can stop after a violation. Such a case uses a second TLC run to capture the complete graph.

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

## Evidence

Each temporal case directory contains `swift-graph.jsonl`, `tlc-graph.jsonl`,
`temporal-comparison.json`, TLC output, command data, and diagnostics.

Read the case directory when a command reports exit `1` or `2`. The retained files identify the first incomplete or different result.
