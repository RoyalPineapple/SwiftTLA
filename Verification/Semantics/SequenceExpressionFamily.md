# Sequence append and concatenation

Status: uncommitted diagnostic draft. No hosted check qualifies this draft.

This family starts from admitted `d0419d84501e7043b1f67a184740d81ceb2ee3c6`.
It does not depend on the unpublished binding or ordered-capture stack.
The shared outcome, frame, and indexed-history modules remain unchanged.

## Conditional rules

The source rules construct sequences from their index maps.
The generated rules use `Append` and concatenation, with separate failure-selection expressions.
The rules retain every sequence index and the complete selected failure payload.
An earlier failed child suppresses the later child.
The negative theorems distinguish reversed concatenation and an omitted appended element.

The composition module has separate source and generated evaluators.
It uses the existing indexed-history existence and induction theorems.
Its plan permits arbitrary finite append and concatenation trees, including empty plans and repeated values.
Each append has a sequence child and an element child.
Element-child semantics remain explicit independent inputs, not another expression evaluator.
Sequence leaves and element children must agree for each context.
The theorem does not discharge those agreement premises.

The existing action-outcome interface receives a sequence result through an explicit projection.
The projection preserves the selected failure and supplies no update after failure.
This projection does not prove assignment targets, complete-state materialization, or action labels.

## Actual translation connections

`CompiledLowerer.scheduleSequenceBinary` already uses `SequenceExpressionLoweringContract.matches`.
That contract checks the constructor and the exact ordered scheduled operands.
The contract does not independently derive the scheduled operands from accepted syntax.
The added lowerer regression uses the actual accepted concatenation fixture.
It checks the two source-variable identities and rejects a changed constructor or reversed compiled operands.

`StraightLineRenderedActionCheck+Sequence.swift` extends the existing TLA output checker.
Its expected values derive from compiled constructors and resolved variable identities, not the renderer.
The initial slice contains pure append and concatenation trees with reads, tuple literals, and small integer literals.
The coordinator added the value-case connection and concatenation token support in this branch.
These shared edits remain separate from this family's owned files.
Unsupported expressions retain the existing checker policy. This draft does not restrict accepted DSL forms.
The compiler supplies the read types and binder identities. This output slice does not independently prove those facts.
Integer literals outside the small-literal slice remain unsupported by this additional check, not by the DSL.

`GeneratedAtomicUpdateProofTests` owns the actual Swift output controls.
The existing concatenation owner now uses an inline accepted `#spec` with nested append and concatenation.
It checks the actual complete Swift visitor and complete TLA action before it rejects changed operands.
The TLA controls reverse concatenation, substitute another state read, and change the appended element.
The Swift controls reverse concatenation and change the appended element.
Its other existing sequence tests retain the fallible-child controls.
`CollectionCheckingTests` owns generated execution, complete snapshots, and first-child runtime failures for those fixtures.
These runtime regressions do not discharge arbitrary child semantics or native-kernel correctness.

## Test authoring gate

The lowerer test protects source-read identity and ordered child occurrences at the real compiler boundary.
A changed constructor or operand order is its credible regression.
The existing synthetic contract table cannot detect a wrong source read in the real lowered result.
The test uses no new production seam.

The actual-output extension must accept each positive artifact before it rejects an altered artifact.
Its TLA mutations must change only the sequence order or operand value.
The rejection must name the actual output-check diagnostic, not an unrelated unsupported-input error.
No expected value can come from the renderer under check.
The extended existing owner protects a different boundary from the lowerer occurrence check.
An output backend can change an operand while the compiled expression remains correct.
The test uses the real output checkers and adds no production test seam.

## Remaining premises

- Accepted-syntax recognition, normalization, plan extraction, and source identities remain open.
- Leaf expression evaluation and element-child failure agreement remain premises.
- Fallible prefix, index, head, tail, remove, and arithmetic output rules are outside this slice.
- The checker, native sequence kernels, execution dispatch, and concrete failure encoding remain trusted.
- Shared action composition, initialization, complete-state commits, and checking semantics remain separate.
- Selected failures do not define the complete set of failures from several branches.

No complete sequence-language row or universal fidelity claim follows from this draft.

## Diagnostics

The coordinator granted the sequence lane one serialized local slot. All local commands are complete, and the slot is released.
The repaired pinned batch passed all four declared modules independently, with `--nofp`.
The constructor module discharged 48 obligations. The composition module discharged 104 obligations.
The first constructor attempt failed two obligations and does not qualify as passing evidence.
The repair named the existing failure-domain assumption and split the combined concatenation closure.
No theorem statement, premise, tool pin, or timeout changed.
The retained proof-source and runner-input hashes match the current draft.
Evidence resides at `/tmp/swifttla-sequence-family.lXlJxY/proof-batch-repaired`.
The approved combined Swift owner check passed all 33 tests.
It includes the changed lowerer and output owners, existing nested failure controls, and generated collection execution.
Approved static checks passed, including the family allowlist and admission-isolation regression.
The whitespace check and scoped Ponytail/TestAudit review passed.
The final hashes bind the current uncommitted source. They do not identify a frozen hosted revision.
No commit, push, diagnostic dispatch, or PR-head change occurred.
The read-only review found the expected renderer forms for pure `Append` and concatenation.
The focused run accepted the actual complete emitted body and rejected each asserted mutation.

