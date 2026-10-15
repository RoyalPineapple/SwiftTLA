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
about the target Swift `Int`, not TLAPS-proved numeric facts. The prior
`SingleAssignment.tla` revision's 1,423 obligations passed locally with
fingerprint reuse disabled. The later selected-initialization theorem steps
pass focused TLAPS checks; a complete proof run of this revision and hosted
evidence remain pending.
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
these obligations using the full-width emitted integer bounds, the test requires
a byte-for-byte match between that module after replacing only its module name,
both emitted bound expressions, and the constant declaration, and the
`CheckedExecutionOverflowSymbolic.tla` module imported by the proof. The proof
assumes integer bounds enclosing the renderer's fast path; the test ties the
symbolic constants to the emitted exact minimum and maximum expressions. This
normalization and the target Swift `Int` contract are trusted links, not TLAPS
theorems. The renderer splits large integers into arithmetic over small decimal
literals. This preserves their TLA+ value, but [TLC cannot evaluate naturals
above 2^31 - 1](https://github.com/tlaplus/tlaplus/blob/master/general/docs/current-tools.md).
TLC graph parity therefore cannot establish full-width overflow behavior;
symbolic proof and native execution remain separate evidence for that boundary.
`SingleAssignment.tla` separately proves the generic addition guard.

The checked-summation regression exercises one accepted `#spec` model whose
finite, explicit set selects three function values totaling `Int.max + 2`,
including a repeated value.
Before the renderer change, the generated Swift machine reported `summation`
overflow while the generated TLA+ module had no matching failure declaration.
The focused test now requires the native failure with all three operands,
the rendered range guard, the `summation` operation identity, and a ranked
operand expression based on source-member counts. This is an output-linked
regression, not a generic proof of `Sum`: the order reconstruction, dynamic or
fallible domains such as `IntRange`,
function arguments outside the function domain, and the imported fold's
mathematical result remain separate obligations. TLC's 32-bit arithmetic
cannot certify this full-width witness. No universal summation-fidelity claim
depends on this test alone.

The checked-execution focused test checks the complete
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
`CheckedGuardOverflowProof.tla` now supplies a separate exact-output instance:
the focused test pins the complete generated TLA+ module and the generated Swift
update function's tokens, including its call to the shared checked-addition
operation and the guard before update emission. TLAPS proves that module's
initial states, complete labeled transitions, overflow failure and operands,
and selected evaluation check match the independent source rule for every
state in the signed-`Int` domain. The proof also establishes that this domain
contains every initial state and is preserved by every `Next` step; an unguarded
action is a negative control. All 14 obligations pass locally. This does not
prove every accepted `When` or independently verify macro expansion and the
Swift compiler/runtime interpretation of the pinned source.
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
`\div` operator. The output link is still incomplete: `Int.min / -1`, actual
target integer bounds, and general evaluation-failure order still need
matching outcome proofs. The emitted failure checks now guard division by zero
and negative modulo divisors in Swift evaluation order; the generated-output
tests pin those guards, and `OrderedArithmeticFailures.tla` proves the first
division failure masks every later failure and distinguishes the two modulo
failure verdicts. It also proves that the emitted conditional division-overflow
guard matches the source rule for every integer operand, with a reversed-guard
negative control. The actual rendered-output test pins the conditional: TLC
must not evaluate Swift's 64-bit minimum for a divisor other than `-1`.
That proof covers the ordered failure boundary, not all nested expressions or
the complete generated machine. TLC's bounded integer evaluator still cannot
validate the full Swift `Int` range; it may overflow while evaluating an
intermediate expression valid in mathematical TLA+.

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
unchanged state, then pins the emitted TLA+ first-failure rule and guards on
every later failure. The adjacent negative-modulo test pins the matching
verdict on both outputs. These are concrete output regressions, not a proof
of failure order for every accepted expression.

`SignedIntegerSemanticsTests.generatedMembershipFailureOrder` closes the same
right-first failure boundary when the outer operation is membership and its
set is a computed literal: a division failure in the set precedes an overflow
in the member. It failed before the renderer traversed membership and set
literal children, then passed with the emitted first-failure, later-overflow,
and action guards pinned. `OrderedArithmeticFailures.tla` proves the two-site
failure outcome for every integer divisor and Boolean later-overflow outcome.
The proof assumes the generated Swift machine evaluates the set first, as the
fixture test observes; it does not prove every collection expression or the
authored PlusCal output link.

`SignedIntegerSemanticsTests.generatedTupleFailureOrder` checks the same
two-site outcome for an ordered sequence literal. The first element divides
by zero before the second can overflow; the generated Swift machine reports
that failure without changing state, and the generated TLA+ action and check
now guard both sites in that order. The same fixture separately checks an
overflow-only sequence, which uses the ordinary arithmetic guard path. The
pre-fix test failed because the TLA+ output omitted the ordered guards.
`MembershipFailureOrderMatchesForEveryDivisor`
proves the shared first-site/second-site outcome equation, while
`ReversingFailureOrderChangesTheObservedOutcome` is its negative control.
The test links that equation to this emitted sequence instance, not every
accepted aggregate or the Swift emitter as a whole.

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

## Formal value identity boundary

Formal and compiled String values now use byte-exact equality and a matching
total order in sets, function keys, records, and state values. The focused
`FormalValueEqualityTests` regression failed before the change: precomposed
`"\u{00E9}"` and decomposed `"e\u{301}"` collapsed to one member under Swift's
ordinary `String` equality. It now checks both values remain distinct and
record-field lookup does not conflate their names. Typed Swift `String` inputs
take a separate canonical-form conversion at the authoring/parser boundary and
at generated-machine formal projection. `FormalStringRenderingTests` and
`SpecVariableDeclarationParsingTests` exercise the input conversion;
`SwiftStringFormalEncodingTests` checks one actual generated Swift transition,
its complete projected String value, and the emitted TLA+ literal. The local
`string-literals` reference fixture uses the canonical value accordingly.
Decoding an explicitly raw formal string back to Swift retains its original
scalars; the conversion does not rewrite data on that reverse path.

These are executable boundary checks, not a TLAPS proof of Unicode
normalization or all emitted String operations. The link assumes Swift String
equality and Foundation's canonical normalization agree on the same Unicode
version. Raw imported TLA+ values remain byte-exact, so an accepted imported
String operation that reaches generated Swift still needs a separate output
link. The closed canonical-Unicode choice below is an output-linked candidate
with local TLAPS proof but no hosted admission;
dynamic String-valued `CHOOSE` and arbitrary Unicode String programs remain
outside the fidelity theorem until those links and TLC's Unicode handling are
established.
The [open TLC Unicode-state issue](https://github.com/tlaplus/tlaplus/issues/1076)
reports that distinct non-ASCII strings can share a state fingerprint and that
disk serialization can corrupt them. Our pinned TLC v1.8.0 revision predates
the October 2026 report. Raw non-ASCII String states therefore cannot qualify as
independent TLC parity evidence until the pinned checker is repaired or the
formal representation is made safe; a passing local Unicode fixture or TLAPS
proof does not establish TLC's state exploration is complete.
TLC-backed validation rejects non-ASCII text outside TLA+ comments in every
declared module and configuration before launch and before computing a
reusable oracle key. Unicode in comments cannot become a state string; the
guard still rejects Unicode inside string literals, including text that looks
like a comment. The current local candidate renders non-ASCII formal string
bytes as versioned ASCII hex, escaping any ASCII string that begins with the
reserved prefix.
The emitted module declares that encoding when it contains an encoded literal;
a compiled configuration-only literal also opts its bundle into decoding.
External modules require an explicit declaration. This preserves the complete native
state value rather than treating the ASCII surrogate as its identity. The
text reader and binary TLC bridge both decode, while an unmarked input retains
its literal strings. Focused rendering, binary-identity, and parity checks are
still required; no hosted Unicode graph parity has been established for this
candidate. Imported TLA+ string operations and dynamically constructed strings
can bypass literal encoding and remain outside the universal theorem.

## Choice-expression obligation

The expression-level `StateExpr.choose` is distinct from the nondeterministic
`Choose` algorithm statement. The generated Swift expression sorts its finite
domain and returns the first satisfying member, or throws when none exists;
the TLA+ renderer emits a least-member `CHOOSE` for integer, Boolean,
finite-enum, closed multi-member canonical String domains, closed
literal tuple/sequence domains with exact integer, Boolean, or canonical
String members, and state-held integer- or Boolean-sequence domains. It emits ordinary
`CHOOSE` for other result types. Ordinary
TLA+ `CHOOSE`
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
The reusable rule now quantifies over every Boolean predicate and every complete
`pc`/`flag` state. It proves equality of source case-split, compiled sorted-first,
and TLA+ least-member labeled edge sets, plus the no-match failure set. A
reversed-order rule changes the complete edge, not merely the selected value.
The generated-output test links one instance to actual Swift and TLA+ emissions;
it does not yet certify those emitters for every accepted predicate.
This is one concrete nonempty Boolean output pair, not an output link for
every Boolean predicate or generated Swift expression. Its guarded output is
pinned, but actual no-match and predicate-evaluation paths remain uncovered.

`EnumSelectionProof.tla` proves that the two-case sorted enum rank chooses the
same member as generated Swift for every predicate, with equal labeled edges
and no-match failures. Reversing the rank changes an edge. It also imports the
complete generated `EnumSelection.tla` module and proves its initial state,
`Next`, labeled actions, and passing evaluation check match this source case.
The authored test pins that exact TLA+ module, checks direct rendering and the
actual Swift transition, while `GeneratedSelectionProofTests` pins the emitted
Swift choice cache and complete update function. This is a concrete finite-enum
output link, not a proof for every enum cardinality or every emitted program.
It still trusts Swift's `Result`, `_NativeMachineOperations.choose`, and update
merging; other accepted value families remain uncovered.

Typed `Select` now carries its integer, Boolean, or finite-enum result type
through source lowering, so `spec.compile().render()` uses the same least-member
rule as the generated model export. Focused tests compare the two complete TLA
modules for `IncreasingSelection`, `BooleanSelection`, and `EnumSelection`,
normalizing only binder names derived from different source locations. The
earlier direct-render mismatch is closed for these three shapes. Other accepted
selection value types still need
an explicit shared ordering rule and output-link proof; these tests do not
establish universal choice fidelity or prove either emitter correct.

`StringSelection` closes one more concrete boundary: the authored closed
`{"alpha", "zed"}` domain lowers to a compiled choice, and the generated
Swift machine selects `"alpha"`. Direct compilation represents the domain as
a constant set with an unknown result type, while macro compilation represents
it as a `setLiteral` with a String result type. The renderer accepts both only
after checking every member has canonical formal String identity, then emits the same ranks.
`TypedSelectionTests.stringSelectionUsesLeastMember` requires the two complete
TLA+ outputs to agree and the generated module to equal the proved
`EnumSelection.tla` module after only model/helper and binder renaming.
`EnumSelectionProof.tla` therefore covers this emitted TLA+ instance through
that exact-output, alpha-renaming test; `GeneratedSelectionProofTests` pins the
complete emitted Swift choice cache and update function to
`GeneratedStringSelectionSwiftWitness.txt`. Generated Swift now calls the same
canonical formal String order used by compiled values. Interpreting Swift's
`String` equality and Foundation normalization, `Result`, `choose`, and update
merge remains a trusted runtime boundary.
This link covers the two ASCII literals, not arbitrary or dynamic String
domains, Unicode equivalence, or every accepted compound value type.

`CanonicalUnicodeStringSelection` adds the closed `{"z", "é"}` domain. Its
regression failed before the fix because TLA+ emitted unrestricted `CHOOSE`;
the generated machine already selected `"z"`. The test now checks the
compiled member set, generated machine's selected value, direct and macro
TLA+ outputs, and an exact link to
`CanonicalUnicodeStringSelection.tla`. `GeneratedSelectionProofTests` pins the
complete emitted Swift choice and update function to the shared
`GeneratedStringSelectionSwiftWitness.txt` after replacing only this fixture's
two literal tokens. The accompanying
`CanonicalUnicodeStringSelectionProof.tla` states the complete initial,
labeled-step, failure, and reversed-order obligations. The earlier hosted
diagnostic on [`fa7c7602`](https://github.com/RoyalPineapple/SwiftTLA/actions/runs/38240172815)
left 8 of 22 obligations unproved, starting with the closed-domain choice and
empty-match laws. After replacing the formal literal with the versioned ASCII
representation, all 22 obligations pass locally with TLAPS fingerprint reuse
disabled. The Swift-string-to-formal representation link remains a tested
runtime boundary, and the repaired proof has no hosted evidence yet.
Even a repaired instance would not prove all Unicode values or dynamic String
domains.

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
update merge remains a trusted runtime boundary. The chosen general rule is a
shared canonical order for every accepted selection type, emitted on both
sides. It remains incomplete: outside supported numeric, Boolean, enum, and
closed canonical String and exact literal tuple domains, observable
non-unique choices can still differ.

`SequenceSelection` adds a closed `Set<[Int]>` case with three distinct
sequence values. The earlier macro output used arbitrary `CHOOSE` while direct
compilation ranked the values; after ranking the macro output, its choice
failure guard was still absent because a `tupleLiteral` domain was not
classified as repeatable. The renderer now extracts only literal tuple members
and guards their total choice. `TypedSelectionTests.sequenceSelectionUsesLeastMember`
checks the native state change, direct/macro TLA+ equality, and exact emitted
`SequenceSelection.tla`. `GeneratedSelectionProofTests` checks the complete
emitted Swift choice cache and action-update function against
`GeneratedSequenceSelectionSwiftWitness.txt`.
`SequenceSelectionProof.tla` proves, for every predicate on this three-member
domain, equal complete labeled edges and no-match failures under the native
lexicographic order and rendered rank. Its exact-output theorem covers the
emitted initial state, `Next`, both action labels, and the selected evaluation
check; reversing the rank changes a complete edge. On frozen SHA `12cb66a8`,
hosted TLAPS left the single emitted-`select` equivalence obligation unproved
while the other 15 obligations passed. The side-branch proof now isolates the
exact emitted choice value and its nonempty candidate set before composing
the emitted action; all 20 revised obligations pass locally without fingerprint
reuse. This revision still needs hosted proof evidence. The Swift
compiler/runtime, `Result`, `choose`, array ordering, and update merge remain
trusted. This is one output-linked sequence instance, not a proof for arbitrary
literal lengths, computed domains, nested conversions, or every accepted
compound value type.

`DynamicSequenceSelection` uses a state-held `Set<[Int]>`, which previously
rendered ordinary `CHOOSE` even though generated Swift sorted candidates
lexicographically. The renderer now emits the same first-difference and
proper-prefix order for this value type, while preserving the existing
closed-domain rank path. A focused test pins the complete TLA+ output, and
`GeneratedSelectionProofTests` pins the generated Swift update function's
state read, sorted choice, and complete update. The test failed on the old
renderer because no ordering predicate was emitted.
`DynamicSequenceSelectionProof.tla` proves that the rendered sequence order
matches the three-value Swift rank for every pair, that the ranked and
lexicographic choices agree for every nonempty subset, and that the actual
emitted action preserves complete labeled steps on all reachable states. It
also proves the initial candidate set remains unchanged, the no-match failure
invariant, and a reversed-order negative control. All 32 obligations passed
locally; hosted evidence is pending. The exact output theorem covers this
fixture's fixed reachable candidate set, not arbitrary mutable sets or all
integer sequences. Swift's `lexicographicallyPrecedes`, the generated update
merge, and the Swift compiler/runtime remain trusted boundaries.

`DynamicBooleanSequenceSelection` extends the output-linked boundary to a
state-held set of Boolean sequences. The focused test first failed because
TLA+ emitted ordinary `CHOOSE` while generated Swift sorted lexicographically;
after the renderer change it checks the native selected state and the complete
emitted TLA+ module byte-for-byte, normalizing only the source-location binder.
`GeneratedSelectionProofTests` token-checks the complete emitted Swift update
function against its witness. `DynamicBooleanSequenceSelectionProof.tla` proves
the source rank and emitted lexicographic order agree for every pair and
nonempty subset of this three-value domain, then composes complete initial
states, labeled steps, no-match failure, and the selected evaluation check.
A reversed chosen edge is a negative control. All 32 obligations pass locally;
hosted proof evidence is pending. The Swift compiler/runtime,
`lexicographicallyPrecedes`, `Result`, `choose`, and update merge remain
trusted. This does not prove arbitrary mutable Boolean-sequence domains,
other element types, or general generated Swift emission.

`RankedChoiceProof.tla` generalizes the sorted-first argument: for any finite
ordered sequence, predicate, integer rank that strictly increases along that
sequence, complete-state update function, and action label, its source and
ranked-TLA choices have identical labeled edges and no-match failures. The
first matching index now follows from TLAPS's least-natural-number theorem,
so the edge theorem no longer assumes its existence. All 20 obligations passed
locally. This theorem still does not link arbitrary Swift and TLA+ emitter
outputs to the modeled order, rank, predicate, or update; hosted evidence for
this revision is pending.

`ConditionalOutcomeRules.tla` defines one Boolean conditional operation for
source steps, guarded compiled branches, and the TLA+ `IF` form. It proves the
complete labeled step predicate and first-failure result agree for any Boolean
condition-definedness and branch-failure flags. Its negative control reports
failure from an unselected branch and is rejected. All four obligations pass
locally. This is an abstract rule; the output links below instantiate it.

`ConditionalSelectionFailure` closes one branch-scoped choice failure. Its
generated Swift machine fails transactionally when `attempt` is true and the
selected domain has no match, but takes the `selected = 2` edge when `attempt`
is false. The renderer previously omitted `__SwiftTLAChoiceFailure0` because
lowering represented `If` as guarded `or` branches. The focused test failed
before the renderer fix, then passed after failure propagation through those
branches; it now pins the complete emitted TLA+ module after normalizing only
the source-location-derived binder name. `GeneratedSelectionProofTests` also
pins the emitted Swift choice cache and complete update function to
`GeneratedConditionalSelectionFailureSwiftWitness.txt`, normalizing only that
binder name. `ConditionalSelectionFailureProof.tla`
instantiates the shared conditional rule, then factors the source success and
failure rules through explicit compiled-branch rules before
comparing them to the exact emitted module. It also proves initial states, the
complete labeled `select` and internal `Terminating` relation, the selected
invariant, both branch verdicts, and a reversed-branch negative control. All
29 obligations passed locally; `EmittedSelectedBranchInstantiatesDefinedRule`
links its exact generated TLA+ step and failure predicate to the shared rule.
The proof does not yet verify that the Swift lowerer implements this compiled
rule for every accepted `If`; this fixture's
native behavior and exact outputs are the instance links. Effectful conditions,
nested conjunctions, arbitrary choice domains, and independent TLC/native
failure-outcome comparison remain open. Interpreting the pinned Swift source,
`Result.get`, `choose`, and update merge remains a trusted runtime boundary.

`ConditionalChoiceConditionFailure` covers an empty expression-level `CHOOSE`
in an `If` condition. The generated Swift machine throws before changing state;
the generated TLA+ module now reports the same evaluation failure and has no
`select` edge. A focused test pins the complete emitted TLA+ module, and
`ConditionalChoiceConditionFailureProof.tla` instantiates the shared
defined-conditional rule, then compares this fixture's initial state, complete labeled
steps, and failure invariant with that exact output. It rejects an unguarded
false-branch edge as a negative control. Its emitted failure predicate also
instantiates the shared rule. All 24 obligations passed locally; hosted evidence
is pending. This closes the empty-choice condition instance,
not nested or otherwise effectful conditions, arbitrary choice domains, or the
general Swift-emitter link.

`AggregateMissingSelection` closes a different expression boundary: a
no-match `Select` is the first element of a sequence literal. The focused
regression failed before the renderer fix: generated Swift threw
`noSatisfyingChoice` without changing state, while generated TLA+ had neither
the failure check nor an action guard. The test now pins the complete emitted
TLA+ module to `AggregateMissingSelection.tla`, normalizing only the generated
binder name. `GeneratedSelectionProofTests` also pins the actual emitted Swift
choice cache and complete update function to
`GeneratedAggregateMissingSelectionSwiftWitness.txt` as Swift tokens.
`AggregateMissingSelectionProof.tla` composes source, compiled, modeled-Swift,
and emitted rules for the initial state, complete labeled `select` relation,
no-match failure, and selected evaluation check. It proves an omitted-check
negative control; all 14 obligations passed locally. The Swift-token witness
and native machine test link this fixture to the modeled Swift rule, but
interpreting `Result.get`, `choose`, eager sequence construction, the update
merge, and Swift compiler/runtime behavior remains trusted. This does not
prove arbitrary nested choices, effectful predicates, all aggregate shapes,
or authored PlusCal; hosted evidence is pending.

## Checked kernel lemma

`SingleAssignment.tla` proves that replacing one value in a complete state
has the same successors as a guarded TLA+ assignment to that variable with
every other variable unchanged. It also proves equality of the corresponding
enabled-successor predicates. The theorem assumes the assigned key belongs
to the state's variable set. It is generic over state domains and values.

`SkipPreservesCompleteState` states the companion all-variable frame rule:
source `Skip`, compiled `unchanged` updates carrying each source value, and
the rendered unchanged relation have the same complete successors.
`GeneratedSkipFrameModel.tla` is the complete TLA+ output for a one-variable
`#spec` `Skip` fixture. `GeneratedSkipFrameTests` pins that module, the complete
macro-emitted Swift update function, the lowered action shape, and the native
labeled self-transition; an altered Swift state read fails its token witness.
Macro expansion now checks every emitted `unchanged` action part against an
independently constructed complete-state read-and-merge shape. The same altered
read is rejected by that production check, not merely by the fixture witness.
Macro expansion also checks each public State field's formal identity against
its compiled variable declaration; a misassigned identity name is rejected.
`EmittedSkipFrameMatchesSource` and `EmittedSkipInitialAndInvariant` connect the
emitted module's action, initial state, and declared invariant to this instance.
The focused Swift test passes locally, and pinned TLAPS 1.6.0-pre with arm64
Z3 4.15.4 proved all 1,430 obligations in an earlier `SingleAssignment.tla`
revision locally.
Hosted evidence remains pending. These structural checks do not prove source
binding chose the correct compiled variable identity, that every
action composition instantiates the frame theorem, or Swift compiler/runtime
interpretation.

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
generic initialization rules. `DependencyOrderedInitializationIsStable`
additionally proves that unique initialization targets and domains determined
only by earlier targets make each step stable under replacing its own target.
`SoundOrderedDependenciesArePriorOnly` derives the earlier-target condition
from sound dependency sets placed before each use. It does not establish that
the compiler's dependency scan is sound. After resolution, the compiler now
independently collects state reads through resolved function calls to a fixed
point and rejects an initializer plan that reads a variable not yet bound.
A reordered-plan negative control exercises this check through a formal call.
This checks the actual compiled order against the resolved read analysis; the
analysis itself still needs a soundness proof against expression evaluation.
`SoundOrderedInitializationIsStable` composes that condition with the
unique-target stability rule.
`StableInitialHistoryMatchesConjunction` then proves that every prefix of the
ordered membership history equals the corresponding TLA+ conjunction, including
empty domains. `OrderedEnumerationMatchesSelectedConjunction` composes those
results with an arbitrary total Boolean selected-initial-state predicate;
`ValidOrderedInitializationsHaveSelectedOutcome` proves that a corresponding
history exists. The compiler orders initializers by detected dependencies, but
these theorems do not yet prove that dependency detection is complete or that
the actual initializer expressions, generated Swift loops, and rendered `Init`
satisfy their premises for every accepted `#spec`. Evaluation failures are not
modeled by these set-equality theorems.

`DependentInitializationOutputProofModel.tla` is an exact generated module for
a `#spec` whose second variable's candidate set depends on the first variable's
choice. `DependentInitializationOutputProofTests` pins the complete emitted TLA
text and observes the generated Swift machine's three initial states.
`EmittedDependentInitializationMatchesSource` proves the imported `Init`
equivalent to an independently stated source relation, and
`EmittedDependentInitializationHasExactlyThreeStates` proves that complete
initial-state set. This connects one actual output pair to the generic rule's
intended behavior; it does not establish the candidate-set premise or generated
Swift output semantics for arbitrary accepted models. For stateful direct-TLA
modules, the renderer now checks the final `Init` block against the compiled
initializer clauses and selected initial invariant; removing the dependent
clause is rejected. The native emitter checks that the actual `_initialStates`
function contains each expected initializer-binding form exactly once, in
dependency order: fixed-value `let` or domain `for`. Replacing a domain loop
with a fixed value is rejected. The emitter also checks that each domain loop
iterates the candidate sequence named by the compiled plan; an altered
iterable failed the focused regression before this check and is now rejected.
For visible member-of initializers, it also verifies that the parsed
`_initialStates` body retains the exact candidate-producing assignment planned
by the emitter. The dependent-choice fixture independently states the expected
Swift conditional set and integer ordering, checks that assignment in the
actual output, and rejects a changed candidate set as a negative control. This
closes the candidate-expression output check for this fixture, not the general
rule: the production check still derives its expected source from the same
expression emitter. The same fixture checks that the actual generated machine
accepts its three valid selected initial states and rejects adjacent invalid
ones. That finite test is not a proof of the selected-state guard for every
value. These remain syntactic and finite output links; they do not prove the
Swift standard-library operations, every emitted expression, the general
selected-state guard, or initialization failures have the source meaning.
Variable-free action modules and initialization failures still need separate
semantics and output links.

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

`DefinedActionFailureRule.tla` extends the total binding rule with ordered
failure reporting: the bound expression is checked before the body, and a
defined binding exposes the body's failure. Its compositional outcome rule
preserves the complete state-and-action-labeled edge set and first-failure
class when source and emitted bound values agree when defined, and their
selected child update sets and failures agree. An omitted-body negative
control rejects the old failure relation. The rule is conditional on those
child premises; it does not establish them for arbitrary emitted expressions.
`BoundBodyChoiceFailureProof.tla` independently states the source initial
states, complete `pick` edge, bound-body `CHOOSE` failure, and selected
evaluation check for one accepted `Let` program. It instantiates the generic
outcome rule and composes it with the complete emitted TLA+ module, proving
the labeled edge and failure relation for the fixture. Negative controls
remove either the successful edge or the body failure. The focused
test pins that module byte-for-byte, the lowered `define`/`CHOOSE` shape, the
entire emitted Swift visitor token-for-token, and the native success/failure
outcomes. The Swift compiler's interpretation of the pinned visitor remains
a trusted boundary. The renderer still lacks a general path-sensitive
failure rule for every nonrepeatable bound expression, and the external
comparison path does not yet equate TLC's invariant violation with the native
typed failure. This slice does not establish universal `Let` preservation.

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
`State`/`Snapshot` declarations. It does not certify arbitrary initializers or
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
The emitter now calls one typed `mergeUpdate` operation for every generated
slot. Its focused contract checks absent, equal, and conflicting writes,
including preservation of the prior value on conflict; the token template
checks that both actual copy slots call that operation. The operation's Swift
implementation is still a trusted output link, not a TLAPS proof of Swift.
`SourceSlotMerge` separately specifies absent writes, compatible writes, and
conflicts over arbitrary state slots. `SourceSlotMergeIsExactlyGenerated`
proves both directions: for any typed prior update, slot, optional write, and
value, the source rule admits exactly one result, equal to the merge model's
result. `SourceAndGeneratedSlotHistoriesAreEqual` carries that equality
through any finite sequence of such writes; an overwrite-on-conflict negative
control is rejected. This closes the abstract merge-composition rule, not its
emitted-code link. The macro now token-checks every emitted `_Updates.merging`
method against the compiled slot list before publishing it, requiring one call
to the reusable `mergeUpdate` operation per slot, in order, with no extra
statements. A wrong-target mutation is rejected. This is a trusted syntactic
output checker, not a proof of the Swift compiler or the helper implementation;
`SourceAppliedUpdateIsExactlyGenerated` separately proves that an accepted
update yields exactly the complete state specified by the source rule, while
a rejected update yields no state. The macro also token-checks every emitted
`_Updates.applying` method against all compiled public and hidden fields:
each constructor argument must use its own update slot or its own prior value.
A wrong-fallback mutation is rejected. These checks cover arbitrary compiled
slot lists. The macro now also token-checks every emitted public `State`
constructor against the compiled field names, types, and ordinals: there must
be exactly one assignment from each corresponding initializer argument. A
wrong-field assignment is rejected by a negative control. In
`SingleAssignment.tla`, `SourceConstructedStateIsExactlyGenerated` proves the
independent complete-state construction rule, and
`AppliedUpdateComposesWithStateConstruction` composes it with the existing
update-application theorem. The macro also checks every emitted `Snapshot`
declaration against the compiled hidden-field list: it permits exactly the
public state and those hidden fields, with `Hashable` and `Sendable` synthesis
and no custom identity implementation. A missing-hidden-field mutation is
rejected. `SnapshotAssemblyPreservesEveryField` and
`SnapshotPartsAreInjective` prove the independent complete-state packing rule
for any partition between public and hidden variables. These close the abstract
construction and packing rules and their syntactic emitted links; the complete
successor-call-chain output checks still cover only the two-slot fixture.
Swift's synthesized memberwise initializer and `Hashable` behavior, plus
generic `Optional`, `Equatable`, `inout`, and `??`, remain stated trust
boundaries.
The macro also checks every emitted `formalProjection` declaration against the
compiled variable order. Its formal tokens must name each complete-state
variable exactly once, and each value expression must read only that variable's
public or hidden snapshot field. The function must contain the matching ordered
projection call without extra statements. A swapped-field mutation is rejected.
This closes the emitted routing shape, not the semantics of each type-specific
`formalValue` conversion. The shared direct-TLA renderer now checks the final
module text for exactly the compiled state-variable declaration (including
hidden variables and formal variable symbols); a missing-variable mutation is
rejected. This closes the TLA+ declaration's syntactic output link, not the
meaning of `Init`, `Next`, framing, or each value conversion.
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
The earlier local `--nofp` run proved all 1,423 obligations in that
`SingleAssignment.tla` revision. `SmallAdditionFitsSwiftInt` supplies the ordered
bound fact; an explicit nonempty-candidate witness closes singleton integer
selection; exposing the existing `OrderedAddDefined` definition closes
guarded-history function typing. That run proved that revision's obligations
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
fail; restoring it restored the proof. The fixture test also checks that the
actual compiled action has a guarded existential over `1..2`, followed by a
bound-value assignment. `GeneratedGuardedChoiceSwiftWitness.txt` pins the
entire emitted Swift update visitor by tokens; changing its native choice
domain to `1...1` fails the output check. The generic enumeration and
enabledness theorems at lines 706–730 were re-proved locally with TLAPS
(`--strict --nofp`, five obligations). This closes the output link for this
pure, finite guarded-choice fixture. It does not prove the emitter for every
accepted choice domain or cover candidate evaluation failures.

`MixedCandidateDivisionFailureModel.tla` is byte-for-byte generated from a
`#spec` choice over `0..1`. Candidate `0` divides by zero; candidate `1`
produces the labeled successor with `result = 1`. The native validator test
requires that successor state and edge before the typed failure event.
`MixedCandidateDivisionFailureProof.tla` independently defines those source
outcomes and proves the emitted initial state, step, division-failure
predicate, selected first failing divisor, absent overflow, and evaluation
verdict (36 local TLAPS obligations). The Swift visitor witness above pins
the shared choice-emission rule that defers a candidate failure until the
remaining candidates have been visited. This is a closed finite Int-division
case, not a proof of failure preservation for every accepted choice body or
value type. The native checker reports the first failure when several paths
fail differently. For an integer-valued candidate domain, the TLA+ renderer
now selects the least failing candidate before classifying its failure and
emits operands only for that candidate. `OrderedCandidateFailureRule.tla`
proves the least-candidate selection under an explicit minimum-existence
premise, the division-before-modulo outcome for a two-candidate instance,
and a reversed-order negative control (10 local TLAPS obligations). The
generated-machine regression failed before the renderer change and now pins
the canonical-order direction in the actual emitted predicates.
`OrderedEnumCandidateFailuresModel.tla` is byte-for-byte generated from a
finite-enum `Choose` whose Swift declaration order is `zed, alpha` but whose
canonical formal order is `alpha, zed`. Both candidates fail at the initial
state: `alpha` divides by zero through modulo, while `zed` uses a negative
modulo divisor. The generated Swift machine and native checker report the
first failure as division by zero, with the complete initial state and no
edge. `CanonicalCandidateTraversalRule.tla` proves that finite ordered native
candidate traversal and formal least-rank selection choose the same first
failure, including the no-failure case (104 local TLAPS obligations). The
least-natural theorem proves that every nonempty failed-position subset of a
finite candidate sequence has a least member, so the composed theorem needs no
minimum-existence premise. A second theorem derives strict traversal order
from ranks assigned by candidate position, allowing a uniform offset. This
also covers an order-preserving configured subset of a finite parameter
domain: its global member ranks select the same first failure as native
traversal. A composed theorem also equates the complete state-and-action-
labeled successor set from finite candidate traversal with the existential
TLA+ edge relation, conditional on equal per-candidate update sets. It does
not prove that the compiler extracts every finite domain correctly, that
individual branch emitters agree, or that every accepted domain has a
renderable rank.
`OrderedEnumCandidateFailureProof.tla` instantiates that rule for the concrete
canonical order, imports the exact emitted module, and independently defines
the source initial state, failed candidate set, canonical first failure, and
evaluation verdict. It proves the initial state's absent successor, selected
failure, and verdict, plus a reversed-rank negative control (71 local TLAPS
obligations). The exact-output
test is the link to the real TLA+ emitter. The same test token-checks the
complete emitted Swift update visitor against
`OrderedEnumCandidateFailureSwiftWitness.txt`, including the canonical
String comparator, ordered `visitAlternatives` call, both modulo expressions,
and complete-state update path. The generated Swift behavior is tested, not
formally proved; Swift's execution of these pinned operations remains a
trusted boundary. This fixture does not prove first-failure order
for every accepted candidate type, dynamic domain, or nested body, nor the
complete Swift emitter. No hosted evidence qualifies this new slice yet.

`CandidateChoiceFailureModel.tla` checks the other failure class inside an
action-level `Choose`: candidate `0` has no matching expression-level
`CHOOSE`, while candidate `1` yields `result = 1`. The native check retains
the complete successor and reports `noSatisfyingChoice`. The TLA+ renderer
now reports a choice failure when any bound candidate's body fails, without
turning the successful candidate into a disabled action. The test pins the
complete emitted TLA+ module byte-for-byte and the emitted Swift visitor by
tokens; it failed before the renderer fix because the TLA+ failure predicate
was absent. `CandidateChoiceFailureProof.tla` independently states the source
initial state, labeled step, failed candidate set, and evaluation verdict,
then proves their equivalence to the actual emitted module (22 local TLAPS
obligations). This closes this finite candidate/selection case, not arbitrary
domain-expression failure order or every accepted choice body. Hosted
evidence is pending.

`EitherBranchDivisionFailureModel.tla` is byte-for-byte generated from a
`#spec` `Either`: its first branch divides by zero in the initial state,
while its second branch produces a complete labeled successor. The source
fixture test checks that lowering creates an `or` of the division and
constant-success branches; it pins the full emitted Swift visitor by tokens
and rejects a visitor with the second branch removed. Native checking must
retain the successful state and edge and report the first branch's typed
failure. `EitherBranchDivisionFailureProof.tla` independently defines the
source initial state, both branch transitions, and failure verdict, then
proves the complete emitted TLA+ outcome and a dropped-branch negative
control (15 local TLAPS obligations). This closes this concrete `Either`
slice, not arbitrary branch composition or multiple distinct failures.
Both `Either` and action-level `Choose` now emit calls to the same
`_NativeMachineOperations.visitAlternatives` operation. Their full Swift
visitor witnesses pin those actual calls. `AlternativeTraversalRule.tla`
proves by induction that ordered traversal retains the union of successful
updates and the first failure for any finite list of branch outcomes. Its
ordered-sequence rule also proves that each buffered update chunk is appended
without loss, reordering, or collapsing duplicates (109 local TLAPS
obligations). Replacing the first failure with the last is a negative control.
`AlternativeTraversalSwiftKernel.txt` pins the actual Swift helper declaration
by parsed tokens; reversing its replay loop fails that check. Focused Swift
tests cover duplicate ordered updates after a failure and ensure an
output-callback error is not mistaken for a branch failure. The mapping from
Swift arrays, loops, `do`/`catch`, and callback execution to the TLAPS history,
and Swift compiler/runtime interpretation of the pinned code, remain trusted
boundaries. This does not establish that arbitrary branch bodies or the TLA+
emitter implement the abstract branch outcomes.
Hosted evidence for this slice is pending.

Two further `Either` fixtures test failure precedence across different
generated checks. `EitherDistinctFailuresModel` fails by division in its first
branch and by negative modulo in its second; the native result reports the
division failure, and the emitted TLA+ suppresses the later modulo predicate.
`EitherChoiceAfterDivisionFailureModel` has initial divisors `0` and `1`:
the first reports division failure, while the second retains its successful
division edge and reports the later no-match `CHOOSE` failure. Focused tests
pin the complete emitted TLA+ modules byte-for-byte and both complete Swift
update visitors by tokens. `EitherDistinctFailuresProof.tla` and
`EitherChoiceAfterDivisionFailureProof.tla` independently state initial
states, complete labeled steps, selected failure predicates and evaluation
verdicts over their typed domains, prove those domains include the initial
states and are step-closed, and show an ungated later failure would disagree.
All 16 obligations in each module passed locally. These are concrete output
links, not a theorem for arbitrary `or` trees: failures that the renderer does
not yet expose, parameterized candidate ordering, and general first-failure
agreement with TLA+ remain open. Hosted evidence is pending.

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

Before compilation, every normalized action now passes a structural frame
check: each potentially successful branch must assign or explicitly preserve
every declared model variable. A focused negative control rejects a branch
that omits one variable; the same branch passes after frame completion. This
checks a source-level invariant only. It does not prove that lowering retains
the frame, or that either emitted output implements it.

`ActionDistributionRule.tla` proves that distributing conjunction over two
alternatives preserves every compatible complete update and its labeled edge,
for arbitrary update sets. Its negative control proves that dropping a branch
with a distinct compatible update changes the graph. A `#spec` regression with
two `Either` statements retains both generated Swift successors while also
reporting a division failure. These facts do not yet prove that
`ActionNormalization.complete` implements the general distribution rule, that
the generated TLA+ action has the same complete relation, or that distribution
preserves first-failure order and checking effects. Those links remain open.

| Action-tree rule | Current machine-checked fact | Output obligation still open |
| --- | --- | --- |
| `assign`, `unchanged` | Complete-state delta and unchanged-frame equality; output-linked one-variable `Skip` instance; every generated write part has a structural target-and-merge check; direct fallible assignments now emit a definedness guard and failure predicates | Prove each emitted Swift update and TLA clause denotes that delta for every compiled expression and state type. |
| `guard_` | Pure total guards agree at abstract positions; the checked-addition `When` instance has exact Swift/TLA+ output links, complete labeled edges, failure and evaluation-check proof | Generalize emitted predicate evaluation, disabledness, short-circuit failures, and source `When` substitution. |
| `and` | Compatible delta conjunction and conflicting relational writes; TLA+ now exposes a right-hand arithmetic or `CHOOSE` failure when the left action is enabled | Prove both emitters' evaluation order, first-failure selection across nondeterministic left branches, conflict/error semantics, and frame completion. |
| `or` | Guarded-choice preservation conditional on equal branch edges; output-linked success-plus-failure and two distinct-failure fixtures; generic successful-update union and first-failure order for the shared native traversal | Prove arbitrary branch construction, all failure kinds and TLA+ ordering, multiplicity policy, and both outputs. |
| `existsAction` | Enumeration versus existential quantification preserves complete labeled edges and enabledness for the same state-dependent candidate values and pure branch edges; shared native traversal preserves successful updates and first-failure order; an output-linked case retains a successful candidate and reports another candidate's expression-level choice failure; fallible domains now guard the emitted TLA+ action and retain evaluation failure | Prove arbitrary emitted domain and branch expressions agree, including all failure kinds, first-failure order, and checking effects. |
| `define` | Equal total bound values and selected branch edges preserve complete labeled edges and enabledness across eager binding and `LET` | Prove emitted value/branch expressions, failure behavior, and checking effects. |
| `ifElse` | Equal pure predicates and branch edges preserve labeled edges and enabledness; `ConditionalOutcomeRules` proves source, guarded compiled, and TLA+ conditional forms agree on labeled steps and first failure; every generated Swift conditional calls one checked kernel | Link every emitted condition and branch expression, including nonrepeatable ones, to the rule, and prove the independent TLA+ output link. |

A typed membership condition over repeatable operands is also repeatable.
Previously, TLA+ generation omitted the selected branch's failure predicates
for such a condition, even though the generated Swift machine could report a
division failure there. A focused accepted `#spec` model now checks both
membership outcomes in the native machine and the membership-guarded generated
TLA+ failure declaration. This closes that concrete disagreement; it does not
prove membership or conditional selection for every accepted operand type.

`DefinedChoiceDomainRule.tla` proves that guarding an existential domain
preserves the enabled step and puts a domain evaluation failure before any
body failure; an unguarded domain has a counterexample. The renderer regression
failed before the guard was added. `UndefinedChoiceDomainModel` exercises an
accepted `#spec` `With` with a zero-divisor domain through the generated Swift
machine and rendered TLA+. This links one fallible domain instance to both
outputs. The theorem assumes the definedness predicate is correct and that a
domain value exists when it is true; it does not prove arbitrary domain
evaluation, TLA+ `IF` execution, or branch semantics.

The generated Swift action checker now walks every compiled action node and
checks the actual emitted visitor tokens for exactly one corresponding local
function, the root invocation, and the ordered child calls. It also counts
`assign` and `unchanged` nodes independently, and checks each complete write
body for its target slot, compatible-update merge, and emission. For
`unchanged`, the expected state read comes from the compiled field mapping
rather than the emitter's read helper. Wrong-target, missing-write, and
wrong-child mutations are rejected; the unmodified generated visitor passes.
This closes the structural call-graph and write-body output link for accepted
action trees. It does not establish that the checked Swift syntax executes
with the abstract rule's branch, binding, or failure semantics, nor that
assignment expressions or the independent TLA+ output agree. Those remain
separate obligations; this is not yet a general action-output theorem.

For each compiled `ifElse`, the checker now also requires the actual emitted
body to call `_NativeMachineOperations.visitConditional` with the emitter's
rendered condition and the corresponding children, passing the same binder
arguments, pending updates, and emitter. A mutated output that replaces the
condition with `false` is rejected. `ConditionalSwiftKernel.txt` pins the
actual reusable Swift operation: it evaluates the condition once, invokes only
the selected branch, and propagates a condition failure before either branch.
Focused execution tests exercise those three facts. This closes the Swift
conditional *control-shape* link for every compiled action tree, conditional
on ordinary Swift semantics for the pinned kernel and on expression emission
denoting the compiled condition. Source lowering, arbitrary branch failures,
and the independent TLA+ conditional output still need their general links.

For every compiled `or` node, the output checker additionally requires the
complete emitted body to call the shared ordered alternative visitor with
`[false, true]`, route the second alternative to the right child and the first
to the left child, and pass the same bindings, updates, and branch emitter to
both. Reversing that order fails the production check. The parsed Swift helper
witness connects those generated calls to one reviewed implementation of the
TLAPS traversal rule. Interpreting its Swift control flow as the formal fold,
and matching arbitrary child expressions to their TLA+ forms, remain explicit
unproved links.

The direct compiled `assign` renderer previously omitted both the value's
definedness guard and its choice/arithmetic failure predicates. A focused
regression failed on all four missing facts before the shared constructor fix;
it and the renderer and choice-failure suites now pass locally. This connects
the renderer and a complete direct formal-core module to the existing
expression-definedness machinery; the module test requires the emitted
evaluation invariant. It does not prove that machinery for every expression or
link arbitrary generated Swift
assignment code to this TLA+ rule.
`DefinedAssignmentPreservesStepAndFailure` composes the existing complete-state
update theorem with matching expression definedness and values. Its three
focused TLAPS obligations passed locally with fingerprint reuse disabled.
Those expression-agreement premises, actual output interpretation, and other
failure kinds remain open.

A focused regression was red because a non-guard left conjunct could succeed
while the TLA+ failure renderer discarded a right-hand division failure. The
renderer now predicates right-hand arithmetic and `CHOOSE` failures on
`ENABLED` of the left action; the focused regression, renderer suite, and
choice-failure suite pass locally. This checks the compiled renderer rule, not
the source-to-compiled mapping or the actual generated Swift/TLA+ pair for an
arbitrary accepted program. In particular, `ENABLED` establishes that the
right side is visited at least once; it does not establish which failure wins
when the left action has multiple ordered branches. That output and proof
boundary remains open.

`ParameterizedStringCandidateFailuresModel` exercises `existsAction` over a
typed `Set<String>` parameter whose declared finite domain contains two
different sets. The actual generated Swift machine reports the first failure
in canonical candidate order for the two configurations. The actual
macro-emitted TLA+ now ranks the union of the declared members and selects
the same first failing candidate; the regression was red when it used
independent existential failure predicates. This is focused output-test
evidence, not a TLAPS proof or a TLC parity run. Non-enumerable dynamic
domains, value families without a proved rank, and the general emitter theorem
remain open. A fallible `With` over a state-dependent `Set<String>` has no current
renderable candidate order. Native checking still evaluates it, but TLA+
export now fails with `unsupportedCanonicalCandidateOrder` instead of emitting
an existential failure predicate that may select a different failure. The
focused regression was red before this fail-closed change. This is an
explicit output limitation, not a proof that the dynamic-domain construct is
preserved; an ordered formal encoding and its output link remain required.

Finite model values are also exact candidates when their universe comes from
an accepted finite enum or parameter domain. The generated Swift visitor and
the TLA+ failure predicate both rank the same complete formal values; a
focused two-configuration test checks different first failures and the emitted
rank for each model value. The AsynchInterface corpus test checks the resulting
configured native graphs and selected verdicts. The generic
`CanonicalCandidateTraversalRule.tla` covers equal ordered candidate lists and
their finite subsets, but the Swift emitter, parameter-domain extraction, and
actual TLC behavior remain trusted or independently tested links. Arbitrary
state-held sets without a renderable order still fail closed.

For nested fallible `With` actions, the TLA+ emitter now renders the Boolean
"some failure" test structurally, using existential quantification over the
candidate domain rather than re-expanding every failure-kind predicate at each
nesting level. `CandidateFailureAggregationPreservesVerdict` proves the
quantifier/disjunction step; `OmittingAFailureKindChangesVerdict` is its negative
control, and `EarlierFailureShortCircuitsLaterFailure` covers the `Either`
Boolean guard. The local generated-output regression keeps Boulanger and
DieHardest-parallel modules below a 1 MB total and 64 KiB per line; the prior
hosted outputs were 2.7 MB and 13.6 MB. This proves neither TLC runtime nor
the general lowering/emitter link. The complete hosted parity paths remain the
admission test.

A `With` over dictionary keys selected from a singleton literal tuple parameter
also has a finite rank. The generated Swift machine sorts the keys, and a
focused output test checks its first failure against the ranks in the actual
generated TLA+. The registered DieHardest cases render with this rule. This
does not prove general parameter-expression evaluation or TLC parity for the
new output. A derived domain with multiple possible parameter values or a
state-dependent domain still fails closed when no other renderable order exists.

The generated conditional arithmetic regressions check both branch selection
and an arithmetic condition that can overflow before either branch runs.
Native failure leaves state unchanged; generated TLA+ disables the action and
reports that first failure. For a repeatable arithmetic condition, branch
failures are reported only when the condition succeeded and selected that
branch. `DefinedConditionalPreservesStepAndFirstFailure` proves the abstract
Boolean step and ordered failure rule, with an unselected-branch negative
control. The arithmetic fixture still has only focused output-test evidence:
its actual Swift and TLA+ expressions are not linked to that theorem or to a
checked TLA module. Nonrepeatable conditions and other `ifElse` trees remain
open. `EmittedConditionFailureInstantiatesDefinedRule` does link the existing
empty-choice-in-condition TLA+ fixture to this rule, but it does not establish
the arithmetic instance or all accepted conditions. A separate accepted `Choose(0...1)`
case still throws on its first native branch while generated TLA+ has no
intrinsic failure predicate; ordered first-failure and whole-action semantics
for `existsAction` remain open.

`ConditionalChoiceThenModuloFailureModel` adds a mixed-failure instance. For
its four initial states, generated Swift reports a missing `CHOOSE` result
before branch selection, reports modulo by zero in the selected branch, or
produces the complete successor. Before the renderer fix, generated TLA+
declared neither failure. The test now pins the lowered conditional shape,
the complete generated Swift update visitor, and the complete generated TLA+
module after normalizing only the source-location binder ID. The corresponding
TLAPS module proves initial states, complete labeled steps, closure of the
reachable state set, all three emitted failure predicates and their selected
invariant against that actual TLA+ module; an unguarded-else negative control
adds an invalid edge. Both exact-output checks reject a deliberately altered
witness, and all 17 proof obligations passed locally. Swift compiler/runtime
interpretation of the pinned visitor and the macro's general lowering rule
remain trusted; conditions without a compositional definedness rule still
lack coverage. This is an output-linked instance, not arbitrary `ifElse`
preservation.

The earlier conditional Swift witness was also refreshed to pin the emitted
`visitAlternatives` call after native alternative traversal changed. Its
exact-output test passes again. `AlternativeTraversalRule.tla` proves the
abstract update-union and first-failure behavior; the concrete Swift helper's
implementation and its call-site link are still trusted boundaries.

Expression-level `If`, `&&`, and `||` now select fallible sites only when their
branch is evaluated. The shared TLA+ renderer emits branch-guarded failure
conditions, and a `Let` with a defined fallible value carries later arithmetic
failures from its body. Focused generated-machine and renderer regressions
cover missing `CHOOSE`, modulo by zero, successful successors, and skipped
branches. `LazyExpressionFailureRule.tla` proves the selected-site first-failure
algebra (10 local TLAPS obligations), including an eager-branch negative
control. `OrderedFailureSites.tla` then proves, by induction for every finite
ordered list of Boolean site guards, that the renderer's guarded prefix has
the source definedness, each emitted failure marks exactly the first failing
site, and a later bound-body failure runs only after the value is defined.
Its eager-body negative control and all 32 obligations passed locally. The
rule is reusable for other expressions and `Let` bodies, but it does not by
itself prove that every emitted expression supplies the right guard list.
Effectful forms without a compositional definedness rule remain open.

`ExpressionConditionalFailureModel` is one output-linked instance of that
rule. Its test checks the lowered conditional expression, the emitted Swift
transition visitor and closed-choice helper by syntax tokens, and the complete
generated TLA+ module by exact text after normalizing only a source-location
binder name. A reversed Swift branch and an eager TLA+ choice-failure guard
must both fail those output checks. `ExpressionConditionalFailureProof.tla`
proves the pinned module's initial states, complete labeled transition,
three failure predicates, selected evaluation invariant, and branch-selection
rule against an independent source relation. It also proves that this action
is enabled exactly when the evaluation check holds on the declared initial
domain. The three actual emitted failure predicates are connected to the
generic ordered-site theorem, not merely proved separately; an eager-failure
negative control is included (31 local TLAPS obligations). The finite
Swift-machine test covers the exact four initial
states and their successors. These facts do not prove the Swift compiler,
the concrete `_NativeMachineOperations` implementations, arbitrary source
lowering, or every expression form. Hosted proof and parity evidence for this
new instance are still pending.

`ShortCircuitFailureModel` connects the same ordered-site rule to both
expression-level Boolean operators. Its output check pins the complete
generated TLA+ module and both emitted Swift transition visitors; reversing
either Swift short-circuit branch or making the TLA+ conjunction failure eager
breaks the check. `ShortCircuitFailureProof.tla` proves the two complete
labeled relations, all four emitted failure predicates and selected invariant,
reachable-state closure, and the instantiated ordered-site rule (22 local
TLAPS obligations). In particular, `enabled = TRUE, divisor = 0` retains a
valid disjunction step while the conjunction reports division by zero. The
native test checks all four initial states, successor counts and failures.
With non-decisive checking, the generated validation visitor reports a failing
action and continues to later actions and states. The focused regression checks
the disjunction edge alongside the conjunction failure; the related choice
tests require the resulting complete two-state graph, including its self-loop
and the failure at each expanded state. Decisive checking may still stop at
the first failure and does not claim graph parity.
Swift runtime interpretation of the pinned visitors and arbitrary Boolean
expression lowering remain trusted; this exact instance is not a universal
short-circuit theorem or hosted admission result.

This table is a proof inventory, not a claim that these seven groups exhaust
`#spec`: initialization, source lowering, properties, temporal behavior,
refinement, and PlusCal export also require their own output links.

`MissingFunctionKeyProof.tla` imports an exact-output-checked generated TLA+
module. It proves that a dictionary read emits the same complete labeled step
and missing-key failure as the independent read rule, and that omitting the
evaluation check would disagree. The generated Swift machine test observes
the actual missing-key error without a state change. An exact token witness
pins the emitted Swift action visitor, including argument-before-function
evaluation and its call to the shared checked lookup; unchecked lookup and
reversed-operand mutations fail that output check. The proof is local only;
hosted evidence is pending. It does not cover every function-application form
or prove Swift runtime behavior from source. Fallible `With` bodies over
state-dependent candidates with no reproducible TLA+ order remain rejected
with `unsupportedCanonicalCandidateOrder`, rather than claiming first-failure
parity.

SequenceIndexFailureProof.tla imports an exact-output-checked generated
module and proves the source's one-based array bound agrees with the compiled
rule and TLA+ DOMAIN guard. For the pinned #spec read it checks initial states, the
complete labeled step, the out-of-bounds failure and its index/length payload,
and the selected evaluation invariant. Its negative control shows that
omitting the failure check disagrees on the empty initial sequence. The
generated Swift test checks the actual compiled sequence-access constructor,
pins the complete update visitor, and executes the shared one-based read
operation at valid and invalid indices. All 34 proof
obligations passed locally; hosted evidence is pending. The Swift compiler
and runtime interpretation of the pinned visitor remain trusted. This
instance does not establish arbitrary sequence-expression lowering,
initialization, or temporal fidelity.

EmptySequenceReadProof.tla imports an exact-output-checked generated module
and proves the source and compiled rules for empty-sequence head and tail
agree with both emitted TLA+ actions and their evaluation-failure predicates.
It checks initial states, both complete labeled steps, the selected
evaluation invariant, and a negative control that omits the failure check.
The focused test pins both actual generated Swift action visitors and checks
the shared native operation on empty and nonempty sequences. All 23 proof
obligations passed locally; hosted evidence is pending. The Swift compiler
and runtime interpretation of the visitors remain trusted. This instance
does not establish arbitrary sequence-expression lowering, initialization,
or temporal fidelity.

SequenceEditPreservationProof.tla imports the exact generated TLA+ module for
a `#spec` array removal and prefix. For arbitrary integer sequences and valid
indices, it proves the independently indexed source values equal the lowered
`SubSeq` forms; it then connects both complete labeled actions, the two
initial states, index/length failure payloads, and the selected evaluation
check to the emitted module. Its invalid-initial-state negative control fails
if the evaluation check is omitted. The focused generated-machine test pins
both complete Swift update visitors and checks that replacing either shared
checked sequence operation breaks its output witness; it executes both
successful and failing transitions. All 53 TLAPS obligations passed locally;
hosted evidence is pending. The Swift compiler/runtime and the shared array
operations' implementation of the stated one-based sequence rules remain
trusted. The proof covers these two operators and this emitted model, not
arbitrary expression composition, initialization plans, or temporal claims.

Selected `RandomSubset(upTo:from:)` initialization now validates the count
before checking a proposed member against the source domain. A negative count
reports the native evaluation failure; zero admits no selected member. The
focused regression failed on both cases before the change and now passes;
the existing valid unsampled-member replay also passes. This closes only that
native selected-initial-state inconsistency. The TLA+ randomization rule,
TLC override, and their failure/order agreement with generated Swift are not
established by these tests.

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
