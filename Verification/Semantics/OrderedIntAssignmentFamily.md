# Ordered Int expressions and assignment outcomes

Status: candidate based on admitted `2f0098a`.
Hosted admission for these changes is pending.
No complete accepted-program rule is claimed.

The current pinned `--nofp` batch proved 26 ordered rows and 3,527 obligations.
All 158 proof snapshots and both runner hashes matched the current proof inputs.
The current safety-wrapper checks passed 537 tests across 48 selected suites.
Static checks passed family isolation and all five pinned-download controls.

## Current domain queries and initialization connection

`FiniteSetMembershipRule` separates mathematical domains from generated predicates that avoid enumeration.
Its range and eager-union rules preserve every member and the selected child failure payload.
Its `integerSet` rule supplies mathematical `Int` and an always-true membership predicate.
Finite postorder histories compose these constructors under explicit operand and leaf agreement.
The `integerSet` constructor has no child or supplied leaf-agreement premise.
`OrderedIntAssignmentComposition` connects their query results to the complete labeled assignment observation.

The existing lowerer and actual Swift/TLA+ owners retain their positive and rejecting controls.
Independent checks cover supported source operands, emitted range predicates, and the selected failure operands.
The initialization connection and declared-type filters appear in [InitializationFamily.md](InitializationFamily.md).
Source extraction, unsupported constructors, concrete traversal, and checker/kernel soundness remain open.
These local results do not establish hosted admission or universal preservation.

## Finite integer-domain equality

The source rule compares a finite integer domain with the complete mathematical interval.
The generated rule handles an empty domain first.
For a nonempty domain, it checks the last endpoint from the count and requires every key within the interval.
The proof uses the pinned standard-library finite-set theorems without expanding recursive cardinality definitions.
An internal endpoint overflow makes the query false; it does not create a model evaluation failure.
The parent rule preserves operand order and each genuine child failure payload.
The assignment connection supplies the resulting Boolean value or failure to the complete labeled observation.

The baseline ran the three existing equality cases with production code unchanged.
It recorded nine accepted corruptions across source, actual Swift, and actual TLA+ checks.
It also recorded four incorrect runtime outcomes across the native and compiled paths.
Wide equality raised an enumeration-capability error instead of returning false.
Range-first evaluation hid the genuine domain division failure behind that capability error.
The repaired cases pass, including all nine rejecting controls and both operand orders.
The interval is never materialized by this query.
The global enumeration guard remains unchanged.

The native output check covers integer-keyed dictionary state reads and the supported scalar or arithmetic bounds.
Arbitrary function-child outputs remain outside that check.
Resolution correspondence, Boolean-query initialization outputs, and checking-specific output links remain unproved.
Finite dictionary key/count projection, source extraction, type correspondence, and checker/kernel soundness remain explicit boundaries.
This rule does not complete the general equality or domain constructors.

## Original assignment connection

The original assignment connection used admitted `c582b814` as its base.
The results in this section describe that earlier stage.

That pinned `--nofp` batch proved all twenty ordered rows and 1,554 obligations.
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
