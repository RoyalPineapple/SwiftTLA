# Public workflow conformance

Public workflow conformance is a bounded, reproducible validation command. It
does not currently admit a general public-workflow support claim. A local run
is `diagnosticOnly`; the repository's GitHub workflow produces
`candidateEvidence` for the exact checks below. Neither label means that every
macro, generated model, package configuration, or Apple platform is supported.

Published TLA+ semantics remain authoritative. The parser, builder, runtime,
macro-generated machine, and platform builds are the subjects of these checks.
TLC and Java are explicitly not applicable to the parser-builder, generated,
annotation, and platform cases in this P4 runner; their placeholder identities
do not turn those checks into TLC conformance claims.

## Run validation

Use the checked-in
[GitHub workflow](../.github/workflows/public-workflow-conformance.yml) for the
aggregate validation. It provisions the pinned tools and retains the correlated
evidence artifact.

The aggregate public-workflow gate is a broad validation command. Do not run it
locally unless the user gives explicit authorization for the exact command.
Repository-safe local diagnostics remain limited to the focused modes in
`scripts/local-validation.sh`.

Only the GitHub workflow selects hosted-candidate mode. That mode changes the
aggregate report from `diagnosticOnly` to `candidateEvidence`; it does not claim
independent attestation or broader admission. Setting GitHub-looking environment
variables on a local run does not select hosted-candidate mode.

The command uses `xcodebuild` for the root public library, annotation, and
declared macOS-platform
checks. It validates the project-relative paths and SHA-256 identities in the
[runner register](../Verification/PublicWorkflowConformance/runner.json),
[annotation inventory](../Tests/Fixtures/PublicWorkflowConformance/inventory.json),
parser-builder manifests, generated-behavior manifest, package inputs,
toolchain record, commands, configurations, observations, and retained logs.
Missing or changed bytes do not silently reuse an older result.

## Exact checked scope

| Area | Positive check | Permanent controls and bound |
|---|---|---|
| Parser and builder | The same bounded counter produces exact initial/reachable states, labeled/enabled transitions, properties, deadlocks, failures, and diagnostics. | One integer variable and two reachable states. A source/configuration mismatch must remain a `difference`. |
| Generated behavior | The builder and generated counter agree on the initial state, two reachable states, the `advance` transition, `withinBounds`, and the terminal deadlock. | `maxStates: 2`. Intentional transition mismatch, evaluation failure, and evaluation unavailability must remain visible differences. |
| Annotations | Valid and invalid external packages for `@TLAModel`, `@TLAActor`, and `@TLAObservable` run with their declared Xcode schemes. | Each valid package must build; each invalid package must fail with the declared `withinBounds` invariant diagnostic. These fixtures do not prove every model accepted by those annotations. |
| Public library platform | The root `SwiftTLA` product builds through the `SwiftTLA-Package` scheme on macOS. | The recorded command builds only the public `SwiftTLA` library target for the declared macOS destination. The root package declares macOS support, so this check makes no iOS, Mac Catalyst, tvOS, watchOS, demo, capture, playback, or writer claim. A failed destination is a difference; a missing tool or destination is unavailable. Success applies only to the recorded package tree, command, Xcode toolchain, SDK, and destination. |

The mismatch and failure cases prove that the runner detects those declared
conditions. They are not supported behaviors and do not enlarge the positive
scope.

Generated behavior uses the application-facing typed surface. A fixture reads
generated `State` and `TransitionResult` values. Formal tooling uses the
compiler-owned state boundary.

### Annotation availability

| Annotation | P4 disposition |
|---|---|
| `@TLAModel` | Release-facing fixture pair exists; current local evidence is diagnostic and hosted evidence is a candidate for the exact fixture only. |
| `@TLAActor` | Same bounded fixture disposition; the actor runtime proof is also diagnostic. |
| `@TLAObservable` | Same bounded fixture disposition. |

There are currently no report-derived, generally admitted P4 entries to list in
public claims. Public material may describe the exact validation cases above,
but must not convert `diagnosticOnly` or `candidateEvidence` into “supported.”

## Reports and retained evidence

An explicitly authorized local run writes a hash-verified reference to the current report at:

```text
.build/public-workflow-support-gate/current-support-admission.json
```

The reference contains the immutable report path and SHA-256. The report and
the evidence for one immutable run are below:

```text
.build/public-workflow-support-gate/runs/<run-id>/
```

Despite its filename, the current `PublicWorkflowDiagnosticReport` records
`claimStatus` as `diagnosticOnly` or `candidateEvidence`; consumers must read
that field and `authority`, not infer admission from the path or an exit code.
Each check references its retained manifests, observations, results, stdout,
stderr, platform context, and platform result files by path and digest.

The [GitHub workflow](../.github/workflows/public-workflow-conformance.yml)
runs the aggregate command on `macos-15`, retains its output under
`.build/public-workflow-ci/<run-id>-<attempt>/`, and uploads the artifact named
`public-workflow-evidence-<run-id>`. The workflow is the operational hosted
validation path. Local output remains useful for diagnosis and release
preparation, but is not relabeled as hosted evidence.

## Exit status

| Exit | Report result | Meaning |
|---:|---|---|
| `0` | `success` | Every declared positive and negative control produced its expected bounded result. This is still diagnostic or hosted-candidate evidence. |
| `1` | `blocked` | Evaluation completed, but at least one declared result differed from its expectation. Read the failed check and retained artifacts. |
| `2` | `unavailable` | A register, pinned input, fixture, tool, safe evaluation, package, SDK, destination, or required artifact was unavailable or invalid. |

The command writes a report for safe setup and execution failures. It does not
translate exit `1` or `2` into success.

## Limits

This runner does not claim arbitrary bounds, arbitrary generated machines,
all macro inputs, semantic equivalence to TLC, every Xcode version, simulator
behavior, device behavior, runtime UI behavior, or every package consumer. Its
Apple matrix is build/test evidence only for the exact named destinations and
the pinned nested package tree.

P1 core graph support and P3 temporal/symmetry support keep separate registers,
reports, and authority boundaries. See [core support](CoreSupport.md) and
[temporal and symmetry conformance](TemporalSymmetryConformance.md).
