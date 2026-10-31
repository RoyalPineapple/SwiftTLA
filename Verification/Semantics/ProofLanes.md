# Proof development lanes

Hosted admission checks one frozen integrated revision. Development continues in separate worktrees while those checks run.
Family diagnostics give early feedback. They do not replace integrated admission or prove universal `#spec` fidelity.

## Ownership

| Lane | Branch and worktree | Owned changes |
| --- | --- | --- |
| Integration | `codex/proof-integration-lane`, worktree `proof-integration-lane/SwiftTLA` | CI routing, shared prerequisites, integrated revision, admission evidence |
| Critical connections | `codex/ordered-capture-rule`, worktree `ordered-initial-failure-record/SwiftTLA` | Ordered capture and binding connections, new mixed scoped-Int composition, `LexicalBindingTests.swift` |
| Independent Boolean family | `codex/proof-boolean-family`, worktree `proof-boolean-family/SwiftTLA` | Boolean expression rules and composition, `StraightLineRenderedActionCheck.swift`, `ShortCircuitFailureProofTests.swift` |

Worktree names refer to directories under `/Users/alex/.codex/worktrees/`.
The integration lane owns shared manifests and workflow files. Family branches own separate focused batch manifests and scope records.
The uncommitted user edit in `LanguageCompositionChecklist.md` remains separate from agent changes.

The critical lane owns `ScopedActionBindingComposition.tla`, `scoped-action-binding.batch`, and `ScopedActionBindingScope.md` for this batch.
The Boolean lane owns `BooleanExpressionConstructorRules.tla`, `BooleanExpressionComposition.tla`, `boolean-expression.batch`, and `BooleanExpressionFamily.md`.

The mixed-binding regression exposed a shared prerequisite: definition-root actions bypassed the existing failure-payload check.
The integration lane owns that repair on `codex/definition-payload-prerequisite` before either family is adopted.
The repair keeps the shared outcome schema unchanged. Family diagnostics can continue while the prerequisite checks run.
The regression remains in `LexicalBindingTests.swift`. Preserve one copy when the critical family is integrated.

## Stable base and interfaces

The admitted base for both families is `d0419d84501e7043b1f67a184740d81ceb2ee3c6`.
The Boolean branch starts directly at that base. The critical branch retains dependent preparation from that same base.
The unpublished critical stack is not an admitted base for the independent family.
The integration lane must preserve the separate native-helper binding repair before the next admission candidate.

The shared outcome schema remains frozen during each family batch.
These SHA-256 values identify the admitted definitions:

| File | SHA-256 |
| --- | --- |
| `ActionOutcomeInterface.tla` | `5f4ea93a8b3ca833e99f46b4ef5474eaf6845c99bc98c8b172694d7f1de0b994` |
| `IndexedHistoryRules.tla` | `6cba2afa391c95de54f0c790bb255e1072353e047c714ba39dc4781717e070a6` |
| `FrameActionRule.tla` | `5e046fd047994c438a9bf75d144db4d9b1fc2fb153afd8ba55847aae2142857e` |

The prepared critical stack adds general functional-history lemmas without changing the outcome schema.
The Boolean family must not depend on those unpublished additions.
If incompatible shared changes are necessary, treat them as dependencies. Integrate and admit the shared prerequisite first.

## Family deliverable

A ready family includes all of these links:

- Independent source and generated semantic rules, with a composition theorem.
- Connections to the real lowerer and both actual emitted outputs.
- Positive artifact checks and rejecting mutations at each claimed boundary.
- A scope record that lists remaining child, extraction, checker, kernel, and execution premises.

Keep each missing link open. Do not count a conditional composition theorem as a complete accepted-program theorem.
Keep selected-failure preservation distinct from complete branch-failure semantics.

## Focused family feedback

The existing `ci.yml` has a manual `proof_family` input:

| Family | Proof batch | Implementation and mutation owner |
| --- | --- | --- |
| `scoped-action-binding` | `scoped-action-binding.batch` | `LexicalBindingTests` |
| `boolean-expression` | `boolean-expression.batch` | `ShortCircuitFailureProofTests`, `BooleanBranchLoweringContractTests` |

The routing script accepts only these family names.
Each family dispatch runs pinned proofs and implementation checks as separate jobs.
Each dispatch retains the exact source SHA, input hashes, tool identity, logs, and run context.
Separate concurrency groups prevent family dispatches from cancelling admission checks.
The default `none` selection preserves the existing ordinary CI path.

1. Apply the same reviewed CI-routing commit to each family branch.
2. Prepare every proof, output-check, and mutation input, then complete the scoped review.
3. Commit and freeze the family revision before its hosted diagnostic dispatch.
4. Dispatch `ci.yml` with the family branch and its allowlisted `proof_family` value.
5. Record the exact run ID and source SHA before further branch edits.

The family batch file must exist on the dispatched branch.
Draft family diagnostics can run before the local validation slot becomes available.
Record each local check as passed, failed, or pending. A draft dispatch does not make the family ready for integration.
The integration lane controls diagnostic dispatches and retains their results.
Local heavy checks remain serialized through `scripts/local-validation.sh`.
Authorized direct TLAPS commands also use one coordinator-assigned local validation slot.

## One integration lane

1. Wait until both exact admission runs for the current integrated SHA finish.
2. Reconcile every required job, artifact, source pin, tool pin, input pin, and provenance record.
3. If a check fails, repair that failure before adopting another family.
4. If admission passes, integrate one ready family and preserve all existing repairs.
5. Resolve shared changes and run focused proofs, implementation checks, mutations, and related regressions.
6. Push one integrated SHA to the existing draft PR with an exact lease against its observed head.
7. Freeze that SHA for ordinary CI and full unfiltered validation.
8. Continue development in the other family worktree.

Do not overwrite intervening repairs with stale family tips.
Do not merge the draft PR into `main`, add reviewers, or change branch protection.
Report established translation boundaries and remaining premises, not proof counts or fixture counts.
