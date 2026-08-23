# Core support

Core support is a bounded claim. The [support register](../Verification/CoreConformance/support-surface.json)
names each behavior, its finite bounds, required cases, graph relation, and
requested status.

Parser, macro, generated-machine, and public-library macOS checks
use a separate [public workflow conformance](PublicWorkflowConformance.md)
report. Its diagnostic or hosted-candidate result does not widen this core
support register.

## Temporal and symmetry admission

Temporal and symmetry admission has a separate support register and report.
It does not widen the core finite-graph claim in this document.

The source registers are under `Verification/TemporalSymmetryConformance/`.
A current report can admit only the requested temporal and symmetry entries
named there. Its reference is at
`.build/temporal-symmetry-support-gate/current-support-admission.json`.

GitHub Actions runs the temporal and symmetry qualification. Its report uses
exit `0` for admission and exit `1` for a complete blocking result. Exit `2`
means that evidence is unavailable or unsafe. The gate always retains a
report and never converts exit `1` or `2` into success.

The gate evaluates only declared temporal matrix cases and one
binary-valued `SymmetricCollection` at exact scopes 2, 3, and 4. It explicitly
does not support larger scopes, combined temporal-plus-symmetry checking,
multiple collections, direct symmetry declarations, or nested member-bearing
values. See [temporal and symmetry conformance](TemporalSymmetryConformance.md)
for the algorithms, evidence, and diagnosis steps.

## Current declared surface

The current requested entries are limited to these exact finite cases:

| Entry | Evidence | Bound |
|---|---|---|
| HourClock reachable state space | `hour-clock` | One integer variable over `1...12`; 12 states. |
| HourClock `HCnxt` transitions | `hour-clock` | One integer variable over `1...12`; 12 labeled transitions. |
| DieHard `TypeOK` safety | `die-hard-type-ok` | Two jug variables, bounded `0...5` and `0...3`; 16 states. |

The graph relation is `exactFiniteTLCGraph`: initial states, state bindings,
labeled transitions, and outcome must all agree for the declared case.

The declared graph cases define the current core support surface. Temporal,
liveness, fairness, symmetry, parser, annotation, generated-behavior,
platform, and arbitrary-bound claims use their own declared evidence.

## Read the gate

The hosted gate validates pinned prerequisites, creates one gate run ID, runs
the declared cases, and writes an admission report even when setup or
execution fails. Local broad gate execution requires explicit authorization.

The current-report reference is:

```text
.build/core-support-gate/current-support-admission.json
```

It contains the immutable report path and SHA-256. The immutable report,
invocation record, and case evidence are retained at:

```text
.build/core-support-gate/runs/<gate-run-id>/
```

Each gate run binds its case evidence to one gate run ID.

Each report entry links its required case IDs, retained evidence references,
and case-run correlations.

## Read a report

The report resolved by `current-support-admission.json` is `CoreSupportAdmission`. It contains:

- The gate run ID and the fixed authority statement.
- One decision for each support entry: `admitted`, `blocked`, or `unsupported`.
- Stable reason codes, required case IDs, evidence references, and case-run
  correlations.
- Counts for admitted, blocked, unsupported, missing, stale, failing, and
  non-exact entries.
- The computed final exit class.

`admitted` means every required case was produced in this run, used the
declared inputs and toolchain, completed, and matched exactly. `unsupported`
marks a declared support boundary. `blocked` means a requested entry did not
meet the admission contract.

For a blocked entry, start with `reasonCodes`. Then inspect the referenced
case evidence and exact decision record.

## Exit status

| Exit | Meaning | Maintainer action |
|---:|---|---|
| `0` | All requested entries were admitted from a valid current run. | Retain the report with the change evidence. |
| `1` | The evaluation completed, but requested support is blocked. | Read the report and fix the named semantic or evidence issue. |
| `2` | Setup, execution, register, or evidence validation failed. | Restore the prerequisite or valid inputs, then rerun. |

Published TLA+ semantics are authoritative. TLC is a pinned executable
reference. TLC source and tests are diagnostic evidence. SwiftTLA claims no
hidden checker or oracle.
