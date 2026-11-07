# Sequence append and concatenation

Status: sequence integration onto admitted `c12091f70c025aa6050155439bd167e914a8711a`. New integrated admission is pending.
The integration preserves the Boolean source checker, definition-stack repair, renderer repair, native-helper repair, and pinned-download prerequisite.
The sequence source-link repair depends on that Boolean checker. It is not an independent shared-checker change.
The original `d559041fba3a702b615bc52c827f32660135ecbd` family revision remains frozen.
The shared outcome, frame, and indexed-history definitions remain unchanged.

## Conditional rules

The source rules construct sequences from their index maps.
The generated rules use `Append` and concatenation, with separate expressions for failure selection.
The rules retain every sequence index and the complete selected failure payload.
An earlier failed child suppresses the later child.
The negative theorems distinguish reversed concatenation and an omitted appended element.

The composition module has separate source and generated evaluators.
It uses the existing indexed-history existence and induction theorems.
Its plan permits arbitrary finite append and concatenation trees, empty plans, and repeated values.
Each append has a sequence child and an element child.
Element-child semantics remain independent inputs. Sequence leaves and element children must agree for each context.
The theorem does not discharge those agreement premises.

The action-outcome interface receives a sequence result through an explicit projection.
The projection preserves the selected failure and supplies no update after failure.
It does not prove assignment targets, complete-state materialization, or action labels.

## Translation connections

`CompiledLowerer.scheduleSequenceBinary` uses `SequenceExpressionLoweringContract.matches`.
That contract checks the constructor and exact ordered scheduled operands.
It does not independently derive the scheduled operands from accepted syntax.
The existing lowerer owner checks actual source-read identities and rejects a changed constructor or reversed operands.

`StraightLineAssignmentCheck.verifyCompiled` now traverses append and concatenation in its existing `simple` and `matching` cases.
It checks the exact constructor, two-child arity, ordered children, and existing literal, state, and binder identities.
It retains all admitted Boolean cases and the existing preflight and scope gates.
The sequence extension does not prove normalization, type resolution, or arbitrary accepted syntax.

`StraightLineRenderedActionCheck+Sequence.swift` extends the existing TLA output checker.
Its expected values derive from compiled constructors and resolved identities, without renderer calls.
This slice contains pure append and concatenation trees with reads, tuple literals, and small integer literals.
The integration adds the existing value-case connection and concatenation token, while preserving Boolean tokens and payload gates.
Unsupported expressions retain the existing checker policy. This slice does not restrict accepted DSL forms.
The compiler supplies read types and binder identities. This output check does not independently prove those facts.
Large integer literals remain unsupported by this additional check, not by the DSL.

The existing `GeneratedAtomicUpdateProofTests.sequenceConcatenationRetainsOrder` owner uses one inline accepted `#spec` with nested append and concatenation.
It checks normalized source agreement and both actual complete emitted outputs before it rejects altered artifacts.
Six source mutations change each sequence read, concatenation order, appended element, append presence, or constructor.
Each mutation changes one occurrence and must produce the existing compiled-assignment diagnostic.
The TLA mutations change concatenation order, a state read, or the appended element.
The Swift mutations change concatenation order or the appended element.
The existing sequence owners retain fallible-child controls.
`CollectionCheckingTests` owns generated execution, complete snapshots, and first-child runtime failures for those fixtures.
These runtime regressions do not discharge arbitrary child semantics or native-kernel correctness.

## Evidence and admission

The historical focused family diagnostic `41225882308` passed at exact `d559041f`.
Its retained audit covered both jobs, source and runner hashes, pinned tools, four proof modules, and 33 implementation tests.
That diagnostic qualifies its historical family boundary. It does not admit the new integrated candidate.

The integrated mutation-only baseline used the unchanged admitted Boolean source checker.
It executed one existing test and exposed exactly six labelled accepted-corruption failures, without setup, compilation, or positive-output failures.
This result measured a checker blindspot. It did not demonstrate wrong production compiler output.
The repair adds only append and concatenation traversal and operation matching to the existing source checker.
The unchanged owner then passed with all six source mutations and both actual-output controls.
All 13 recorded input hashes remained unchanged during that focused run.

The ordinary proof receipt includes the sequence checker extension and both changed test owners.
The integrated action batch retains every prior row and adds sequence constructor rules before composition.
The related safety-wrapper run passed 183 tests across all 22 required suites.
It retained the admitted Boolean, Dining, deep-binding, lexical payload, and native-helper controls.
Static checks passed family isolation and all five pinned-download controls.
The integrated pinned `--nofp` batch proved all 1,105 obligations in its fifteen ordered modules.
All 149 proof snapshots and both runner hashes matched the final inputs.
Whitespace and scoped Ponytail/TestAudit review passed. All sixteen prerequisite hashes and the c120 renderer remained exact.
The ordinary manifest contains 204 proof input entries.
Its expected hosted scope contains 92 modules and 5,877 obligations, including unchanged legacy proofs.
The local integrated batch did not rerun those legacy proofs.
Local results are diagnostic only. Ordinary CI and full unfiltered validation must admit the exact published candidate.

## Remaining premises

- Accepted-syntax recognition, normalization, plan extraction, and general source identity remain open.
- Leaf evaluation, resolved types and binders, and element-child failure agreement remain premises.
- Fallible prefix, index, head, tail, remove, and arithmetic output rules remain outside this slice.
- The checker, native sequence kernels, execution dispatch, and concrete failure encoding remain trusted.
- Shared action composition, initialization, complete-state commits, and checking semantics remain separate.
- Selected failures do not define the complete set of failures from several branches.

No complete sequence-language row or universal fidelity claim follows from this integration.
