# Independent validation pipeline

## Product and validation boundary

The SwiftTLA product owns the DSL, compiler, generated Swift machine, TLA+ export,
and native checker. An application can generate and check a machine without TLC,
the upstream examples, this pipeline, or GitHub Actions.

Validation infrastructure owns the `CanonicalUpstreamCorpus` and `UpstreamParity`
targets, `tlc-validate`, the TLC bridge, evidence caches, and hosted comparison.
It consumes generated machines, rendered TLA+ bundles, and native check events.
It does not define transitions, property predicates, or native check results.
SwiftTLA does not depend on these targets.

SwiftTLA exports the resolved check kinds and formal names as a
`RenderedCheckSelection`. The parity target alone combines those selections
with upstream reference declarations; no upstream reference bundle is
constructed by the product. The module bundle's public configuration-copy
operation preserves the original source, imports, and provenance.

Parity adapters read SwiftTLA's public rendered actions, check metadata, and
selected TLA+ bundles. The private configuration and compiler representation
remain inside SwiftTLA. The adapter may select and compare checks, but it may
not supply their model semantics.

The native checker and TLC use separate transition and property logic. Their
output adapters write the same evidence format for comparison. If the parity
jobs are removed, SwiftTLA can still generate and check machines. Only the
external agreement evidence is lost.

The generated Swift machine and generated TLA+ are checked independently.
The native checker reads only generated machine state and transitions. TLC reads
only the generated TLA+ bundle. Neither checker consumes the other's result.

The `dsl-native-parity` job compares their selected invariant, reachability,
temporal, refinement, and deadlock verdicts. When both finish exhaustive
exploration, it also compares the **complete** initial-state set, canonical
state set, and labeled edge set.

The comparator assigns one rank to each complete canonical state value. It
maps each edge to its source rank, action label, and destination rank. It
compares directed edge sets, so repeated identical edges count once. Edge
multiplicity is not part of graph equality. Equal counts or fingerprints alone
cannot establish parity.

A legitimate early counterexample can establish a selected check's verdict,
but does not claim complete graph parity or a verdict for a selected deadlock
check that TLC never reached. The reports retain that selection explicitly.
Missing, malformed, truncated, or unsupported evidence fails closed.

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

`Comparison replay diagnostic` can run a changed comparator against retained
native/TLC evidence without rerunning either checker. It records both source
and evidence SHAs and reports only on the recorded evidence; it is never an
admission check for the new source revision.

The former all-in-one finite-graph runner is removed. It must not be used to
credit a configuration. The separate temporal/symmetry conformance suite
continues to check its specialized contract, but is not a substitute for
the two parity jobs.

## Reachability evidence

The TLC adapter maps a finite TLC counterexample to a positive reachability
witness. It checks the complete path and requires an endpoint that satisfies
the native predicate. Different valid witnesses can establish the same outcome.
The complete graph comparison remains independent of property outcomes.

Reference checks require an explicit property-kind match. The adapter rejects
a witness at a constraint boundary because it cannot export that witness yet.
Hosted TLC evidence remains necessary for an independent agreement claim.
