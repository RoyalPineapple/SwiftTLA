# Temporal and symmetry comparison

This hosted check compares bounded SwiftTLA behavior with pinned TLC behavior.
Each case declares its model, configuration, tool identity, and state limits.

## Temporal cases

The manifest supplies finite exploration bounds and fairness configurations.
Each configuration selects a typed DSL model. Native checking explores its
generated Swift transitions once, then validation checks every declared temporal
property. The native property results must cover exactly the compiler's declared
properties. There is no separate property registry or per-case stuttering flag.

TLC receives the TLA+ exported from that same model. Each comparison requires:

- matching property verdicts;
- complete graphs with identical initial states, states, and labeled edges;
- native and TLC counterexamples that start at initial states and follow their
  graph's transitions or implicit stuttering, as allowed by the generated
  specification's `[Next]_vars` semantics.

Safety counterexamples remain finite. Liveness counterexamples retain their
closed cycles. Counterexamples need not be identical between engines.

Each TLC property invocation captures graph events and any counterexample
together. If it stops before completing exploration, a separate property-free
pass captures the complete graph. Timeouts, malformed data, and incomplete
comparisons cannot succeed.

These finite configurations provide bounded validation, not a universal proof
of compiler correctness.

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
