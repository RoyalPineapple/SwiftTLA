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
not part of the native model API. This is the chosen representation, not a
temporary implementation detail. The accepted source rule is a checked `Int`
operation: if a mathematical intermediate result is outside the target Swift
`Int` bounds, evaluation fails explicitly on both generated paths, without a
successor or partial state update. Programs are not rejected merely because
such a failure is reachable. The failure must identify the same operation and
operand values after the same evaluation order in both outputs, including
initializers, action guards and updates, and selected claims. The bounds are
target-dependent, not an assumed constant width. Division by zero and other
specified evaluation failures need separate matching rules. A finite TLC or
native exploration is not a proof that overflow is unreachable.
The current macro embeds TLA+ bounds using its build host's `Int` width.
Generated export now rejects a different target `Int` width explicitly;
cross-width builds remain unsupported rather than silently producing the
wrong bounds.
The pinned TLAPS 1.6.0-pre diagnostic could not discharge the former
hard-coded 64-bit literal lemmas: its [SMT standardizer converts each
numeric literal with OCaml `int_of_string`](https://github.com/tlaplus/tlapm/blob/d8b9747/src/encode/n_standardize.ml#L244-L254),
while a 64-bit OCaml host's `int` has only [63 bits](https://ocaml.org/manual/5.1/api/Sys.html).
Switching these obligations to `BY Isa` does not solve the literal boundary:
the pinned [Isabelle translator also calls `int_of_string`](https://github.com/tlaplus/tlapm/blob/d8b9747/src/backend/isabelle.ml#L451-L456).
The hosted diagnostic failed on all three such lemmas; this is not a proof that
the compiler's arithmetic is correct or incorrect. Do not merely spell the
bounds as arithmetic over smaller literals:
the same pinned tool [constant-folds with OCaml `int`
arithmetic](https://github.com/tlaplus/tlapm/blob/d8b9747/src/smt/rewrite_arith.ml#L40-L62),
which needs an independent overflow-safety argument. The ordered-write proof
now imports a symbolic version of its generated TLA module, tied to the real
output by a narrowly normalized exact-output test. Its bounds are assumptions
about the target Swift `Int`, not TLAPS-proved numeric facts. All 1,423
obligations in the revised `SingleAssignment.tla` passed locally with
fingerprint reuse disabled; hosted evidence for these inputs is still pending.
Rendered TLA+ now guards pure addition, subtraction, multiplication, and
negation trees in an action binding
and emits ordered overflow-failure predicates with operand tuples. Other
arithmetic operations and evaluation positions still use mathematical integers,
so the source rule is not yet implemented for every accepted program.
The pinned TLC evaluator is not an overflow oracle for Swift `Int`: its
[`IntValue` stores a Java `int`](https://github.com/tlaplus/tlaplus/blob/b123b22654942bd7f8b1bcadcc47da4ee2cf4c0e/tlatools/org.lamport.tlatools/src/tlc2/value/impl/IntValue.java),
and its [addition override fails on 32-bit overflow](https://github.com/tlaplus/tlaplus/blob/b123b22654942bd7f8b1bcadcc47da4ee2cf4c0e/tlatools/org.lamport.tlatools/src/tlc2/module/Naturals.java).
That failure can precede a valid generated-Swift result on a 64-bit target,
while a large Swift literal is outside TLC's `IntValue` range. The TLA+ output
therefore needs an explicit mathematical failure relation tied to the selected
Swift `Int` bounds; TLC execution is evidence only within its own numeric
range. The emitted fast path keeps two operands within ±1,000,000,000, so
their sum fits TLC's signed 32-bit range; it does not test the 64-bit overflow
boundary. Do not equate a TLC arithmetic error with the source failure outcome.
Using TLC's operational `Assert` failure alone would not establish this
agreement: the [standard TLA+ definition of `Assert`](https://github.com/tlaplus/tlaplus/blob/master/tlatools/org.lamport.tlatools/src/tla2sany/StandardModules/TLC.tla)
does not define a matching mathematical error outcome. The failure must be
represented in the semantics of both outputs. A range-safety proof may establish
that a particular configuration never reaches the failure, but is not a
condition for accepting the program.

This matched-failure rule is **partially implemented**. For
`CheckedExecutionOverflow` in `NativeExecutionBoundaryTests`, the generated
Swift machine reports `Int.max + 1` as an evaluation failure; the rendered
TLA+ action has no overflowing successor and exposes a failure predicate,
the `addition` operation identity, and the complete operands. An exact-output
test pins the emitted module. Because the pinned TLAPS backend has not discharged
these obligations using the full-width emitted integer bounds, the test requires a byte-for-byte
match between that module after replacing only its module name, the emitted
minimum-bound expression `(-Int.max - 1)`, the maximum-bound literal, and the
constant declaration, and the
`CheckedExecutionOverflowSymbolic.tla` module imported by the proof. The proof
assumes integer bounds enclosing the renderer's fast path; the test ties the
symbolic constants to the emitted `(-Int.max - 1)` and `Int.max` text. This
normalization and the target Swift `Int` contract are trusted links, not TLAPS
theorems. `SingleAssignment.tla` separately proves the generic addition guard.
The same focused test checks the complete
compiled `advance` action. It requires the control guard, bound `count + 1`
addition, count update, and transition to `Done`. It identifies the separate
internal terminating action. The test checks every token of the emitted Swift
action against `CheckedExecutionOverflowSwiftWitness.txt`, including the
control guard, ordered operands, checked-addition call, count update, and
control-state update. It also checks that the generated machine identifies
that action as the rendered `advance` action with no arguments and projects
the complete initial `pc` and `count` values from the generated machine,
matching the compiled runtime's initial state. The
native boundary test checks the generated Swift failure and unchanged state; the
representable-operand mismatch theorem is a generic negative control, while
`UncheckedAdditionNegativeControl` shows this emitted fixture's initial state
would have an out-of-range mathematical successor without the guard. These are
fixture-level output links, not a general lowering or Swift-emitter proof.
`CheckedExecutionOverflowProof.tla` states exact-output obligations for
initial state, the labeled `advance` machine action, the separate emitted
`Terminating` stutter action and full exported `Next`, and the complete failure
record; all 45 obligations passed locally, while hosted evidence remains
pending. `Terminating` is not
presented as an application action or as a native graph edge.
The initial overflow disables `Next` while making the failure predicate true,
so selected failure reporting must take precedence over ordinary deadlock.
For initial states TLC can represent, the
[pinned checker](https://github.com/tlaplus/tlaplus/blob/867aefb69ffc2452031292587b389d1fc3eb43ff/tlatools/org.lamport.tlatools/src/tlc2/tool/ModelChecker.java#L1123-L1133) evaluates invariants
before successor exploration and its deadlock check; this fixture's `Int.max`
is outside TLC's numeric range, so that execution order cannot validate this
particular failure trace. The exact-output TLAPS obligation is the proof path.
The generated TLC configuration now selects an intrinsic invariant over that
predicate even when callers select no user checks. The independent comparator
does not yet reconcile a TLC invariant violation with the native typed failure
record, so this is not end-to-end matched checking evidence.
`TypedActionParameterTests` confirms that a literal-domain parameterized step
quantifies the failure over each declared argument and retains that intrinsic
check under empty user-check selection. A second test checks the emitted
failure guard and quantifier for a symbolic parameter domain. Neither case
has a general output-linked proof for every parameterized action.
Pure addition, subtraction, multiplication, and negation trees now emit
ordered failure sites and guard the action on every site. One focused
regression checks a nested addition's native
outer overflow and both TLA+ failure records. A second regression first failed
because `Int.max - (-1)` threw in generated Swift while TLA+ allowed a
successor; it now checks the compiled subtraction node, the complete emitted
Swift action against the shared assignment witness, a successful complete-state
transition, the typed native failure, and the exact TLA+/PlusCal guard, failure
predicate, operation, and operands.
`CheckedSubtractionProof.tla` states the symbolic guard and complete labeled
edge/failure obligations; all 40 obligations passed locally. The output test checks the
subtraction instance of that guard; Swift's checked-arithmetic primitive and
the test's output extraction remain trusted boundaries. `CheckedMultiplicationProof.tla`
proves the multiplication fast-path bound and exact fallback preserve complete
labeled edges and failure records for representable operands; its unguarded
negative control adds an invalid edge. All 12 obligations passed locally.
A focused generated-machine test checks successful multiplication, positive and
negative overflow without state changes, the emitted Swift action tokens, and
the rendered TLA+/PlusCal guard, operation, and operands. It does not prove
arbitrary emitter output or TLC execution beyond TLC's integer range.
`CheckedGuardFailureProof.tla` proves a symbolic simplification of the emitted fast-path addition guard,
source rule, and modeled native rule have the same complete labeled edge and
addition-failure sets for a pure `When(count + 1 > 0)` condition; its unguarded
negative control adds an invalid edge. All 10 obligations passed locally. The focused generated-machine
test checks the successful native step, exact typed overflow and unchanged
state, and emitted failure metadata. This proof is a symbolic rule, not yet an
exact-output proof of the complete module or a proof of the Swift emitter.
`SingleAssignment.tla`
also proves the root negation guard, complete labeled edge/failure relation,
and an unguarded counterexample under the explicit Swift signed-`Int` bound
relation. A focused generated-machine test exercises both a successful nested
negation and `-Int.min` failure, and checks both ordered emitted failure sites;
it does not yet pin the complete emitted module or prove the Swift emitter.
Arithmetic under other expression operations, effectful operands,
initialization, non-pure guards, failures after non-guard action prefixes,
division, and target-width differences
remain open. The universal theorem does
not yet hold.
`MachineValidator.run` now reports a typed early evaluation-failure event and
completion for value failures while evaluating a generated action body,
including integer overflow and an empty expression-level `CHOOSE`. The event
retains the source state ID, action, and applicable operation and operands.
Errors from the evidence callback are not reclassified as model failures.
Binary evidence now retains the typed failure, action identity, and operands
with a checked completion footer. The independent comparison path still rejects
that outcome until generated TLA+ has a matching failure rule. The native
validation runner reports the typed failure reason rather than an unavailable
checking outcome; this is a diagnostic, not parity evidence. Errors from
action-domain enumeration, initializers, constraints, and selected claims need
their own matching output rules and checking evidence.
`EWD998TerminationModel` presents a different case: while a sender remains
active, `SendMsg` can increment a receiver's `pending` count indefinitely.
Its `pending <= 3` state constraint limits checking, not the generated
machine's transition relation. A proof that this model always fits Swift
`Int` would be false. Under the `Int` contract, this unbounded model cannot
receive an unconditional range-safety certificate. The required matched
overflow failure would preserve bounded source semantics, but would not
establish parity with the upstream unbounded transition relation. A bounded
replacement would be a different source model and cannot silently count as
that parity either.

`CurrentAdditionAgreementIsExactlyRangeSafety` models checked native addition
as a tagged value or overflow outcome and the currently emitted TLA+ `+` as a
mathematical value. For representable operands, TLAPS proves that the two
outcomes agree exactly when the sum is representable. Replacing the modeled
overflow with a normal value makes the obligation fail. This identifies the
necessary range or output-change obligation; it does not prove that arbitrary
emitted Swift evaluates this model, nor does it make the current outputs agree
on overflow. A second theorem establishes that representable operands with
different outcomes always exist for these finite bounds (`SwiftIntMax + 1` is
a witness), so an unrestricted addition-equivalence claim for the current
outputs would be false.

The same exact range-safety equivalence is proved for the emitted subtraction,
multiplication, and unary negation forms. These are operator-level obligations,
not certificates for every occurrence in an accepted program. Division needs
its own nonzero-divisor and rounding rule; modulo has a separate
positive-divisor rule below.

`AddOverflowGuardMatchesCheckedInt` proves a pre-evaluation addition guard:
for representable operands, checking `lhs > SwiftIntMax - rhs` when `rhs > 0`
or `lhs < SwiftIntMin - rhs` when `rhs < 0` detects exactly the sums outside
Swift `Int`. `AddOverflowGuardUsesRepresentableThresholds` proves that those
thresholds themselves fit in `Int`. `GuardedAddMatchesNativeFailureAndValue`
then proves that a guarded mathematical sum has the same tagged value or
overflow outcome, including the `addition` operation and both operands, as
checked native addition. `GuardedOrderedAddPreservesFailurePriorityAndPayload`
composes that rule with left-first operand evaluation: a left failure wins over
a right failure, and either wins over root addition. A distinct-failure
negative control shows that reversing operand priority changes the result.
`EmittedAddGuardMatchesCheckedInt` also proves the emitted fast path and exact
fallback equivalent to representability for already-representable operands,
provided the target `Int` bounds include `-2000000000...2000000000`. This is
an operator theorem, not yet a theorem about the actual generated module.
`RootAdditionPreservesCompleteLabeledEdgesAndFailures` composes that guard
with a complete-state update and action identity: the source, abstract native
checked-add, and emitted TLA rules have equal labeled edge sets and failure
records, including the original state, action, operation, and operands. Its
assumptions require representable operands and the same target bounds. The
native branch trusts Swift's `addingReportingOverflow` contract and the small
`_NativeMachineOperations.add` wrapper; the fixture's generated-Swift witness
and runtime failure test check that link, but are not a proof of the Swift
compiler or every accepted addition lowering to this root form.
The direct emitter now uses checked guards for pure addition, subtraction,
multiplication, and negation trees in action bindings and emits ordered
overflow-failure predicates, operation identities, and operand tuples. The
generic addition, subtraction, and multiplication theorems cover their
mathematical guards and modeled operand outcomes; they do not yet prove the actual
emitted Swift expression or TLA+ action evaluates every nested operand in
this order. The generated TLC configuration selects the emitted failure
predicate, but native-versus-TLC outcome comparison remains open.

The direct TLA+ renderer now gives each operand one local definition and
normalizes a negative divisor into a positive one before integer division.
This avoids relying on TLC's negative-divisor extension to the mathematical
`\div` operator. The output link is still incomplete: `Int.min / -1`, division
by zero, actual target integer bounds, and evaluation-failure order still need
matching outcome proofs. TLC's bounded integer evaluator may also overflow
while evaluating an intermediate negation that is valid in mathematical TLA+.

`SingleAssignment.tla` proves that the rendered negative-divisor branch has a
positive divisor and a Euclidean remainder in `(divisor + 1)..0`. The latter
proof assumes `PositiveDivisionLaw`, the standard positive-divisor quotient
law; TLAPS checks the sign transformation but does not discharge that axiom
from the imported arithmetic module. The distributed
[Naturals module](https://github.com/tlaplus/tlaplus/blob/master/tlatools/org.lamport.tlatools/src/tla2sany/StandardModules/Naturals.tla)
deliberately contains dummy arithmetic definitions for tools to override; its
comment states the positive-divisor quotient/remainder equation, but those
dummy definitions cannot prove the bounded-remainder premise used here.
`PositiveDivisionQuotientUnique` additionally proves that two bounded
positive-divisor remainder decompositions of the same integer have the same
quotient. `PositiveDivisionNegation` and
`AdjustedTruncatingDivisionMatchesRendered` prove that the mathematical
truncating quotient with a nonzero-remainder sign correction equals the exact
rendered expression for every nonzero divisor. Under the same division-law
assumption, `ModeledSwiftDivisionAlgorithmMatchesRendered` connects a model of
the helper's truncating quotient, signed remainder, and correction to that
rendered expression. `CurrentDivisionAgreementIsExactlyRangeSafety` proves
that the modeled checked outcome agrees with rendered TLA+ exactly when the
quotient fits Swift `Int`. This still trusts Swift's primitive division and
remainder behavior, the emitted call to `_NativeMachineOperations.divide`, and
its checked-overflow behavior; the actual output link and agreement on overflow
are not proved.

`CompiledSpecificationRendererTests`
compares the actual symbolic renderer output with the expression in this proof
module. These checks do not yet establish the native Swift output link or the
overflow and evaluation-failure cases.

`SignedIntegerSemanticsTests.generatedRightOperandFailurePrecedesLeft` checks
the actual generated Swift machine when its left operand overflows and its
right operand divides by zero. It requires the right-side failure and an
unchanged state. This is a concrete output regression, not a proof of failure
order for every expression or agreement with rendered TLA+ on failures.

`ModeledSwiftModuloMatchesEuclideanRemainder` proves that the helper's modeled
signed-remainder adjustment equals the mathematical nonnegative remainder for
every positive divisor. `ModeledSwiftModuloStaysWithinSwiftInt` proves that
this result fits Swift `Int` whenever both operands do; unlike division, the
result needs no additional range premise. The link to the renderer's `%` is
conditional on `PositiveModuloLaw`, matching the [standard Naturals operator
contract](https://github.com/tlaplus/tlaplus/blob/master/tlatools/org.lamport.tlatools/src/tla2sany/StandardModules/Naturals.tla).
TLAPS cannot unfold the distributed module's dummy `%` definition to prove
that law. The proof still trusts Swift's primitive `%` behavior and has not
verified that every emitted call or evaluation failure matches the model.
Zero and negative divisors remain separate error/undefined-operation cases;
this lemma does not claim parity for them.

## Choice-expression obligation

The expression-level `StateExpr.choose` is distinct from the nondeterministic
`Choose` algorithm statement. The generated Swift expression sorts its finite
domain and returns the first satisfying member, or throws when none exists;
the TLA+ renderer emits a least-member `CHOOSE` for integer and Boolean
results, but ordinary `CHOOSE` for other result types. Ordinary TLA+ `CHOOSE`
permits an unspecified consistent witness and gives an arbitrary value when
none satisfies the predicate ([Specifying Systems, §16.1.2](https://lamport.azurewebsites.net/tla/book-01-08-21.pdf)).
Therefore the outputs are not generally equal for observable choices of other
accepted types. A sound output link must either emit the same canonical
selection in TLA+ or prove that every accepted use has a unique satisfying
witness and define matching no-witness behavior. Agreement on a finite TLC
run cannot discharge this obligation.

`SingleAssignment.tla` now proves the general unique-witness rule for every
typed domain and Boolean predicate: if exactly one member satisfies
the predicate, TLA+ `CHOOSE` returns that member. This establishes the TLA+
side of the restricted case, not that the compiler proves uniqueness for
accepted uses or that emitted Swift evaluates every predicate identically.
It also proves an observational rule for a nonempty, non-unique choice: if
every satisfying witness has the same observation, Swift's selected witness
and TLA+'s `CHOOSE` witness have that same observation. For a machine-fidelity
claim, that observation must cover the complete state, action, and selected
checking outcomes; the compiler does not establish this premise. A blanket
uniqueness requirement would reject existing formal helpers such as
`KeyValueStoreUtil.ReduceSet`, which deliberately chooses an arbitrary set
member. Those uses need a proof
that their consumers are witness-independent, a shared canonical choice
semantics, or an explicit unsupported-program diagnostic; their presence
cannot be hidden by the unique-witness lemma.

`SortedIntegerFirstIsUniqueLeast` and
`CanonicalIntegerChoiceMatchesSortedFirst` prove a constructive rule for
nonempty integer choices: given a strictly increasing enumeration and a first
satisfying index, TLA+ selection of the least satisfying integer returns the
same member. The renderer now emits this filtered-set, least-member rule for
integer-valued `CHOOSE` expressions. `IncreasingSelection.tla` is the complete
module emitted from the corresponding `#spec` fixture, and
`TypedSelectionTests.renderedSelectionUsesLeastMember` requires exact equality
with that output. `EmittedIntegerChoiceMatchesSourceWhenDefined` proves its
actual emitted action advances from each position in `0..2` to the least
matching member, matching the generated Swift machine's focused behavior test.
`NativeSortedFirstStepMatchesCanonicalChoice` composes that rule with a
first-matching-step relation for every strictly increasing integer sequence
and typed predicate that has a first match; its result value is exactly the
canonical TLA+ choice value, not just one checked example.
`NativeSortedFirstFailureMatchesCandidateEmptiness` proves the complementary
no-match rule for every integer sequence and typed predicate.
`ReversedIntegerChoiceAtZeroDisagrees` is the negative control: reversing the
ordering selects `3` where the source and emitted rule select `1`.
For this pure, total integer choice, the emitted action now guards `CHOOSE`
with a matching-witness test. At position `3` it has no successor and the
emitted `__SwiftTLAChoiceFailure0` predicate matches the independently stated
source failure. `EmittedIntegerChoiceFailureMatchesSource` and
`EmittedIntegerChoiceCompleteStepWhenReachable` prove the failure and complete
step relation over positions `0..3`;
`NativeIntegerChoiceFailureMatchesEmitted` connects that failure to the
first-match rule. Reversing the failure predicate is a negative control. The
focused generated Swift test confirms the matching
`noSatisfyingChoice` failure without changing state. This is an output-linked
finite slice, not a general compiler theorem. The generated TLC configuration
selects the failure predicate through an intrinsic invariant; the independent
checker comparison does not yet match that violation to the native typed failure.

`GeneratedSelectionProofTests` also token-checks the complete emitted Swift
`_visitUpdates0` function against `GeneratedSelectionSwiftWitness.txt`,
normalizing only the source-location-derived choice binder identifier. The checked
function sorts `{1, 2, 3}` ascending, selects the first member greater than
the current position, and merges that value into the complete update. The
generic least-member theorem covers the choice rule; interpreting the emitted
Swift call, `choose` helper, and update merge retains their ordinary Swift
semantics as a trusted boundary. This check does not establish the generator's
behavior for arbitrary choices or binders.

Authored PlusCal carries the same
failure predicate declaration and guards the `with` that evaluates this choice
with the same definedness predicate used by direct TLA+. A focused output test
checks that the guard precedes evaluation. The translated PlusCal action and
checking outcome are not yet proved by this source-level guard. For integer
`CHOOSE` nested in a straight-line addition tree with total choice operands,
the renderer now emits ordered choice and overflow guards. Two focused
`#spec` regressions check a missing nested witness and a successful witness
followed by addition overflow against the generated Swift machine and TLA+
failure declarations. This is tested behavior, not an output-linked TLAPS
proof or independent TLC outcome comparison. Choice nested under other
expression operations, effectful or fallible operands, other value orders,
and general generated Swift semantics remain uncovered.

`BooleanSelection.tla` is likewise the complete emitted module for a
non-unique Boolean choice. `TypedSelectionTests.booleanSelectionUsesLeastMember`
checks that the authored Boolean domain and predicate lower to the compiled
choice operation, then checks the actual generated Swift transition and exact
TLA+ output;
`GeneratedSelectionProofTests` token-checks the emitted closed-choice cache and
complete update function against `GeneratedBooleanSelectionSwiftWitness.txt`.
That witness sorts `FALSE` before `TRUE`, reads the cached selection, and
merges the flag and control-location writes. The interpretation of Swift's
`Result`, `_NativeMachineOperations.choose`, and update merging remains a
trusted runtime boundary, not a TLAPS theorem.
`BooleanSelectionProof.tla` now isolates the source, compiled, and exact emitted
Boolean rules from the unrelated Int64 proof. Its compositional obligation
compares complete initial states, full `Next`, the `select` and internal
`Terminating` labeled steps, and
the empty failure outcome and passing generated evaluation check. Its
reversed-order theorem is a negative control:
choosing `TRUE` would change the emitted step. CI checks this module separately,
and the frozen diagnostic on SHA `337c76cf` [proved all 37 obligations](https://github.com/RoyalPineapple/SwiftTLA/actions/runs/38134117416/job/114454364613).
This is one concrete nonempty Boolean output pair, not a proof for every Boolean predicate or generated Swift expression;
its guarded output is pinned, but general no-match and predicate-evaluation
failures remain uncovered.

Typed `Select` now carries its integer or Boolean result type through source
lowering, so `spec.compile().render()` uses the same least-member rule as the
generated model export. Focused tests compare the two complete TLA modules for
`IncreasingSelection` and `BooleanSelection`, normalizing only binder names
derived from different source locations. The earlier direct-render mismatch is
closed for these two shapes. Other accepted selection value types still need
an explicit shared ordering rule and output-link proof; these tests do not
establish universal choice fidelity or prove either emitter correct.

For a repeatable String selection with no matching member,
`TypedSelectionTests.missingStringSelectionHasMatchingFailure` checks the
generated machine's transactional `noSatisfyingChoice` failure and the rendered
TLA+ output against the complete `MissingStringSelection.tla` proof input,
normalizing only the source-location-derived binder name.
`GeneratedSelectionProofTests` also pins the emitted closed-choice cache and
complete `_visitUpdates0` function to
`GeneratedMissingStringSelectionSwiftWitness.txt`. The test failed on the
previous renderer, which guarded only integer and Boolean choices.
`MissingStringSelectionProof.tla` states source, compiled, and emitted initial
states, complete labeled steps, no-match failure, and evaluation check, with a
missing-check negative control. All 47 obligations passed locally; hosted
evidence is pending. The interpretation of the emitted Swift `Result`, `choose`, and
update merge remains a trusted runtime boundary. This is not a solution to
non-unique String choice: the generated Swift machine still takes the first
ordered member while rendered TLA+ uses unrestricted `CHOOSE` for that type.
The chosen rule for this gap is a shared canonical order for every accepted
selection type, emitted on both sides. It remains unimplemented until the
ordering is defined for every value family, both outputs use it, and an
output-linked proof checks observable non-unique choices.

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
compiled and generated Swift enumerators now also discard that conflicting
branch. `ConjunctionSuccessorsAgree` proves that this executable merge-or-skip
rule and the rendered conjunction have identical complete-state successors
for both compatible and conflicting writes. `ConjunctionEnablednessAgree`
derives matching enabledness from those complete successor relations.
`ConjunctionLabeledEdgesAgree` lifts the rule to complete labeled graphs when
both partial update maps are total functions of the complete source state. It
does not prove emitted Swift or TLA+ expressions denote those maps. The general
output links remain to be proved. Removing the merge-compatibility
guard in a local negative control made the successor theorem fail; restoring
it restored all obligations.

`ExactStateCorrespondence` through `EveryMappedTargetRunLifts` give a generic
observation layer for complete state-labeled/action-labeled graphs.
`PointwiseStateEncodingIsInjective` proves that an injective value encoding
lifts to an injective encoding of complete states with the same variable keys.
`PerFieldStateEncodingIsInjective` extends this to the generated machine's
heterogeneous state shape: each field may have its own value domain and
encoding, provided that encoding is injective on that field's domain. TLAPS
proves that distinct complete typed states then remain distinct after
projection. The compiler has not yet established the premise for every
emitted field encoder, nor has the emitted projection been machine-checked.
`ScopedControlNamingIsInjective` proves that duplicate source labels remain
distinct when their replacement names are injective and disjoint from every
source label. The compiled layout allocates replacement names for colliding
control locations. Compilation now rejects a layout whose final formal names
are not injective, before either output can use it; this checks the theorem's
required conclusion on each accepted layout, without assuming the allocation
loop is correct. A generated-machine regression checks one pair of same-named
procedure steps. The Swift check and the use of these names in every emitted
projection are not themselves machine-checked, so the general output link
remains open.
`InjectiveSetEncoding` proves that an injective element encoding maps distinct
sets to distinct encoded sets, without assuming a finite domain.
`InjectiveSequenceEncoding` proves the corresponding rule for every finite
sequence: elementwise encoding preserves length, order, repeated values, and
sequence identity. The generated-machine array regression checks the emitted
projection for both empty and repeated input. This is a concrete output
witness, not a proof that every emitted element encoder is injective.
`InjectiveActionCallEncoding` proves that an injective action-name mapping and
injective argument encoding preserve the identity of a structured action call,
including argument order and repeated arguments. The generated-machine typed
action-parameter regression checks emitted `FormalActionCall` values for
concrete steps. The compiler has not yet proved that every emitted action name
and argument encoder satisfies the theorem's premises, nor that every emitted
TLA+ action uses exactly that call.
`InjectiveFunctionGraphEncoding` proves that injective key and value encodings
preserve every partial function's domain and values through its graph of
key/value pairs. A generated-machine regression checks one emitted dictionary
projection with two distinct keys. The theorem does not verify that every
emitted dictionary conversion constructs exactly this graph.
`DisjointUntaggedUnionEncodingIsInjective` proves that erasing a union's branch
tag preserves identity when each branch encoding is injective and their images
are disjoint. The generated projection does erase that tag, and type resolution
rejects overlapping alternatives, but these theorems do not prove that the
actual emitted encodings satisfy their premises.
Generated set projection now rejects a collision when its formal set has fewer
members than the native set. The missing proof link is that, for every finite
source set, equality of those cardinalities is equivalent to injectivity of
the emitted element encoding on that set. The guard prevents a silent lossy
result; it does not establish that all accepted models project successfully.
It also cannot distinguish two singleton native sets whose different elements
have the same formal encoding: each set passes the guard separately. Complete
state identity therefore needs injectivity across the whole accepted element
type, not only within one projected set. Macro collection rejects duplicate
enum encodings, and type resolution rejects overlapping untagged union
alternatives, but the emitted projection's every type case is not yet linked
to those checks and the injectivity theorems.
If state and action encodings are injective and the target initial set and
edge relation are their exact images, they preserve initial membership,
labeled edges, default deadlock, nonstuttering enabledness, mapped infinite
runs, and weak/strong fairness observations on those runs. The run definitions
permit stuttering;
action occurrence requires a changing state, as TLA+'s `<<A>>_vars` does.
Default deadlock instead asks whether any explicit labeled edge exists, so an
explicit self-loop is outgoing while implicit temporal stuttering is not.
The reverse theorem proves that every valid target run from the mapped initial
set remains in the state image and lifts to a valid source run. These theorems
also preserve invariant and reachability observations along mapped runs when
the source and target claim predicates agree at every corresponding state.
They do not prove that compiler outputs meet these graph and claim premises
or that the abstract run formulas implement every emitted `WF_`/`SF_` form.
Those output and temporal links remain required.

`EveryConcreteRunRefines` covers the distinct, one-way refinement case. A
state projection may be non-injective: if it maps concrete initial states into
abstract initial states and every concrete labeled edge projects to either an
abstract edge or a stutter, then every concrete infinite run projects to a
valid abstract run. This does not establish the edge/initial premises for an
emitted refinement declaration, nor does it preserve fairness automatically.
`WeakFairnessSurvivesRefinement` and `StrongFairnessSurvivesRefinement` add the
separate fairness premises: whenever the abstract action is enabled, its
concrete counterpart is enabled, and every changing concrete occurrence maps
to a changing abstract occurrence. Under those premises, concrete fairness
implies abstract fairness even for a non-injective state projection. Compiler
refinement exports must still establish these premises for their actual
actions and mappings.

`InitialMembershipMatchesEnumeration` proves that one native initializer's
candidate sequence produces exactly the complete states admitted by a TLA+
membership clause when the sequence contains precisely the declared domain.
`InitialMembershipComposesAcrossPriorChoices` permits that domain to depend on
each previously selected state, including an empty domain.
`InitialEqualityMatchesSingletonEnumeration` covers a deterministic initializer:
one native candidate admits exactly the complete states described by TLA+
equality. `DependentDeterministicInitializationComposes` applies that equality
to every prior state, so the value may depend on earlier initialization choices.
`OrderedInitialHistoriesAgree` extends the equality to every position in any
finite ordered initialization plan. `OrderedInitialHistoriesExist` constructs a
shared history for every such plan, so the equality is not vacuous. These are
generic initialization rules; they do not yet prove that the actual initializer
expressions, generated Swift loops, and rendered `Init` satisfy the candidate
equality premise for every accepted `#spec`.

`DependentInitializationOutputProofModel.tla` is an exact generated module for
a `#spec` whose second variable's candidate set depends on the first variable's
choice. `DependentInitializationOutputProofTests` pins the complete emitted TLA
text and observes the generated Swift machine's three initial states.
`EmittedDependentInitializationMatchesSource` proves the imported `Init`
equivalent to an independently stated source relation, and
`EmittedDependentInitializationHasExactlyThreeStates` proves that complete
initial-state set. This connects one actual output pair to the generic rule's
intended behavior; it does not establish the candidate-set premise or generated
Swift output semantics for arbitrary accepted models.

The TLA renderer prints action conjunction as `/\`. TLC must solve primed
assignments as an action relation; making one such assignment the condition of
an `IF` caused generated models to fail during exploration. The native machine
still evaluates ordered statements left-first. `LazyConjunctionPreservesBooleanValue`
applies to total Boolean state expressions, not to TLC's execution of action
formulas. Evaluation-failure order and the general action output link remain
unproved.

The guarded-choice composition rule preserves complete labeled edges and
enabledness for any choice domain, provided corresponding branches produce
equal edge sets and both outputs use the same guard and domain. These premises
are not yet discharged for arbitrary compiler input. The rule is a reusable
induction step, not proof that the current Swift emitter satisfies it.

The existential-action rule now proves that iterating a state-dependent finite
candidate sequence and existentially quantifying over a separately supplied
domain produce the same complete labeled edge set and enabledness, provided
their member sets and each corresponding branch's edge set agree. It permits
duplicate candidates because graph edges have set semantics. The compiler has
not yet established those premises for the emitted Swift and TLA+ expressions;
evaluation failures and checking-register/`PrintT` effect order also remain
open.

The `define` rule proves that a native eager binding and a TLA+ `LET` binding
preserve complete labeled edges and enabledness when both evaluate to the same
total, effect-free value and their selected branch edge sets agree. The
emitted `GeneratedGuardedChoiceProofModel` contains a concrete `LET` and its
action is separately proved equivalent to the stated source relation. Neither
fact establishes those value and branch premises for arbitrary emitted code;
undefined expressions and checking effects remain outside this rule.

The conditional-action rule selects a branch by a Boolean predicate of the
complete source state. TLAPS proves that equal source/rendered predicates and
branch edge sets yield equal complete labeled edges, and that the conditional
is enabled exactly when its selected branch is enabled. This supplies a
compositional `ifElse` step, not a proof that the compiler preserves the
predicate or that both emitters implement each branch. The repeated-write
guard proof was split into the initial guard and the remaining positions so
the full module checks without relying on prover search over one large step.

The state-expression renderer now emits a Boolean conjunction as
`IF left THEN right ELSE FALSE`, matching the generated Swift machine's
left-first short circuit. TLAPS proves this form has the same truth value as
`left /\ right` for total Boolean operands. The existing enabledness fixture
tests the actual generated TLA+ form and native skipped-right-operand behavior.
The [TLC tools documentation](https://github.com/tlaplus/tlaplus/blob/master/general/docs/current-tools.md)
also states that an unselected `IF` branch is not evaluated.
This does not yet prove arbitrary emitted predicate evaluation or a general
correspondence for evaluation failures and checking effects.

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
placed at history index `Len(prefix)`. TLAPS proves that restricting a full
source history to that index yields a valid prefix history, and uniqueness
then establishes that the guard reads exactly the state produced by the
prefix. It also proves source and scheduled transition relations,
enabledness, and labeled edges equal for every such plan and pure total
predicate. Conditional expression evaluation, algorithm lowering, and the
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
small `#spec` model. `GeneratedAtomicUpdateProofTests` checks that parsing and
lowering that actual source produces two ordered `define` captures: the first
reads `second`, the second reads the first capture, and the complete action
assigns those captures to `first` and `second` with a true guard. This is a
fixture-specific compiled-output link, not a proof of the general `Do` lowerer.
The test also requires byte-for-byte
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

The same test pins five actual generated Swift members—`State`, `Snapshot`,
formal projection tokens and values, and action identity—to
`GeneratedAtomicCopySwiftWitness.txt`. It checks the full emitted
`_initialStates` body against a restricted two-field Swift pattern, extracts
its two literals, and requires the values used by the formal initial-state
theorem. Mutating the selected-state guard to inspect the wrong field makes
this check fail. This establishes the private `_initialStates` output link for
this fixture conditional on the ordinary Swift meaning of the matched literals,
optionals, comparisons, nested `if` statements, append, return, and the pinned
`State`/`Snapshot` constructors. It does not certify arbitrary initializers or
public machine construction. The test also token-checks the complete emitted
`_Updates`, `_visitUpdates0`, `_visitSuccessors0`, the action-specific and
whole-machine `_visitSuccessors` dispatchers, and the public checking visitor
against `GeneratedAtomicCopySwiftTemplate.txt`, extracting the source field read by
the ordered copy. Its field and update-slot bindings are checked consistently
across those declarations; a second `#spec` fixture with renamed fields
passes the same template. Changing the read changes the extracted obligation;
a wrong target merge or a false `found` result makes the template check fail.
The global visitor forwards the single `copy` action to the proved private
successor path, and an executable check confirms that dispatch from the initial
state. Under the ordinary Swift meaning of the matched callback, optional-merge,
state-construction, and
deduplication syntax, this links the checking visitor to the relation proved
below. It does not yet certify public machine construction, the runtime behavior
of pinned `State`/`Snapshot` declarations, or macro installation.
`GeneratedDisjointWritesPreserveCompleteState` proves a model of the emitted
update merge and apply path for any two distinct state fields, including
successful accumulation and complete-state replacement.
`GeneratedCopyMatchesEmittedTLA` specializes that path to the generated
callback chain: the second write uses the first captured read, and its complete
transition relation equals the emitted TLA `copy` action. The token template
checks the actual Swift checking path against this modeled callback chain;
its interpretation of those Swift constructs remains a stated trusted boundary,
not a theorem about the Swift compiler/runtime. The template currently covers
this two-field, integer, ordered-copy rule, not all eight action constructors.
`GeneratedCopyLabeledStepMatchesSource` carries the emitted action label through
that relation for every typed source and target state.
`GeneratedCopyInitialsMatchSourcePredicate` proves both unfiltered
initialization and filtering by a selected complete initial state against the
source-state predicate. `GeneratedCopyInitialMembershipMatchesActualInit`
composes that set result with the actual emitted TLA `Init` predicate for every
typed pair of integer variables. The projection theorem
proves that both formal fields preserve every typed value, and the token
declaration is pinned to their actual TLA names. The copy-step theorem covers
every typed source and target state, not only the test's concrete step.
The pinned `State` and `Snapshot` declarations, global action dispatch, and
macro installation are not yet semantically certified by this slice.
`PreStepSecondReadIsObservable` is a machine-checked negative witness: at
`(first, second) = (0, 1)`, reading the pre-step `first` for the second write
produces `(1, 0)`, which the emitted TLA action rejects. The generated-machine
test independently requires `(1, 1)` for that state; neither finite check
establishes the universal Swift output link.

The `OrderedCopyModel` test requires the complete generated TLA+ module,
after replacing only its Swift `Int` bounds with symbolic constants, to match
`OrderedCopy.tla` byte-for-byte. The generated-machine test exercises the same
two action steps. `SingleAssignment.tla` states source-to-emitted claims for
`Init`, both ordered actions, termination, complete `Next`, reachable-state
invariants, temporal behavior, and a complete-state relation. The indexed
guarded-history theorem also links the second action to the scheduled source
history. A direct theorem about TLA+'s `ENABLED` remains unavailable in the
[pinned TLAPS proof system](https://proofs.tlapl.us/doc/web/content/Documentation/Unsupported_features.html).
The current local `--nofp` run proved all 1,423 obligations in
`SingleAssignment.tla`. `SmallAdditionFitsSwiftInt` supplies the ordered
bound fact; an explicit nonempty-candidate witness closes singleton integer
selection; exposing the existing `OrderedAddDefined` definition closes
guarded-history function typing. This proves this module's stated obligations
under its declared assumptions, not universal preservation of the compiler's
actual Swift and TLA+/PlusCal outputs. Hosted proof evidence is still pending.
Trying `BY Isa` for the two bound steps made this pinned TLAPS build stack
overflow while printing an Isabelle sequent, before it could report obligations;
those proof-step changes were reverted before the passing `--nofp` run.
Changing only the second abstract increment from `+ 1` to `+ 2` failed the
history obligation in an earlier negative control; that result does not prove
arbitrary compiler output.

`GeneratedGuardedChoiceProofModel.tla` is a second complete emitted module,
checked byte-for-byte against its `#spec` fixture. Its generated Swift machine
has exactly two successors from the initial state and disables the action in
both successors. `SingleAssignment.tla` separately states the source guard and
the two permitted next values, then proves equivalence with the emitted
`Init`, `choose`, and `Next` definitions and proves disabledness after a choice.
Widening the emitted choice domain from `1..2` to `1..3` made the action proof
fail; restoring it restored the proof. This is a second output-linked case,
not a general proof of guarded choice or of the Swift emitter.

`ConditionalStepProofModel.tla` is the complete output from a `#spec` step
that flips a Boolean before an `If`/`else` assignment in the same atomic
`Do`, with sequential weak fairness. The fixture test pins those bytes,
including `WF_<<pc, chooseFirst, value>>(Next)`, and checks that the generated
Swift machine selects the branch from the updated value for both initial
Boolean values. `GeneratedConditionalStepSwiftWitness.txt` now pins the actual
emitted `_visitUpdates0` token stream: both paths compute `!chooseFirst`, use
opposite guards, and merge the selected Boolean, value, and control-location
updates. Inverting the true-branch guard is rejected by the output check.
`ConditionalStep.tla` separately proves that the emitted initial
states, both conditional branches, terminating action, and `Next` match
independently stated source relations over Boolean condition states. It also
states the compiled conditional as an explicit two-branch relation and proves
its complete initial states and `Next` agree with the source before connecting
the emitted TLA+ action. `ConditionalStepProofTests.compiledConditionalBranches`
checks the actual compiled runtime's two initial states, labeled successor,
prior-write branch selection, and disabledness after the step. A reversed
compiled branch is a TLAPS negative control. The local proof passed all 203
obligations, and the focused suite passed all three tests; this revision has
not yet been hosted.
The module also proves the generated temporal `Spec` equivalent to the source
temporal spec conjoined with weak fairness on the source step, under a
reachable-state type invariant. It proves that the complete state relation has
a successor for every typed state. Direct `ENABLED` theorems establish that
the emitted `choose` and `Next` actions agree with the source relations on
enabledness and deadlock for typed states. It covers one emitted
conditional with a prior write, not arbitrary conditions, expression failures,
or the Swift emitter rule for arbitrary compiled programs. The Swift-output
check is a fixture-specific link, not a machine-checked Swift semantics.

`EmittedConditionalValueRefinement` projects that exact generated module onto
the non-injective value-only abstraction: initial value `0`, at most one
choice of `1` or `2`, and then stuttering. TLAPS proves every behavior of the
emitted `Spec` satisfies this abstract temporal specification, using a
reachable-state invariant that the choice location still has value `0` and
the done location has value `1` or `2`. `EmittedConditionalFairValueRefinement`
also carries the emitted weak-fairness obligation through that projection, so
the choice cannot stutter forever at `0`.
This is one output-linked one-way refinement witness; it does not certify an
arbitrary emitted `Refinement` mapping or its abstract module.

TLAPS expands TLA+'s `WF_vars` and `SF_vars` operators and proves that weak
fairness on the emitted `Next` equals weak fairness on the source `choose`:
the additional emitted `Terminating` action only stutters. The exact rendered
`Spec` therefore carries the declared weak fairness. A separate theorem
covers strong fairness if conjoined to that `Spec`; strong fairness is not
declared by this fixture. The proof uses action and enabledness equality under
the reachable-state type invariant. It does not verify generated Swift
fairness callbacks or every fairness scope supported by the DSL.

Before the checked-overflow edits, TLAPS 1.6.0-pre checked all 1333
`SingleAssignment.tla` obligations and all 192 `ConditionalStep.tla`
obligations locally with fingerprint reuse disabled. The
arm64 TLAPS archive had SHA-256
`fe2ac4b0e4bfd7fa038a9857be8a56e4521a1e3b3ec41c9a80b01fa390de3987`;
its bundled Z3 was x86-only, so the check used arm64 Z3 4.15.4 with archive
SHA-256 `8bb3439772cafd75240d61abf255e89122850bab93563d1283b048359ab4e88f`.
This is historical local diagnostic evidence, not proof of the current worktree
or hosted admission. The generic lemmas
do not yet prove expression evaluation or compiler lowering. The imported
fixtures connect actual TLA outputs, but the general TLA-emitter and
generated-Swift output links remain mandatory.

Ordinary CI now defines a separate `semantic-proof-diagnostic` job. It verifies
the official Linux TLAPS archive against SHA-256
`13eff4e3dd0a4570c1c33c46f052fd4eb3afad465eb201ebade607961f09d43c`,
replaces only its bundled Z3 with official Linux Z3 4.15.4 pinned to SHA-256
`a41b690e89c343931471506cdc6d957b6044a200fd2d240cc017432afdff7d3e`,
checks the declared proof modules,
without fingerprint reuse, and retains the exact
source SHA, TLA and Swift-witness input digests, tool versions/configuration, and separate
proof logs. A changed archive fails its checksum. The revised
`CheckedExecutionOverflowProof.tla`, `CheckedSubtractionProof.tla`,
`CheckedMultiplicationProof.tla`, `CheckedGuardFailureProof.tla`,
`MissingStringSelectionProof.tla`, and `SingleAssignment.tla` have passed
locally on the current side-worktree inputs. None has qualifying hosted
evidence. This job
does not yet have qualifying hosted evidence and is not the universal
semantic-preservation admission check.
The ordered two-addition regression passes focused Swift tests and its symbolic
TLA fixture is required to match normalized renderer output. Its revised
`SingleAssignment.tla` proof passed locally, but has not been hosted. On SHA
`337c76cf`, the pinned TLAPS job reported five
Zenon search exhaustions and then stack-overflowed in `Zenon.fmt_expr` while
processing that module; it did not produce a proved-obligation total or identify
one failed theorem. The same job proved all 192 `ConditionalStep.tla`
obligations, but failed three of six obligations in the former
`Int64LiteralArithmetic.tla` and five of
41 `CheckedExecutionOverflowProof.tla` obligations at the known full-width
literal boundary. The [retained diagnostic artifact](https://github.com/RoyalPineapple/SwiftTLA/actions/runs/38134117416/artifacts/11700481152)
is evidence for these scoped results, not universal semantic admission. Neither
test result establishes the ordered failure theorem.
The older hosted run at `e77f1689` passed its diagnostic job and retained
logs for 931 and 192 obligations respectively; those inputs precede the
current lemmas and do not qualify this revision.

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
The generated export records its macro-time `CompilationIdentity` as bundle
provenance, and compiled-state consumers use identities to reject mixed
compilations. The generated machine does not recompile its source at runtime.
That identity neither validates the emitted Swift transition bodies nor proves
that they agree with the embedded TLA+ text. The output link must inspect or
verify the emitted code itself.

| Action-tree rule | Current machine-checked fact | Output obligation still open |
| --- | --- | --- |
| `assign`, `unchanged` | Complete-state delta and unchanged-frame equality | Prove each emitted Swift update and TLA clause denotes that delta for every compiled expression and state type. |
| `guard_` | Pure, total guards agree at each abstract ordered-statement position | Prove emitted predicate evaluation, disabledness, short-circuit failures, and source `When` substitution. |
| `and` | Compatible delta conjunction and conflicting relational writes | Prove both emitters' evaluation order, conflict/error semantics, and frame completion. |
| `or` | Guarded-choice preservation conditional on equal branch edges | Prove branch construction, multiplicity policy, and failure behavior in both outputs. |
| `existsAction` | Enumeration versus existential quantification preserves complete labeled edges and enabledness for the same state-dependent candidate values and pure branch edges | Prove the actual emitted domain and branch expressions agree, including failures and checking effects. |
| `define` | Equal total bound values and selected branch edges preserve complete labeled edges and enabledness across eager binding and `LET` | Prove emitted value/branch expressions, failure behavior, and checking effects. |
| `ifElse` | Equal pure source/rendered predicates and branch edges preserve complete labeled edges and enabledness | Prove emitted condition evaluation, failure behavior, and both branch forms. |

This table is a proof inventory, not a claim that these seven groups exhaust
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
