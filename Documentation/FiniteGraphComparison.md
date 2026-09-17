# Finite graph comparison

Finite graph comparison compares native exploration with separate TLC runs of
the pinned upstream model and the generated model. Each case resolves one source model and declares its TLC bundle
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

The pinned upstream TLA+ fixture runs as an independent reference.
The runner also explores the DSL-generated TLA+ and retains its complete graph in `generated/tlc-graph.jsonl`.
Both TLC graphs must match native execution.

The runner can combine graph capture with a batch of checks that native execution reports as satisfied.
Only a completed TLC graph run can supply both graph evidence and satisfied results for that batch.
A property violation, unsupported formula, or temporal tautology does not establish complete graph capture.
The runner can collect the complete graph with checks disabled, then run the checks separately.
This changes only check selection, not model behavior or the required outcomes.

A successful batch supplies results only for its selected checks.
Other checks run separately against the same module and exploration configuration.
An unavailable batch supplies no property verdicts.
The runner isolates its checks to identify unavailable results and differences.
Each counterexample must belong to the shared complete graph.

Reports in `properties/<name>/` and `deadlock/` retain verdicts and counterexamples.
Matching violations can establish agreement without hiding other failures.
An unavailable check cannot pass, including when the scenario expects a violation.
Incomplete graphs, timeouts, malformed evidence, and unsupported checks remain failures.

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

The workflow builds one release executable for that commit.
Before distribution, it checks every case selector, the `all` selector, and rejection of an unknown selector without invoking TLC.
The manifest determines one job per graph case.
A separate job runs the model-owned scenarios.
Each graph job retains its complete comparison independently of the other jobs.

```sh
gh workflow run finite-graph.yml \
  --ref main \
  -f swift_tla_sha="$swift_tla_sha"
```

The workflow artifact contains both graph streams, the TLC process output, and
`comparison.json` and `native-checks.json`. Inspect graph differences and every native check when a case differs.

The combined job retains available evidence even after a failure.
Artifact publication alone does not establish success.
The final gate requires successful jobs and exact, complete comparisons for every declared graph case.

## Hosted result

The scenario runner accepts two resource limits through environment variables:

- `SWIFTTLA_SCENARIO_MAXIMUM_STATES`: a positive integer, with a default of 1,000 states.
- `SWIFTTLA_SCENARIO_TIMEOUT_SECONDS`: a positive finite number, with a default of 120 seconds per TLC invocation.

The hosted workflow supplies 2,000,000 states and 600 seconds for model-owned scenarios.
Independent upstream cases declare their limits in `cases.json`.
These limits do not change model parameters, transitions, or selected properties.
An incomplete graph or timeout remains a validation failure.

The `finite-graph.yml` workflow accepts `swift_tla_sha`. It uses that exact
commit and names the artifact with the resolved commit, run ID, and run
attempt.

| Exit | Result |
| ---: | --- |
| `0` | Every declared graph and all property/deadlock verdicts match. |
| `1` | A complete graph or a property/deadlock verdict differs. |
| `2` | At least one case cannot produce a complete comparison. |
