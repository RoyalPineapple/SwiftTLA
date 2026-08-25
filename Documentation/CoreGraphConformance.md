# Core graph conformance

Core graph conformance is a bounded, executable comparison between one
SwiftTLA BFS run and one TLC run. For each declared case, it compares the
canonical initial-state set, canonical state bindings, and complete labeled
transition multiset. It is stronger than matching a state count.

Published TLA+ semantics are authoritative. TLC is a pinned executable
reference; its source and tests are diagnostic evidence. SwiftTLA does not
claim a hidden checker or oracle.

The authority is the declared semantic source and retained hosted evidence,
not this document. GitHub Actions runs core conformance and support admission.
Local use is diagnostic-only: use the approved narrow validation wrapper, or
obtain explicit authorization for a broader command. Do not treat a local run
as admission evidence.

## What is pinned

`Verification/CoreConformance/toolchain.json` locks TLC v1.8.0, its source
commit and JAR digest, an architecture-specific Temurin 17 archive digest,
and the bridge class/source/binary digests. `cases.json` locks every case's
module, configuration, arguments, mappings, and upstream reference. Setup
fails closed when a required digest does not match.

The setup script can seed an exact, digest-matching artifact from
`Tools/TLCGraphBridge/.tool-cache`. That cache is a local convenience, not a
published artifact source. A fresh machine must obtain the exact locked files
or setup fails; it must not silently accept a changed upstream release asset.

## Evidence and diagnosis

The command writes fresh evidence under `.build/core-conformance-evidence`.
Each case retains the input identity, toolchain provenance, TLC JSONL stream,
canonical Swift and TLC runs, `core-decision.json`, and relevant TLC logs.
Checked-in baseline and control evidence lives under
`Verification/CoreConformance/baselines/` and
`Verification/CoreConformance/fixtures/`.

```text
swift-run.json + swift-run.graph/*.jsonl
tlc-run.json   + tlc-run.graph/*.jsonl
                 │
                 ▼
        exact canonical comparison
                 │
                 ▼
          core-decision.json
```

`core-decision.json` references each run and graph chunk by SHA-256. It also
records the run correlation, comparison categories, and difference digest.
The reader verifies the references, reconstructs both runs, repeats the exact
comparison, and verifies the recorded summary.

When a run fails, first inspect its `core-decision.json`, then the canonical
graphs and `logs/` in that case's evidence directory. A graph mismatch is
classified by relation (for example, an initial state, state binding, edge,
outcome, or mapping difference); do not reduce it to a count mismatch.

Counterexample traces have a different job. They explain an invariant or
other checker failure and may be replayed, but they are not proof that the
complete graph was explored. Complete-graph evidence comes from a successful,
exhaustive declared run and its bridge stream.

## Exact admission

`Verification/CoreConformance/support-surface.json` defines the finite
support claims evaluated by the gate. Each requested entry names its declared
cases. Admission requires complete current evidence and exact canonical graph
agreement for every named case.

A comparison mismatch retains its canonical runs, graph chunks, and command
record. The exact records reproduce the first difference. The gate
reports `.nonExactComparison` and blocks the requested entry.

The admission report is written to
`.build/core-support-gate/current-support-admission.json`; the immutable report and
case evidence for that invocation are retained at
`.build/core-support-gate/runs/<gate-run-id>/`. The report lists each entry,
its decision, reason codes, mandatory cases, evidence references, run
correlations, aggregate counts, and final exit class.

For a blocked entry, start with its reason codes and then inspect the retained
`core-decision.json` and graph records for the named case.

## Controls and limits

The gate has three shell outcomes. Exit `0` admits every requested support
entry. Exit `1` means a complete current evaluation blocked requested support.
Exit `2` means setup, execution, register, or evidence validation failed.

Required support claims use exit `0`.

This claim applies only to the finite cases named in `cases.json` and only to
the compared safety graph relation. It does not establish arbitrary bounds,
temporal properties, liveness, fairness, symmetry reduction, or unsupported
TLA+ constructs.
