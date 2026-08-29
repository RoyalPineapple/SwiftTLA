# Finite graph comparison

Finite graph comparison compares one bounded SwiftTLA exploration with one
pinned TLC run. Each case resolves one source model and declares its TLC bundle
and maximum state count. Each completed graph supplies its observable states
and labeled actions.

```text
CompiledSpecification → SwiftGraphExporter → CompletedGraphRun ─┐
                                                                ├→ GraphComparison
pinned TLC bundle → TLCGraphReader → CompletedGraphRun ─────────┘
```

## Exact relation

`GraphComparison` compares these records:

- observable variable and action names.
- initial states.
- complete states.
- labeled edges with multiplicity.
- exploration outcome.

Both graph runs must report complete exploration. A different record produces
one structured `GraphDifference`.

## TLC boundary

[`Verification/FiniteGraph/cases.json`](../Verification/FiniteGraph/cases.json)
declares each finite case. The toolchain lock declares the TLC source commit,
JAR digest, Java archive, and graph bridge digests.

`TLCProcessAdapter` validates and stages the declared bundle. `TLCGraphReader`
decodes TLC graph events into `CompletedGraphRun`. TLC is the independent
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
`comparison.json`. Read the first `GraphDifference` when a case differs.

## Hosted result

The `finite-graph.yml` workflow accepts `swift_tla_sha`. It uses that exact
commit and names the artifact with the resolved commit, run ID, and run
attempt.

| Exit | Result |
| ---: | --- |
| `0` | Every declared graph matches exactly. |
| `1` | At least one complete graph differs. |
| `2` | At least one case cannot produce a complete comparison. |
