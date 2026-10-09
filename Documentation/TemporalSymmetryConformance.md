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

Each finite configuration captures its complete TLC graph once in a property-free
pass. All property comparisons reuse that graph, bound to its original module,
exploration bounds, arguments, environment, and tool pin. A failed shared capture
makes every property comparison unavailable; it is not retried per property.

Each TLC property invocation captures graph events and any counterexample
together. A completed property graph must agree with the shared graph. Timeouts,
malformed data, and incomplete comparisons cannot succeed.

These finite configurations provide bounded validation, not a universal proof
of compiler correctness.

Artifacts are grouped by finite model configuration. Each model directory owns
one `source-input`, one `swift-graph.jsonl`, and the independently captured
`complete-graph/tlc-graph.jsonl`. Property reports live below
`properties/<property-name>/`; their comparison JSON contains both verdicts and
any native or TLC counterexamples. Graphs are not copied into property folders.
Native graph artifacts remain available even if the TLC toolchain is unavailable.

## Symmetry cases

Each symmetry case uses one generated Swift machine. SwiftTLA renders raw and
reduced TLC configurations from the same resolved model.

The case retains three complete graphs: the unreduced generated Swift graph,
the raw TLC graph, and the symmetry-reduced TLC graph. It compares the two raw
graphs exactly, then validates the reduced TLC graph's representatives and
quotient transitions under the declared permutations. Native checking does
not construct a reduced graph or discard distinct states.

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
