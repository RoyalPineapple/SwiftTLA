# Independent validation pipeline

The generated Swift machine and generated TLA+ are checked independently.
The native checker reads only generated machine state and transitions. TLC reads
only the generated TLA+ bundle. Neither checker consumes the other's result.

The `dsl-native-parity` job compares their selected invariant, reachability,
temporal, refinement, and deadlock verdicts. When both finish exhaustive
exploration, it also compares the **complete** initial-state set, canonical
state set, and labeled edge set. The comparator sorts full state identities
and edges on disk; equal counts or fingerprints alone cannot establish parity.
A legitimate early counterexample can establish a selected check's verdict,
but does not claim complete graph parity. Missing, malformed, truncated, or
unsupported evidence fails closed.

The `upstream-parity` job is separate. It runs TLC on the DSL-generated TLA+
and the pinned upstream TLA+ fixture using the declared configuration. It
compares the same verdicts and, for exhaustive runs, the complete graphs.
Only this job stages upstream examples. It never invokes the native checker.

Both jobs retain their TLC inputs, stdout/stderr, process record, graph-event
stream, counterexample when present, native event stream when applicable, and
machine-readable comparison report. The generated-TLA oracle report records a
content identity covering the TLA+ modules, configuration, pinned toolchain,
bridge, and TLC arguments. This identity can distinguish unchanged oracle
inputs from a changed SwiftTLA revision.

[`Verification/FiniteGraph/cases.json`](../Verification/FiniteGraph/cases.json)
declares the currently represented upstream configurations. The generated
machine scenarios are declared in the SwiftTLA corpus. Both lists are
enumerated by the validator, so a newly declared case enters the appropriate
hosted matrix without a manually maintained workflow list.

## Hosted admission

The `Independent Validation Pipeline` workflow runs on pull requests. For a
focused diagnostic on an immutable candidate SHA:

```sh
gh workflow run validation-pipeline.yml \
  --ref codex/native-compiler \
  -f swift_tla_sha="$swift_tla_sha" \
  -f case_id="<case-id>"
```

Omit `case_id` to run the complete represented corpus. The final admission
job requires both independent parity matrices to pass. A focused diagnostic
is not complete corpus admission. Host-side evidence, not local test results,
is the authority for a candidate.

The former all-in-one finite-graph runner is removed. It must not be used to
credit a configuration. The separate temporal/symmetry conformance suite
continues to check its specialized contract, but is not a substitute for
the two parity jobs.
