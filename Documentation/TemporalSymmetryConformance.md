# Temporal and symmetry comparison

This hosted check compares bounded SwiftTLA behavior with pinned TLC behavior.
Each case declares its model, configuration, tool identity, and state limits.

## Temporal cases

SwiftTLA compiles the typed model from `TemporalCaseConfiguration`. TLC runs
the pinned `TemporalMatrix.tla` module with the same property and fairness
values.

The comparison requires these facts:

- both property runs produce the same result.
- both complete graphs have the same initial states.
- both complete graphs have the same states.
- both complete graphs have the same labeled edge multiplicities.
- each TLC lasso starts from a TLC initial state and follows ordered labeled
  edges in the TLC graph.
- each SwiftTLA lasso starts from a SwiftTLA initial state and follows ordered
  labeled edges in the SwiftTLA graph.

Each case uses one TLC run for the complete graph and one TLC run for the
property. A property violation also captures its trace.

## Symmetry cases

Each symmetry case uses one compiled specification. SwiftTLA renders the raw
and reduced TLC configurations from that compilation.

The case compares four graphs:

1. raw SwiftTLA graph.
2. reduced SwiftTLA graph.
3. raw TLC graph.
4. reduced TLC graph.

The orbit comparison validates each representative and quotient transition.
It also compares the raw SwiftTLA and TLC graphs exactly.

## Run the hosted comparison

```sh
gh workflow run temporal-symmetry-conformance.yml \
  --ref main \
  -f swift_tla_sha="$swift_tla_sha"
```

The workflow uses the requested commit. Its artifact name contains the
resolved commit, run ID, and run attempt.

| Exit | Result |
| ---: | --- |
| `0` | Every declared case matches. |
| `1` | At least one complete comparison differs. |
| `2` | At least one case cannot produce a complete comparison. |
