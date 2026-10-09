# Semantic-preservation contract

Status: **unproved**. This document defines the claim to prove. Finite graph
comparisons do not discharge it.

## Scope

The source language is the subset of `#spec` accepted after parsing, binding,
type checking, and configuration resolution. An unsupported source form must
fail with a diagnostic. The target paths are the generated Swift machine and
the rendered TLA+ module with its configuration. Authored PlusCal is a third
target only for programs whose export succeeds.

`CompiledProgram` is a proof boundary, not the source semantics. Two backends
can agree on an incorrectly lowered program. That agreement does not prove
that either backend implements the author's `#spec`.

## Integer range obligation

Generated Swift retains Swift `Int`; arbitrary-precision integer values are
not part of the native model API. Rendered TLA+ uses mathematical integers. A
semantic-preservation claim therefore needs a range proof for every integer
value evaluated by an accepted program, including intermediate arithmetic in
initializers, action guards and updates, and selected claims. The bounds are
those of the target Swift `Int`, not an assumed constant width. Division by
zero and other specified evaluation failures need separate matching rules.
Compilation must reject a program when it cannot establish the required
range safety; a finite TLC or native exploration is not such a proof.

This gate is **not implemented**. `CheckedExecutionOverflow` in
`NativeExecutionBoundaryTests` is a concrete accepted counterexample: its
`count + 1` step starts at `Int.max`, so the generated machine throws while
the rendered TLA+ arithmetic has a successor. Until the gate and both output
links are proved, the universal theorem does not hold for accepted `#spec`.
`EWD998TerminationModel` presents a different case: while a sender remains
active, `SendMsg` can increment a receiver's `pending` count indefinitely.
Its `pending <= 3` state constraint limits checking, not the generated
machine's transition relation. A proof that this model always fits Swift
`Int` would be false. Under the chosen `Int` contract, this unbounded model
cannot receive an unconditional semantic-preservation certificate. A bounded
replacement would be a different source model and cannot silently count as
parity with the upstream unbounded transition relation.

## Choice-expression obligation

The expression-level `StateExpr.choose` is distinct from the nondeterministic
`Choose` algorithm statement. The generated Swift expression sorts its finite
domain and returns the first satisfying member, or throws when none exists;
the TLA+ renderer emits ordinary `CHOOSE`. TLA+ permits an unspecified
consistent witness and gives `CHOOSE` an arbitrary value when none satisfies
the predicate ([Specifying Systems, §16.1.2](https://lamport.azurewebsites.net/tla/book-01-08-21.pdf)).
Therefore the current outputs are not generally equal for observable
expression-level choice. A sound output link must either emit the same
canonical selection in TLA+ or prove that every accepted use has a unique
satisfying witness and define matching no-witness behavior. Agreement on a
finite TLC run cannot discharge this obligation.

`SingleAssignment.tla` now proves the general unique-witness rule for every
typed domain and Boolean predicate: if exactly one member satisfies
the predicate, TLA+ `CHOOSE` returns that member. This establishes the TLA+
side of the restricted case, not that the compiler proves uniqueness for
accepted uses or that emitted Swift evaluates every predicate identically.

## Checked kernel lemma

`SingleAssignment.tla` proves that replacing one value in a complete state
has the same successors as a guarded TLA+ assignment to that variable with
every other variable unchanged. It also proves equality of the corresponding
enabled-successor predicates. The theorem assumes the assigned key belongs
to the state's variable set. It is generic over state domains and values.

The same module also proves that two distinct compiled assignments can update
one complete state simultaneously, with every other variable unchanged. This
is a compiled-action rule. Statements inside an authored `Do` step instead run
in order while the resulting step remains externally atomic. A local negative
control changed the second rendered value to the first value; TLAPS rejected
the resulting obligation. Restoring the correct value restored the proof.

The generalized update rule now covers any typed subset of state variables:
applying a partial assignment map to a complete state is equivalent to the
rendered assignments plus an unchanged frame for every other variable. A
second rule covers conjunction of two assignment maps when overlapping writes
agree. If they disagree, the rendered conjunction has no successor. The
compiled and generated Swift enumerators instead throw a conflicting-assignment
error; the universal proof must show that accepted `#spec` lowering cannot
reach such a conflict, or align the declared error semantics across outputs.

The guarded-choice composition rule preserves complete labeled edges and
enabledness for any choice domain, provided corresponding branches produce
equal edge sets and both outputs use the same guard and domain. These premises
are not yet discharged for arbitrary compiler input. The rule is a reusable
induction step, not proof that the current Swift emitter satisfies it.

The conditional-action rule selects a branch by a Boolean predicate of the
complete source state. TLAPS proves that equal source/rendered predicates and
branch edge sets yield equal complete labeled edges, and that the conditional
is enabled exactly when its selected branch is enabled. This supplies a
compositional `ifElse` step, not a proof that the compiler preserves the
predicate or that both emitters implement each branch. The repeated-write
guard proof was split into the initial guard and the remaining positions so
the full module checks without relying on prover search over one large step.

The ordered-`Do` lemma uses finite, indexed source and scheduled histories.
TLAPS proves that both histories exist for every finite sequence of typed
abstract **assignment** instructions and that their complete states agree at
every position, including repeated writes and reads of earlier writes. It
also proves equality of the resulting complete-state transition relation,
enabledness, and labeled edges. This removes the vacuity risk in the earlier
conditional theorem. It is **not** a total
compiler-correctness theorem: we have not proved that the abstract schedule
is exactly the Swift lowerer's schedule, that accepted source expressions
denote the abstract instruction functions, or that either emitter implements
the abstract rules. The indexed formulation avoids a recursive-operator
limitation in this pinned TLAPS build; that tool workaround does not discharge
the compiler and output obligations.

The ordered conditional extension permits an arbitrary finite assignment
prefix, either finite branch, and a common suffix. The branch predicate is
placed at history index `Len(prefix)`, the intended state after the prefix.
TLAPS proves source and
scheduled transition relations, enabledness, and labeled edges equal for
every such plan and pure total predicate. A separate induction proves source
histories unique; the emitted copy fixture uses that theorem instead of a
large solver-only uniqueness step. Conditional expression evaluation,
an explicit prefix-history restriction theorem, algorithm lowering, and the
generated output links remain open.

The guarded-history extension assigns a total, pure predicate to each position
before, between, and after those assignments. TLAPS proves that each guard
observes the same complete state in both histories and that guarded steps have
equal successors, enabledness, and labeled edges. A false later guard therefore
disables the whole abstract atomic step, including earlier pending writes.
Multiple guards at one position can be conjoined. This does **not** prove the
Swift scheduler's expression substitution, partial evaluation or failure
behavior, branch selection, or control transfers; those remain separate
compiler-to-semantics obligations.

`GeneratedAtomicCopyProofModel.tla` is the complete TLA module emitted from a
small `#spec` model. `GeneratedAtomicUpdateProofTests` requires byte-for-byte
equality with `GeneratedAtomicCopyProofModel.render()` and checks the generated
Swift machine's concrete `(0, 1) -> (1, 1)` step. This module is imported by
`SingleAssignment.tla`, which proves its generated `Init`, `copy`, and `Next`
equivalent to independently stated source relations. It also derives that
relation from two ordered state replacements: in this `Do` step, the second
assignment reads the first assignment's new value. Changing that source read
to the pre-step value made the ordering theorem fail. Changing the imported
module's second next-state value to `0` made the action theorem fail; restoring
both values restored the proof. This is an output-linked proof for one source
fixture. The emitted `copy` action is also proved equivalent, over typed
complete pre- and post-states, to the two independently stated instructions
under the general ordered-schedule relation. Neither result proves the Swift
emitter or arbitrary accepted models.

The existing `OrderedCopyModel` fixture now pins its complete generated TLA+
module byte-for-byte in `OrderedCopy.tla`. For integer `x`, TLAPS proves its
emitted `Init`, both ordered actions (including two writes to `x` in one
atomic step), terminating step, and `Next` equivalent to independently stated
relations. It also proves the integer/control-state invariant and equivalence
of the complete temporal `Spec` over the resulting behaviors. The existing
generated-machine test exercises the same two action steps. A separate
complete-state relation theorem proves that every typed state has a successor
and that this relation is exactly the generated `Next` relation. This is
relational no-deadlock for this model; a direct theorem about TLA+'s `ENABLED`
operator is not checked because the [pinned TLAPS proof system lists it as
unsupported](https://proofs.tlapl.us/doc/web/content/Documentation/Unsupported_features.html).
This covers one actual algorithm-lowering output, not the compiler's general
substitution rule or all generated Swift transitions.

The emitted `repeatWrites` action is also tied to the generic guarded-history
rule. Over typed complete states, TLAPS checks that its control-location guard
and two ordered writes to `x` have exactly the same transition relation as the
indexed source history and its scheduled form. The abstract instructions use
a total fallback for ill-typed states; the correspondence theorem assumes the
model's integer `x` and `y` values. This remains a proof of one emitted TLA
action, not of arbitrary compiler output or the generated Swift code. Changing
only the second abstract increment from `+ 1` to `+ 2` made the new history
obligation fail; restoring it restored all obligations.

`GeneratedGuardedChoiceProofModel.tla` is a second complete emitted module,
checked byte-for-byte against its `#spec` fixture. Its generated Swift machine
has exactly two successors from the initial state and disables the action in
both successors. `SingleAssignment.tla` separately states the source guard and
the two permitted next values, then proves equivalence with the emitted
`Init`, `choose`, and `Next` definitions and proves disabledness after a choice.
Widening the emitted choice domain from `1..2` to `1..3` made the action proof
fail; restoring it restored the proof. This is a second output-linked case,
not a general proof of guarded choice or of the Swift emitter.

`ConditionalStepProofModel.tla` is the complete output from a `#spec` step with
an `If`/`else` assignment. The fixture test pins those bytes and checks the
generated Swift machine from both possible initial Boolean values. In a
separate module, `ConditionalStep.tla` proves that the emitted initial states,
both conditional branches, terminating action, and `Next` match independently
stated source relations over Boolean condition states. This covers one actual
conditional lowering and TLA output; it does not prove arbitrary conditions,
expression failures, or the Swift emitter for all states. Changing only the
emitted false-branch value from `2` to `3` made the branch obligation fail;
restoring it restored all 9 obligations.

TLAPS 1.6.0-pre checked all 372 `SingleAssignment.tla` obligations and all 9
`ConditionalStep.tla` obligations locally with fingerprint reuse disabled. The
arm64 TLAPS archive had SHA-256
`fe2ac4b0e4bfd7fa038a9857be8a56e4521a1e3b3ec41c9a80b01fa390de3987`;
its bundled Z3 was x86-only, so the check used arm64 Z3 4.15.4 with archive
SHA-256 `8bb3439772cafd75240d61abf255e89122850bab93563d1283b048359ab4e88f`.
This is local diagnostic evidence, not hosted admission. The generic lemmas
do not yet prove expression evaluation or compiler lowering. The imported
fixtures connect actual TLA outputs, but the general TLA-emitter and
generated-Swift output links remain mandatory.

Ordinary CI now defines a separate `semantic-proof-diagnostic` job. It verifies
the official Linux TLAPS archive against SHA-256
`13eff4e3dd0a4570c1c33c46f052fd4eb3afad465eb201ebade607961f09d43c`,
replaces only its bundled Z3 with official Linux Z3 4.15.4 pinned to SHA-256
`a41b690e89c343931471506cdc6d957b6044a200fd2d240cc017432afdff7d3e`,
checks both proof modules without fingerprint reuse, and retains the exact
source SHA, proof-input digests, tool versions/configuration, and separate
proof logs. A changed archive fails its checksum. This job does not yet have
qualifying hosted evidence and is not the universal semantic-preservation
admission check.

## Observable behavior

For a source model `M` and resolved configuration `C`, define:

- `Init(M,C)`: the set of complete initial model states.
- `Step(M,C,s,a,t)`: one enabled atomic transition from `s` to `t`, labeled by
  the complete action invocation `a`.
- `Eval(M,C,s,p)`: the value or specified evaluation failure of a state claim.
- `Traces(M,C)`: the infinite behaviors formed from `Init` and `Step`, with
  TLA+ stuttering and declared fairness interpreted explicitly.

An assumption-only model also observes the ordered values that `PrintT`
records. A proof of its checking behavior must preserve the selected branch,
the recorded values, and their order.

The observation includes hidden control locations and every declared model
variable. Checking-only registers, resource limits, views, symmetry reduction,
and serialized evidence are separate operations with separately stated
semantics. None silently changes `Init` or `Step`. A declared view can identify
states for checking only when the corresponding source/TLA checking mode does.

The state correspondence must be a total, value-preserving encoding of every
supported state type. The action correspondence must retain the action identity
and all bound arguments. Neither a fingerprint nor a traversal ID establishes
equality. Auxiliary PlusCal translator variables require an explicit relation.
They cannot be discarded by an implicit projection.

## Required theorems

If compilation and emission succeed, these theorems must hold for every
accepted `M` and legal `C`:

1. **Initial states.** The source, generated Swift, and generated TLA+ initial
   sets correspond in both directions under the declared state encoding.
2. **Atomic steps.** For every corresponding source/target state, each enabled
   source action invocation has exactly the corresponding generated successors,
   and every generated successor comes from such a source step. Disabled
   actions, nondeterministic branches, assignment conflicts, and evaluation
   failures retain their specified outcomes. Repeated identical derivations
   are one labeled graph edge unless the source contract explicitly observes
   multiplicity.
3. **Claims.** State invariants, reachability, deadlock, and selected
   postconditions have corresponding evaluations. Infinite-trace properties,
   fairness, stuttering, and refinement preserve their declared meaning, not
   merely their result on one finite graph.
4. **Outputs.** The proof reaches emitted Swift and TLA+ syntax. An
   intermediate-representation theorem alone is insufficient. Rendering,
   generated code, and their name/value encodings need a verified or
   independently checked connection to the semantics above.
5. **PlusCal.** For every supported authored PlusCal export, translation by the
   pinned official translator satisfies the declared state/action relation and
   the same selected checking behavior. Each translator assumption belongs in
   the trusted-boundary record.

The forward and reverse step clauses intentionally demand equality for the
model transition system. A one-way refinement claim is not a substitute for
the promised native/TLA fidelity. Infinite-trace properties require a separate
argument even after finite transition equality is established.

## Proof decomposition and trusted boundaries

Prove source-to-resolved-program lowering, resolved-expression evaluation,
atomic-action execution, initialization, and claim construction separately.
Then prove each emitter against the resolved-program semantics. The current
implementation boundaries are `SpecParser`, `CompiledLowerer`,
`ProgramResolver`, `NativeSwiftEmitter`, `CompiledTLARenderer`, and
`AlgorithmPlusCalRenderer`. The proof must track their current behavior,
not a simplified substitute.

The compiled action tree has eight constructors in
`Sources/SwiftTLA/CompiledExpressions.swift`. It is consumed by three distinct
implementations: `CompiledActionEnumerator` executes it for compiled checking,
`NativeSwiftEmitter+Machine` emits executable Swift, and `CompiledTLARenderer`
prints TLA+. The generated Swift machine does **not** delegate action execution
to `CompiledActionEnumerator`. Consequently, a theorem about the action tree
or the compiled checker alone cannot discharge either output obligation.

| Action-tree rule | Current machine-checked fact | Output obligation still open |
| --- | --- | --- |
| `assign`, `unchanged` | Complete-state delta and unchanged-frame equality | Prove each emitted Swift update and TLA clause denotes that delta for every compiled expression and state type. |
| `guard_` | Pure, total guards agree at each abstract ordered-statement position | Prove emitted predicate evaluation, disabledness, short-circuit failures, and source `When` substitution. |
| `and` | Compatible delta conjunction and conflicting relational writes | Prove both emitters' evaluation order, conflict/error semantics, and frame completion. |
| `or` | Guarded-choice preservation conditional on equal branch edges | Prove branch construction, multiplicity policy, and failure behavior in both outputs. |
| `existsAction`, `define`, `ifElse` | No general output-linked theorem | Prove binding scope, selected domain/branch, expression evaluation, and both emitted forms. |

This table is a proof inventory, not a claim that these five groups exhaust
`#spec`: initialization, source lowering, properties, temporal behavior,
refinement, and PlusCal export also require their own output links.

Record exactly which parser, macro-expansion, Swift compiler/runtime, TLA+
parser/TLC, PlusCal translator, serialization, and proof-checker facts remain
assumptions. Do not describe a result as a universal guarantee if a backend
or text-generation boundary remains unproved or unchecked.

## Independent evidence

Keep purpose-built finite conformance models with hand-specified expected
states and transitions. For each supported construct, require a source-level
witness, native/generated-TLA complete-graph comparison, selected verdicts,
and a negative control that the comparison rejects. Where the construct is
expressible in PlusCal, retain the official-translator differential check.
These checks find mistakes in the formalization and implementation. No finite
set of them proves the universal theorems.

The proof milestone is complete only when every supported source and target
construct is covered by machine-checked theorems, all proof assumptions are
documented, and hosted CI runs the proof and independent regressions on the
same final revision. The upstream example-family corpus remains a subsequent
milestone, not evidence that can replace this proof.
