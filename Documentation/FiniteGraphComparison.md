# Finite graph comparison

Finite graph comparison compares one bounded SwiftTLA exploration with one
pinned TLC run. Each case resolves one source model and declares its TLC bundle
and maximum state count. Each completed graph supplies its observable states
and labeled actions.

```text
Generated Swift machine → ReachabilityGraph → NativeModelRun ─┐
                                                            ├→ GraphComparison + check results
pinned TLC bundle → TLCGraphReader → GraphRun ────────────────┘
```

## Exact relation

`GraphComparison` compares these records:

- observable variable and action names.
- initial states.
- complete states.
- labeled edges.
- exploration outcome.

Both graph runs must report complete exploration. A different record produces
one structured `GraphDifference`.

Native export retains every declared invariant, refinement, and temporal result,
plus the requested deadlock check. Each failed check owns a validated canonical
counterexample. `native-checks.json` preserves all results; it does not select
only the first failure. The runner validates that the native result names and
requested deadlock check exactly cover the rendered model's declarations.

The pinned upstream TLA+ fixture still runs as an independent reference, and its
complete graph must match native execution. The runner separately explores the
DSL-generated TLA+ with property and deadlock checks disabled, retaining that
complete graph in `generated/tlc-graph.jsonl`. This graph must also match native
execution. Each declared property and requested deadlock check then runs independently,
sharing that captured graph. Reports in `properties/<name>/` and `deadlock/`
compare both verdicts and retain their counterexamples. Matching violations can
establish agreement; a violation need not hide other checks or stop validation.
A check that cannot finish or produces an unavailable result cannot pass, and
does not skip subsequent checks.

The root `comparison.json` records upstream and generated graph differences and
every check's status. An incomplete upstream reference run remains a failure.
These comparisons cover the declared finite configurations, not the full upstream
corpus or a universal proof of correctness.

## TLC boundary

[`Verification/FiniteGraph/cases.json`](../Verification/FiniteGraph/cases.json)
declares each finite case. The toolchain lock declares the TLC source commit,
JAR digest, Java archive, and graph bridge digests.

`TLCProcessAdapter` validates and stages the declared bundle. `TLCGraphReader`
decodes TLC graph events into `GraphRun`. TLC is the independent
bounded oracle for the declared case.

## Run the hosted comparison

The hosted workflow runs the complete declared case set for a requested
SwiftTLA commit.

```sh
gh workflow run finite-graph.yml \
  --ref main \
  -f swift_tla_sha="$swift_tla_sha"
```

The workflow artifact contains both graph streams, the TLC process output, and
`comparison.json` and `native-checks.json`. Inspect graph differences and every native check when a case differs.

## Hosted result

The `finite-graph.yml` workflow accepts `swift_tla_sha`. It uses that exact
commit and names the artifact with the resolved commit, run ID, and run
attempt.

| Exit | Result |
| ---: | --- |
| `0` | Every declared graph and all property/deadlock verdicts match. |
| `1` | A complete graph or a property/deadlock verdict differs. |
| `2` | At least one case cannot produce a complete comparison. |
