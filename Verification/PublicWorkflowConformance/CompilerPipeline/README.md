# Compiler-pipeline diagnostic cases

These files configure the bounded compiler-pipeline cases in
`../compiler-pipeline.json`. The manifest is the authority for case identity,
source and toolchain digests, finite bounds, and expected outcomes.

Each configuration has one purpose:

| File | Result that must remain visible |
|---|---|
| `counter.config.json` | The bounded counter produces `exact`. |
| `structural-invalid.config.json` | Duplicate variables produce `difference` before rendering. |
| `metadata-mismatch.config.json` | Changed generated metadata produces `difference`. |
| `unavailable.config.json` | An unavailable tool produces `unavailable`. |

The negative controls prove detection of their named condition. They do not
admit a language feature or general compiler behavior.

The checked-in Public Workflow GitHub workflow runs these cases. Every
`CompilerPipelineDiagnosticEvidenceV1` case record remains `diagnosticOnly`,
including a record retained by that workflow. The aggregate Public Workflow
report can identify the hosted run as `candidateEvidence` for the exact
fixture. That status does not change a case record or create a general support
claim.

If a case differs, read its retained artifacts and fix the named source,
configuration, bundle, or metadata relation. If a case is unavailable, restore
the required input or tool. Do not replace unavailable evidence with an older
result.
