# Core graph conformance

Core graph conformance is a bounded, executable comparison between one
SwiftTLA BFS run and one TLC run. For each declared case, it compares the
canonical initial-state set, canonical state bindings, and complete labeled
transition multiset. It is stronger than matching a state count.

Published TLA+ semantics are authoritative. TLC is a pinned executable
reference; its source and tests are diagnostic evidence. SwiftTLA does not
claim a hidden checker or oracle.

The authority is the declared semantic source and the evidence the command
writes, not this document.
Run the selected cases with:

```bash
make core-conformance
```

`make core-conformance` writes a fresh graph-comparison run. It does not by
itself admit a support claim. Use the core-support gate for that decision:

```sh
make core-support-gate
```

Run the local equivalent of the repository's required checks with:

```bash
make ci-local
```

`make ci-local` runs release-contract checks, tests, coverage, package and
macro builds, the core-conformance workflow contract, locked tool setup, core
conformance, and the core-support gate. SwiftLint is visible but advisory. The
commands are intended to run locally; hosted GitHub Actions availability is
not evidence of a passing check.

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
Each case retains the input identity, toolchain/provenance, TLC JSONL stream,
canonical Swift and TLC graphs, comparison result, and relevant TLC logs.
Checked-in baseline and control evidence lives under
`Verification/CoreConformance/baselines/` and
`Verification/CoreConformance/fixtures/`.

When a run fails, first inspect its `comparison.json`, then the canonical
graphs and `logs/` in that case's evidence directory. A graph mismatch is
classified by relation (for example, an initial state, state binding, edge,
outcome, or mapping difference); do not reduce it to a count mismatch.

Counterexample traces have a different job. They explain an invariant or
other checker failure and may be replayed, but they are not proof that the
complete graph was explored. Complete-graph evidence comes from a successful,
exhaustive declared run and its bridge stream.

## Divergences and support admission

`Verification/CoreConformance/divergences.json` is a permanent ledger. Record
every observed core disagreement with its original evidence, semantic
citation, pinned tool and runtime identity, bounded reproducer,
classification, disposition, regression case, normalized difference
fingerprint, and latest comparison. Do not delete a record when a defect is
fixed: preserve the regression and change its latest comparison to exact.

Choose one classification for each record:

| Classification | Use it when |
|---|---|
| `swiftTLADefect` | SwiftTLA behavior disagrees with the cited published TLA+ semantics. |
| `harnessOrConfigurationDefect` | The declared input, mapping, bridge, tool setup, or run configuration caused the disagreement. |
| `unsupportedConstruct` | The disagreement concerns a construct outside the current bounded support surface. |
| `publishedSemanticsAmbiguity` | The cited published material does not determine one clear result. |
| `suspectedTLCDefect` | The evidence indicates that the pinned TLC executable may disagree with the cited published semantics. |

Choose one disposition for the current state of that record:

| Disposition | Meaning |
|---|---|
| `open` | The disagreement is still being investigated. |
| `resolved` | The record stays in the ledger, and its latest comparison is exact. |
| `unsupported` | The behavior is deliberately outside the support claim, including a retained negative control. Its recorded difference and fingerprint must still reproduce. |
| `awaitingSemanticsReview` | A published-semantics decision is required before the record can be resolved. |
| `suspectedReferenceDefect` | The pinned TLC reference is suspected, but the record is not resolved. |

Only `resolved` is resolved to the gate. A linked record with any other
disposition prevents a requested support entry from being admitted. The gate
also requires each retained regression to have current evidence: an exact latest result for `resolved`, or
the recorded difference fingerprint for every other disposition. A
published-semantics ambiguity or suspected TLC defect must state the
published-semantics result separately from TLC output.

### Minimize and retain a divergence

Use this checklist when a declared core comparison differs:

1. Reduce it to the smallest practical finite case and record its explicit
   bounds and semantic citations.
2. Keep the original evidence, complete pinned input and toolchain identity,
   and the normalized difference fingerprint in `divergences.json`.
3. Add or keep a permanent regression case in `cases.json`. Its expected
   result must be the retained exact result or the retained difference.
4. Link the record from `support-surface.json`. Do not enlarge requested
   support merely because a related case runs.
5. Run `make core-support-gate`. Read its new report and the evidence stored
   under its matching gate-run ID; do not use evidence from another run.
6. When a defect is fixed, keep the ledger record and regression. Update its
   latest comparison to the new exact evidence, then set its disposition to
   `resolved`.

Do not delete a record to make a report pass. Do not change a difference
fingerprint without retaining evidence for the new difference.

`Verification/CoreConformance/support-surface.json` defines the only support
claims the gate can evaluate. The admission report is written to
`.build/core-support-gate/support-admission.json`; the immutable report and
case evidence for that invocation are retained at
`.build/core-support-gate/runs/<gate-run-id>/`. The report lists each support
entry, its decision, stable reason codes, mandatory cases, divergence IDs,
evidence references, run correlations, aggregate counts, and final exit
class.

For a report that blocks support, read the entry reason codes first. Then
inspect the referenced evidence and the case `comparison.json`. `missing`,
`stale`, `failing`, or `unexplained` counts mean the run is not admission
evidence. Fix the named prerequisite or evidence problem and rerun the gate;
do not reuse a report from another gate run.

## Controls and limits

The manifest includes expected negative controls: a same-count edge mismatch
and an invariant-violation/replay case. Their declared nonzero result is a
successful control outcome: it proves the gate rejects a false match. Any
unexpected mismatch, missing evidence, invalid stream, incomplete run, or
tool/input identity mismatch fails the gate.

The gate has three shell outcomes. Exit `0` admits every requested support
entry. Exit `1` means a complete current evaluation blocked requested support.
Exit `2` means setup, execution, register, or evidence validation failed.
Both nonzero outcomes are failures for a required support claim; neither is a
skip.

This claim applies only to the finite cases named in `cases.json` and only to
the compared safety graph relation. It does not establish arbitrary bounds,
temporal properties, liveness, fairness, symmetry reduction, or unsupported
TLA+ constructs.
