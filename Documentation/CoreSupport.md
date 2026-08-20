# Core support

Core support is a bounded claim. The [support register](../Verification/CoreConformance/support-surface.json)
names each behavior, its
finite bounds, required cases, graph relation, requested status, and any
linked divergence. Behavior outside that register is not admitted.

Parser, macro, generated-machine, and public-library macOS checks
use a separate [public workflow conformance](PublicWorkflowConformance.md)
report. Its diagnostic or hosted-candidate result does not widen this core
support register.

## Temporal and symmetry admission boundary

Temporal and symmetry admission is a separate P3 boundary. It does not widen
the core finite-graph claim in this document.

The P3 source registers are under
`Verification/TemporalSymmetryConformance/`. A current P3 report can admit
only the exact requested temporal and symmetry entries named there. Its report
is at `.build/temporal-symmetry-support-gate/support-admission.json`.

GitHub Actions runs the required P3 qualification. Its report uses exit `0`
for admission, `1` for a complete blocking result, and `2` when evidence is
unavailable or unsafe. It always retains a report and never converts `1` or
`2` into success.

P3 currently evaluates only declared temporal matrix cases and one
binary-valued `SymmetricCollection` at exact scopes 2, 3, and 4. It explicitly
does not support larger scopes, combined temporal-plus-symmetry checking,
multiple collections, legacy symmetry declarations, or nested member-bearing
values. See [temporal and symmetry conformance](TemporalSymmetryConformance.md)
for the algorithms, evidence, and diagnosis steps.

## Current declared surface

The current requested entries are limited to these exact finite cases:

| Entry | Evidence | Bound |
|---|---|---|
| HourClock reachable state space | `hour-clock` | One integer variable over `1...12`; 12 states. |
| HourClock `HCnxt` transitions | `hour-clock` | One integer variable over `1...12`; 12 labeled transitions. |
| DieHard `TypeOK` safety | `die-hard-type-ok` | Two jug variables, bounded `0...5` and `0...3`; 16 states. |

The graph relation is `exactFiniteTLCGraphV1`: initial states, state bindings,
labeled transitions, and outcome must all agree for the declared case.

The altered HourClock edge and failing DieHard `NotSolved` invariant are
permanent negative controls. They are intentionally unsupported. All other
finite core behavior outside the two declared exact graphs is also explicitly
unsupported. This does not claim temporal, liveness, fairness, symmetry,
parser, annotation, generated-behavior, platform, or arbitrary-bound support.

## Read the gate

The hosted gate validates pinned prerequisites, creates one gate run ID, runs
the declared cases, and writes an admission report even when setup or
execution fails. Local broad gate execution requires explicit authorization.

The latest report is:

```text
.build/core-support-gate/support-admission.json
```

The immutable report, invocation record, and case evidence are retained at:

```text
.build/core-support-gate/runs/<gate-run-id>/
```

Do not use an older retained run as current support evidence. The gate binds
all case evidence to its one gate run ID and rejects missing, partial,
foreign, or digest-mismatched evidence.

Each report entry links its required case IDs, linked divergence IDs, retained
evidence references, and case-run correlations. Use those links to trace an
admission or block back to the declared support entry and evidence from the
same gate run.

## Read a report

`support-admission.json` is `CoreSupportAdmissionV1`. It contains:

- The gate run ID and the fixed authority statement.
- One decision for each support entry: `admitted`, `blocked`, or `unsupported`.
- Stable reason codes, required case IDs, linked divergence IDs, evidence
  references, and case-run correlations.
- Counts for admitted, blocked, unsupported, missing, stale, failing, and
  unexplained entries.
- The computed final exit class.

`admitted` means every required case was produced in this run, used the
declared inputs and toolchain, completed, and matched exactly with no
unresolved linked divergence. `unsupported` is visible scope, not a pass for
that behavior. `blocked` means a requested entry did not meet the admission
contract.

For a blocked entry, start with `reasonCodes`. Restore a missing prerequisite;
rerun incomplete or foreign evidence; correct an input or toolchain digest;
or investigate a non-exact or unexplained divergence. Then run the gate again.
Do not relabel a failure as admitted.

## Divergence records

The divergence ledger uses these classifications:

- `swiftTLADefect`: SwiftTLA disagrees with cited published TLA+ semantics.
- `harnessOrConfigurationDefect`: an input, mapping, bridge, tool setup, or
  run configuration caused the disagreement.
- `unsupportedConstruct`: the construct is outside the current support
  surface.
- `publishedSemanticsAmbiguity`: the cited published material does not give
  one clear result.
- `suspectedTLCDefect`: the pinned TLC executable may disagree with the cited
  published semantics.

The current disposition is `open`, `resolved`, `unsupported`,
`awaitingSemanticsReview`, or `suspectedReferenceDefect`. Only `resolved`
allows a linked divergence to stop blocking support, and it requires an exact
latest comparison. An `unsupported` record remains in the ledger as a
regression: its retained difference fingerprint must still match. See [core
graph conformance](CoreGraphConformance.md#divergences-and-support-admission)
for the complete retention checklist.

## Exit status

| Exit | Meaning | Maintainer action |
|---:|---|---|
| `0` | All requested entries were admitted from a valid current run. | Retain the report with the change evidence. |
| `1` | The evaluation completed, but requested support is blocked. | Read the report and fix the named semantic or evidence issue. |
| `2` | Setup, execution, register, or evidence validation failed. | Restore the prerequisite or valid inputs, then rerun. |

Published TLA+ semantics are authoritative. TLC is a pinned executable
reference. TLC source and tests are diagnostic evidence. SwiftTLA claims no
hidden checker or oracle.
