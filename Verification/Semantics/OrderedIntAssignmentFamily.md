# Ordered Int expressions and assignment outcomes

Status: integrated candidate on admitted `c582b814`. Local checks passed; new
hosted admission is pending. No complete accepted-program rule is claimed.

The pinned `--nofp` batch proved all twenty ordered rows and 1,554 obligations.
All 153 proof snapshots and both runner hashes matched the checked inputs.
The combined safety-wrapper check passed 183 tests across all 22 current
regression owners, including both overlapping-target arguments. Static checks
passed family isolation and all five pinned-download controls. These results
are local diagnostics; they do not replace new hosted admission.

This transports the assignment/expression connection from `37e19b06` and
`16244a79`, preserving the current Boolean, sequence, definition, renderer,
native-helper and pinned-tool repairs. Later lexical/capture work is separate.

`PendingWriteOutcomeRule` defines source write constraints separately from the
generated compatible-write merge. `PendingFrameOutcomeRule` reuses that rule
with the prior state's framed value. The complete-state materialization and
frame observations keep their previous meanings.

`AssignmentActionRule` evaluates its child before checking an inherited write.
A child failure retains its payload and has no successor. Conflicting successful
writes disable the assignment without creating an evaluation failure. Its source
observation constrains the target, every inherited write and every remaining
state field; the generated observation materializes the compatible update.

`AssignmentTreeOutcomeComposition` supplies assignment and frame leaves to the
existing finite action-tree rule. Other leaf/condition agreement and the
remaining conjunction-left shape premises stay explicit.
`OrderedIntAssignmentComposition` supplies typed assignment child outcomes from
the independent literal/read/checked-add expression histories. It assumes the
expression plan, Int projection, value/failure domains and `NoFailure` separation.
The shared prefix-induction lemma replaces the expression-local induction proof;
it does not change expression evaluation or arithmetic guard semantics.

The actual lowerer and both output links remain in their canonical owners:
`OrderedAssignmentLoweringTests`, `NativeExecutionBoundaryTests` and
`ConjunctionFailureSelectionTests`. The existing nested-arithmetic Swift mutation
already checks operand order and is reused. The conjunction owner retains its
original nonconflicting case and adds an overlapping-target arm. Its new actual
Swift mutation returns early at the second fallible write when an update is
already pending. Existing TLA failure-selection mutations remain in that owner.
No production Swift code, test seam, model or fixture is added.

These checks do not prove parser/macro/builder extraction, normalization,
postorder-plan correspondence, capture/type/layout identities, checker soundness,
native operation/merge kernels, initialization, program-counter control or
selected checking outcomes. Those SwiftTLA-owned boundaries remain open or
separately tested. The theorem preserves one selected failure, not every branch's
failure set. No accepted DSL form is restricted. Fixtures remain regressions.

The ordinary rule-before-composition batch owns this extension. It adds no
`proof_family` value or diagnostic-dispatch route. The current Boolean/sequence
rules and original family revisions stay unchanged. Admission requires new
ordinary CI and full unfiltered validation on one frozen integrated revision.
