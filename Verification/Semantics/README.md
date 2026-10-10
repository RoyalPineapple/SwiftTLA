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
Rendered TLA+ currently uses mathematical integers, so it does not yet obey
this source rule.
Using TLC's operational `Assert` failure alone would not establish this
agreement: the [standard TLA+ definition of `Assert`](https://github.com/tlaplus/tlaplus/blob/master/tlatools/org.lamport.tlatools/src/tla2sany/StandardModules/TLC.tla)
does not define a matching mathematical error outcome. The failure must be
represented in the semantics of both outputs, or the program must carry a
proved range obligation.

This matched-failure rule is **not implemented**. `CheckedExecutionOverflow` in
`NativeExecutionBoundaryTests` is a concrete accepted counterexample: its
`count + 1` step starts at `Int.max`, so the generated machine throws while
the rendered TLA+ arithmetic has a successor. Until the gate and both output
links are proved, the universal theorem does not hold for accepted `#spec`.
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
same member. The renderer still emits ordinary `CHOOSE`, not this canonical
operator. The proof does not cover empty domains, predicate evaluation
failures, or the ordering of other value types.

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
`_Updates`, `_visitUpdates0`, and `_visitSuccessors0` declarations against
`GeneratedAtomicCopySwiftTemplate.txt`, extracting the source field read by
the ordered copy. Changing that read changes the extracted obligation; a
wrong target merge makes the template check fail. Under the ordinary Swift
meaning of the matched callback, optional-merge, state-construction, and
deduplication syntax, this links the private successor path to the relation
proved below. It does not yet certify global action dispatch, the runtime
behavior of pinned `State`/`Snapshot` declarations, or macro installation.
`GeneratedDisjointWritesPreserveCompleteState` proves a model of the emitted
update merge and apply path for any two distinct state fields, including
successful accumulation and complete-state replacement.
`GeneratedCopyMatchesEmittedTLA` specializes that path to the generated
callback chain: the second write uses the first captured read, and its complete
transition relation equals the emitted TLA `copy` action. The token template
checks the actual private Swift output against this modeled callback path;
its interpretation of those Swift constructs remains a stated trusted boundary,
not a theorem about the Swift compiler/runtime.
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
The emitted-spec invariant now fixes every reachable state to
`(pc, x, y) = (copy, 1, 0)`, `(repeatWrites, 2, 2)`, or `(Done, 4, 2)`.
TLAPS proves that both action bodies' intermediate additions stay within
any Swift `Int` range containing `0...4`. This closes overflow for this
fixture's reachable steps, not for the unbounded `Int` states used by the
relational no-deadlock theorem or for arbitrary accepted programs.
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

`ConditionalStepProofModel.tla` is the complete output from a `#spec` step
that flips a Boolean before an `If`/`else` assignment in the same atomic
`Do`, with sequential weak fairness. The fixture test pins those bytes,
including `WF_<<pc, chooseFirst, value>>(Next)`, and checks that the generated
Swift machine selects the branch from the updated value for both initial
Boolean values. `ConditionalStep.tla` separately proves that the emitted initial
states, both conditional branches, terminating action, and `Next` match
independently stated source relations over Boolean condition states. It also
proves the generated temporal `Spec` equivalent to the source temporal spec
conjoined with weak fairness on the source step, under a reachable-state type
invariant. It proves that the complete state relation has a successor for
every typed state. Direct `ENABLED` theorems also establish that the emitted
`choose` and `Next` actions agree with the source relations on enabledness and
deadlock for typed states. It covers one emitted
conditional with a prior write, not arbitrary conditions, expression failures,
or the Swift emitter for all states.

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

TLAPS 1.6.0-pre checked all 1163 `SingleAssignment.tla` obligations and all 192
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
