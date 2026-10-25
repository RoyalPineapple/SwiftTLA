# Language-composition proof checklist

**Target:** for every accepted `#spec` program, the actual generated Swift
machine and TLA+ module have the same complete initial states, labeled steps,
evaluation failures, and selected checking outcomes as the independently
defined source semantics. Documented Swift language, compiler, standard-library,
and runtime behavior is trusted; SwiftTLA's parser, lowerer, emitters, output
checkers, and execution kernel are not automatically trusted.

This is a **rule checklist**, not a tally of models or TLAPS obligations. A row
is complete only when every link below holds for arbitrary well-typed inputs
to that rule, its premises are discharged where the compiler uses it, and the
result composes with already-complete rows. A fixture or TLC graph comparison
is regression evidence, not a substitute for a rule.

Named-model proofs remain as regression evidence, not language-proof credit.
The sequence-removal lemmas were extracted from one retired model proof;
output-pin and negative-control tests for that model remain. Rule modules are
**candidates**, not automatically language-wide certificates: each still
needs the links in the gate below.

## Gate for each accepted rule

- [ ] Define its source value/outcome rule independently of `CompiledProgram`.
  Include evaluation order, disabled behavior, complete state and action
  identity, successful and failing alternatives, and error payloads.
- [ ] Prove the source rule corresponds to the compiled constructor for
  arbitrary well-typed operands. Check the **real lowerer's** source and output
  against that rule; reject a mismatched derivation.
- [ ] Check the **actual emitted Swift** against the compiled rule, including
  initial-state and failure paths, and state the project-owned checker/kernel
  assumptions that remain.
- [ ] Check the **actual emitted TLA+ and configuration** against the same rule,
  including guards, selected failure relations, and checking settings.
- [ ] Prove the rule composes with its children and surrounding program. Add a
  mutation that each artifact check rejects; run focused tests and proof, then
  related regressions and hosted checks on one frozen SHA.

Keep one row per **accepted constructor**, not per fixture. If a constructor
exists only in the formal core or compiled representation, record that
separately; its existence does not show that `#spec` accepts it. An accepted
form with a missing link stays open. Do not quietly reject an existing DSL
form to make a theorem true: repair the translation or obtain an explicit
acceptance-rule decision.

## Inventory and proof work

### Action-constructor domain

`ActionExpr` and `CompiledActionExpr` each have the eight cases below. The
`#spec` accepts direct `Action` declarations through
`SpecParser+SpecBuilder.parseAction` and `SpecParser.decodeActionExpr`:
`FormalDefinitionFidelityMacro` is a compiled macro fixture, and
`SpecificationSourceAuthorityTests.initialDomainsUseDeclarationContext`
checks that route through type resolution. The Algorithm lowerer also builds
these cases from scoped statements. Repository authoring guidance prefers
`Algorithm`, but that preference does **not** remove accepted `Action` from
the proof domain. Individual constructor combinations and rejection
diagnostics still need an acceptance audit.

The inventory is taken from `SpecParser+SpecBuilder.swift`, `SpecParser.swift`,
`AlgorithmLowering.swift`, `ActionExpr.swift`, and `CompiledExpressions.swift`.

| Source / compiled case | Accepted route | Rule coverage |
| --- | --- | --- |
| `assign` | Direct `ActionExpr.assign`, `.becomes`, collection updates; scheduled `Assign` and control writes | Ordered root-`Int` `Do` slice only; other targets and expressions open |
| `unchanged` | Direct `.stays`; generated frame and terminal actions | Complete-state frame composition proved for an arbitrary partial continuation; full action-tree induction open |
| `guard_` | Direct predicate or `.when`; Algorithm `When` and entry guards | General disabled/failure rule open |
| `existsAction` | Direct `ActionExpr.exists`; Algorithm `With` and scheduled `Choose` | General domain, binding, and outcome rule open |
| `ifElse` | Algorithm `If` | General branch and condition-failure rule open |
| `define` | Algorithm `Let` and scheduled write captures | General lexical binding and failure rule open |
| `and` | Direct `&&` or action closure sequence; Algorithm atomic composition | Ordered root-`Int` `Do` composition only; arbitrary nesting open |
| `or` | Direct `\|\|`; Algorithm `Either` and control-branch composition | General union of successful and failing branches open |

The rows name constructor *reachability*, not proof completion. For each route,
the remaining audit must verify its parsed source tree, the real lowerer's
matching compiled case, both actual outputs, and a rejecting mutation. Keep
compiler-synthesized uses in the domain too: they affect accepted programs
even when authors cannot spell the constructor directly.

`While` is an accepted step form, not an `AlgorithmStatementModel` case.
`SpecParser+Algorithm.parseEachComponent` records its condition in
`AlgorithmStepModel.loopCondition`; `CompiledLowerer` and `CompiledTypeChecker`
carry and type-check it. Sequential and process `AlgorithmLowering` each
lower it to an `ifElse`: true runs the body and returns to the step's control
location; false transfers to the following location. The condition also
guards generated assertion checks. This source-to-control rule, including
condition evaluation failures and the actual Swift/TLA+ output links, needs
its own proof row; proving the fifteen statement cases does not cover it.

The parser's `AlgorithmSourceConstruct` also has accepted forms **outside**
the statement enum. This is a dispatcher inventory, not an assertion that
every spelling and placement passes the parser's later checks:

| Source constructs | Boundary to prove |
| --- | --- |
| `scopedState(.shared/.local)` | Initial values and member-choice domains; local-state ownership |
| `formalDefinition`, `macro` | Expansion, binding, and capture before expression/action lowering |
| `procedure`, `each` | Parameter/process domains, control ownership, and procedure stack |
| `doStep`, `whileStep` | Step labels and fallthrough; `Do(when:)` becomes `when`, while the `While` condition remains on the step |
| `invariant`, `reachable`, `leadsTo`, `eventually`, `always`, `alwaysEventually`, `eventuallyAlways` | Selected state and temporal checking outcomes |
| `fairness`, `assume`, `stateConstraint`, `actionConstraint` | Configuration, fairness obligations, and constrained exploration; generic fairness and assumptions are invalid inside an `Algorithm` body |
| `whenCondition`, `assert`, `assign`, `goto`, `call`, `return`, `stop`, `skip`, `ifElse`, `either`, `choose`, `with`, `letBinding` | The corresponding statement cases below; `parallel` and `rejected` are compiler-synthesized |

Each group still needs a spelling/placement acceptance audit. In particular,
an exhaustive switch over `AlgorithmStatementModel` would miss the step
envelope, definitions, initializers, and checking configuration.

Fairness is not one semantic constructor. The outer `#spec` parser accepts the
following distinct forms; `Algorithm` bodies reject generic fairness. Each
form still needs source, lowering, both output, and selected-checking links:

| Accepted fairness form | Distinct obligation |
| --- | --- |
| `WeakFairness(action)` / `StrongFairness(action)`, optionally `on: projection` | Weak versus strong fairness of one bound action or `Do` step, using the selected fairness projection |
| `WeakFairness(anyOf: steps)` / `StrongFairness(anyOf: steps)` | One obligation over the disjunction of a nonempty list of distinct bound `Do` steps |
| `WeakFairness(eachOf: steps)` / `StrongFairness(eachOf: steps)` | One process-member obligation over that disjunction for each member; lowering requires one shared immutable process population |
| `WeakFairness(each: step)` / `StrongFairness(each: step)` | One obligation for each finite invocation of the bound step; lowering requires an immutable domain |
| `WeakFairnessNext()` / `StrongFairnessNext()`, optionally `on: projection` | Weak versus strong fairness of `Next`, with the selected state projection |

The compiled `FairnessCondition` also has concrete action-call cases. Track
those as lowering-produced forms, not extra `#spec` spellings. A proof of
`anyOf` cannot stand in for `eachOf`, and neither establishes per-invocation
fairness.

### Validation and checking-selection domain

`SpecParser+Validation.parseValidation` accepts an immutable bound
`Validation { Bind(parameter, to: value) }` and the modifiers below. This is
part of accepted `#spec` syntax even though it does not add an action to the
model. Each selection needs a source rule and links to the actual native check
and rendered TLA+/configuration; a matching finite graph alone does not prove
the selected verdict. The parser also registers bound `FairnessProfile` and
`Symmetry` declarations used by these selections.

| Accepted form | Separate rule still needed |
| --- | --- |
| `Bind(parameter, to: value)` | Typed parameter substitution and the resulting complete initial and step relations |
| `.checking(only: properties)` / `.expect(property, outcome)` | Selected property set and expected `.satisfied` or `.violated` verdict |
| `.checkingDeadlock(flag)` / `.expectDeadlock(outcome)` | Deadlock selection and expected verdict, including disabled checking |
| `.behavior(.specification / .initialAndNext)` | Which behavior specification is checked |
| `.checkingMode(.exhaustive / .decisiveCounterexample)` | Exhaustive completion versus a decisive early result; never equate partial graphs |
| `.simulating(traces: count, maximumDepth: limit)` | Sampled-trace outcome and positive bounds, distinct from exhaustive checking |
| `.usingFairness(profile)` with `FairnessProfile(excluding: labels)` | Selected fairness obligations after the declared step exclusions |
| `.usingSymmetry(symmetry)` with `Symmetry(domain)` | Finite or typed-parameter symmetry domain and checking quotient, without changing model transitions |
| `.viewing(expression)` | Selected checking view; preserve complete machine states outside that explicit view |
| `.postcondition(expression, name:, expecting:)` | After-check summary predicate, optional name, and expected outcome; state-level reads are rejected |

The parser records modifier selections in source order. The acceptance audit
must also check how compilation handles repeated or conflicting selections;
the table does not assume that a repeated modifier is valid. `Symmetry` takes
a finite domain or typed set parameter; `FairnessProfile` takes registered
step labels. Neither declaration is a new transition rule.

### Expression-constructor domain

These are the exact outer cases in `StateExpr` and `CompiledOperation` at this
revision, grouped only to keep the inventory readable. A group is **not** one
proof rule: each named case still needs its own source, lowering, Swift, and
TLA+ links. `CompiledLowerer.lowerWithReferences` maps source expressions to
compiled operations; some compiled cases are synthesized during binding or
type checking. Parser reachability and rejection diagnostics for every spelling
remain to be audited, so this inventory does not claim that every public
`StateExpr` case can be authored in `#spec`.

| Domain | `StateExpr` cases | `CompiledOperation` cases |
| --- | --- | --- |
| Values, names, and control | `sourceIssue`, `value`, `integerSet`, `variable`, `parameter`, `checkingRegister`, `setCheckingRegister`, `checkingLevel`, `checkingDiameter`, `processLocalFamily`, `currentProcess`, `programCounter`, `procedureStack`, `controlLocation` | `value`, `integerSet`, `stateVariable`, `boundValue`, `checkingRegister`, `setCheckingRegister`, `checkingLevel`, `checkingDiameter`, `controlLocation`, `operatorReference`, `convert` |
| Arithmetic | `add`, `subtract`, `multiply`, `divide`, `modulo`, `negate`, `integerDivide` | `add`, `subtract`, `multiply`, `divide`, `modulo`, `negate`, `integerDivide` |
| Equality, order, and Boolean control | `equal`, `notEqual`, `lessThan`, `lessOrEqual`, `greaterThan`, `greaterOrEqual`, `and`, `or`, `not`, `ifThenElse`, `printT` | `equal`, `notEqual`, `lessThan`, `lessOrEqual`, `greaterThan`, `greaterOrEqual`, `and`, `or`, `not`, `ifThenElse`, `printT` |
| Transition and explicit view | `assertView`, `nextState`, `stutteringStep`, `enabledAction` | `assertView`, `nextState`, `stutteringStep`, `enabledAction` |
| Sets and ranges | `setLiteral`, `in`, `subset`, `union`, `intersection`, `setDifference`, `cardinality`, `setFilter`, `setMap`, `powerSet`, `sequenceSet`, `unionAll`, `integerRange`, `setSum`, `functionSet`, `randomSubset`, `randomElement` | `setLiteral`, `in`, `subset`, `union`, `intersection`, `setDifference`, `cardinality`, `setFilter`, `setMap`, `powerSet`, `sequenceSet`, `unionAll`, `integerRange`, `setSum`, `functionSet`, `randomSubset`, `randomElement` |
| Tuples and sequences | `tupleLiteral`, `tupleAccess`, `tupleDynamicAccess`, `tupleLength`, `tupleAppend`, `tupleHead`, `tupleTail`, `tupleConcatenate`, `tupleRemoving`, `tuplePrefix`, `sequenceSelect`, `sequenceFromSet`, `sequenceFromFunction` | `tupleLiteral`, `tupleAccess`, `tupleDynamicAccess`, `tupleLength`, `tupleAppend`, `tupleHead`, `tupleTail`, `tupleConcatenate`, `tupleRemoving`, `tuplePrefix`, `sequenceSelect`, `sequenceFromSet`, `sequenceFromFunction` |
| Records and functions | `recordLiteral`, `recordAccess`, `domain`, `functionLiteral`, `functionApply`, `except` | `recordLiteral`, `recordAccess`, `domain`, `functionLiteral`, `functionApply`, `except` |
| Binding, choice, and calls | `caseExpr`, `forAll`, `exists`, `choose`, `foldFunction`, `operatorApplication`, `recursiveCall`, `letValue`, `letIn` | `caseExpr`, `forAll`, `exists`, `choose`, `foldFunction`, `operatorApplication`, `call`, `checkedCall`, `letValue`, `letIn` |

`sourceIssue` must fail before a compiled expression exists. `currentProcess`
and `processLocalFamily` are rejected outside their algorithm scope; the
algorithm lowerer may replace them before this general expression pass.
`convert`, `operatorReference`, `boundValue`, `call`, and `checkedCall` are
compiled-side obligations even though they have no same-named source case.
The first ordered-`Int` slice covers only literal `value`, resolved prior-state
reads, and checked `add` in its stated positions; every other case above
remains open unless a separate complete rule is established.
`OrderedIntExpressionRule.tla` proves that both evaluation histories exist
for every finite topologically indexed expression graph of those three cases.
They agree at every node on the value or the first left-to-right failure,
including the `integerOverflow` kind, `addition` operation, and ordered
operands. Source and generated overflow records are defined independently;
changing the generated operation to `subtraction` or reversing its operands
breaks the general theorem. Reversing generated child-failure priority also
makes the proof fail. The generated addition rule includes the TLA+ emitter's
actual small-operand fast path and exact fallback; the proof requires the standard
Swift `Int` range to include ±2,000,000,000. Replacing that fast-path test
with unconditional success breaks the theorem. This closes the arithmetic
guard rule. `StraightLineRenderedActionCheck` reconstructs that exact guard
from the compiled tree, reads the actual TLA+ action, and rejects a changed
fast-path bound. Its implementation remains a SwiftTLA-owned trust boundary;
the Swift operation-kernel link is separate. For the recognized ordered-`Int`
class, `StraightLineAssignmentCheck`
now constructs postorder indexed plans independently from source and lowered
initializer trees, and from source and captured `Do` assignment trees. It
compares literal values, resolved root reads, ordered child indices, and
operations; the existing wrong-value and wrong-order controls pass. The
checker and its plan construction remain SwiftTLA-owned trust boundaries,
not a TLAPS proof of the compiler implementation. This does not extend the
mapping to other accepted expressions or close either actual-output link.
`OrderedIntExpressionPreservesAssignmentOutcome` composes that expression
rule with an arbitrary root assignment: the separately defined source and
generated updates have the same labeled Int-data-state edge, and a failed
expression yields the same labeled failure without a successor. Replacing
the generated failure relation with the empty set breaks the theorem. This
discharges the expression-to-assignment rule, not the missing source-syntax
mapping or either concrete emitter link. The program-counter update is
composed separately in `SingleAssignment.tla`.

### Algorithm-statement domain

`AlgorithmStatementModel` has the fifteen cases below. Authored statements
enter through `AlgorithmBuilder` or `SpecParser+Algorithm`; scheduling can
replace them before `AlgorithmLowering.lower` builds an `ActionExpr`. This map
is based on those actual switches, not on named example models. A destination
names a constructor reached during lowering; it is **not** a completed proof
of the source statement or its generated outputs.

| Statement case | Route into the compiled action/check | Rule still needed |
| --- | --- | --- |
| `rejected` | Diagnostic sentinel; lowering yields a false guard only if it reaches that phase | Prove rejection precedes usable output |
| `when` | `guard_` combined with the remaining action by `and` | Disabled versus failed condition |
| `assert` | Extracted assertion; leaves transition action unchanged | Assertion selection and failure |
| `set` | Scheduled into `letBinding` plus a final `parallel` write | Ordered reads, captures, and writes |
| `parallel` | Scheduler-owned final root assignments joined by `and` | Complete frames and last-write rule |
| `letBinding` | `define` around the continuation | Lexical scope and failure |
| `with` | `existsAction` over the bound domain | Every binding and domain failure |
| `ifElse` | `ifElse` over both continuations | Selected branch and condition failure |
| `either` | `or` over both continuations | Both branches' successors and failures |
| `choose` | Scheduled into `with`, then `existsAction` | Choice domain and retained failures |
| `goto` | Program-counter transfer through `assign` | Exact next control location |
| `call` | Procedure entry, argument/local/stack writes | Call frame and argument order |
| `return` | Procedure stack and program-counter transfer | Return frame and underflow |
| `stop` | Transfer to the generated `Done` location | Terminal control and frame |
| `skip` | Continuation unchanged | Identity step and control fallthrough |

`set`, `choose`, and `parallel` do not all reach the same lowering switch:
the scheduler must run exactly once before atomic lowering. That scheduling
boundary needs its own general proof; a proof of the final `ActionExpr` alone
cannot establish source-order behavior.

### 0. Fix the domain of the theorem

- [ ] Enumerate all accepted `#spec` syntax after parsing, binding, type and
  configuration checking. Link each spelling to its source AST constructor,
  compiled constructor(s), and diagnostics. Reconcile the parser in
  `Sources/SwiftTLAPlugin` with `Documentation/DSLDesign.md`; identify formal-
  core-only constructors separately.
- [ ] Inventory every `StateExpr`, `CompiledOperation`, `ActionExpr`,
  `CompiledActionExpr`, `VariableInitialization`, and
  `AlgorithmStatementModel` case. Make the inventory fail review when a new
  accepted case has no proof row. Include parameterized types, names, binders,
  checking configuration, and target-dependent `Int` bounds.
- [ ] Define one outcome domain: initial states; labeled transition relation;
  disabled branches; all evaluation failures alongside any successful choices;
  and selected property/deadlock/temporal verdicts. Define exact agreement and
  the projection, if any, between source and generated internal state.

### 1. Values and expressions — structural induction

- [ ] Values and identity: `Int`, `Bool`, `String`, finite constants, sets,
  tuples/sequences, records, functions, and hidden control values. Prove exact
  encoding, equality, canonical order where selection needs one, and failures.
- [ ] Leaves and binding: literals, state/control/checking reads, parameters,
  bound values, operator references, explicit conversions and views. Prove
  capture avoidance and that both outputs read the same complete prior state.
- [ ] Arithmetic: each accepted operator, checked Swift-`Int` bounds, operand
  order, division/modulo failures, and matching operation/operand payloads.
  Generalize from child-expression premises, not a fixed addition fixture.
- [ ] Predicates and control expressions: comparisons, Boolean short circuit,
  conditional/`CASE`, `LET`, operator calls, and any check-specific expressions.
  Preserve which child is evaluated, skipped, disabled, or fails first.
- [ ] Collections and selection: set/range operations, tuples/sequences,
  records/functions, quantifiers, expression-level `CHOOSE`/`Select`, folds,
  and random operators. Check every accepted compiled operation individually;
  exhaustive random choice is a relation, not a sample. A successful choice
  must not erase another candidate's failure.
  `SequenceRemoveRule.tla` proves the sequence-removal domain and value
  equations for arbitrary element sets and valid indices. Its actual lowerer,
  Swift-output, TLA+-output, and failure links remain open.
- [ ] Prove the expression induction covers arbitrary accepted nesting and
  substitution. For unsupported combinations, verify a clear diagnostic
  **before** either backend emits a plausible but unproved machine.

### 2. Initial states and actions

- [ ] `.value` initialization: exact complete initial binding and type.
- [ ] `.expression` initialization: ordered dependent reads and failures.
- [ ] `.memberOf` initialization: every initial choice and its failures.
- [ ] Compose initializers with hidden control/procedure state and selected
  initial-state checks. Prove the complete set, not one replay.
- [ ] `.assign`: value/failure evaluation, one intended update, exact frame.
  For sequential `Do` algorithms whose shared state is `Int` and whose steps
  contain only ordered root assignments from literals, prior-state reads, and
  checked addition, the source-to-lowered check now records every qualified
  step and the terminal action. Compilation requires the independent scalar
  TLA+ action check for each recorded action, plus its checked-addition failure
  declarations; an unsupported output shape fails instead of silently skipping
  that check. Actual action declarations and selected failure checks still run
  on the emitted module. This closes the output-check *coverage* gap for that
  stated class, not the general `.assign` rule or the Swift execution-kernel
  trust boundary.
- [ ] `.unchanged`: exact frame, including hidden state.
  The compiler checks action-constructor shape and assignment/frame target IDs
  across nested compiled actions. The generated Swift verifier independently
  checks the compiled frame variable and prior-state read. The actual generated
  TLA+ action is checked against the compiled constructor structure and frame
  names. `UnchangedConjunctionPreservesOutcome` proves that, for any complete
  state, frame key, partial continuation write, and action label, the source,
  compiled, and rendered relations have identical complete successors and
  retain the continuation's failure set, including when its write conflicts
  with the frame. This is conditional on equal continuation failures: it does
  not prove the continuation's expression evaluation or the native kernel.
  General expression values, definedness/failure guards, and the full
  action-tree induction remain open; the TLA+ structure check uses the
  expression renderer for its leaves.
- [ ] `.guard_`: enabled/disabled/failure distinction.
- [ ] `.existsAction`: all bindings, successors, and failures.
- [ ] `.ifElse`: branch selection and condition failure.
- [ ] `.define`: binding scope, capture, and failure.
- [ ] `.and`: ordered composition and first failure.
  `BranchwiseConjunctionRetainsSuccessesAndFirstFailure` proves, for any finite
  ordered list of left outcomes with at most one success and no simultaneous
  left failure, that running each successful candidate's continuation retains
  every update in order and selects the first resulting failure. The source
  first-failure predicate is independent of the visitor's fold. The compiled
  shape gate rejects an alternative-producing left conjunct; lowering moves
  continuations inside `or` and `existsAction` branches, and focused generated-
  machine tests exercise a success alongside a later failure. The general
  source-to-branchwise-lowering proof remains open. For action trees built from
  `assign`, `unchanged`, `guard_`, `and`, and `or`, the real normalizer now checks
  ordered branch words, unchanged expression sites, and complete frames even
  when an expression can fail; a swapped fallible branch is rejected. This
  structural check does not establish expression evaluation, binding, or
  action semantics. A proof that the shape gate discharges
  the single-candidate premise for every accepted nested action, and both
  arbitrary-expression output links remain open. The Swift visitor kernel and
  structural output checker remain project-owned trusted boundaries.
- [ ] `.or`: branch union, retaining success and failure together.
  For root and nested `or` trees, the actual TLA+ aggregate-failure
  declaration is checked against independent left-to-right `IF` composition
  of the two child predicates; changing the declaration to `TRUE` is rejected.
  This is conditional on each non-`or` child's predicate being correct. It
  does not yet check detailed failure kind/operands or an `or` nested under
  another action constructor. Those output and source-semantic links remain open.
  For each of these eight source/compiled constructors, check complete frames,
  labels, binders, evaluation order, all successors, disabled branches, and
  failures where applicable.
- [ ] Prove action-tree induction: arbitrary nesting and ordered atomic writes;
  branch union preserves both valid successors and failures. Check actual
  generated transition routing, not only a hand-written action relation.

### 3. Algorithms and checking outcomes

- [ ] `When` and `Assert` (separate rules for disabling and failure).
- [ ] `Assign` and parallel assignment (separate ordered-write rules).
- [ ] `Let` and `With` (separate binding and domain rules).
- [ ] `If`, `Either`, and `Choose` (separate conditional/branch rules).
- [ ] `Goto`, `Call`, `Return`, `Stop`, and `Skip` (separate control rules).
  Split each accepted statement form into its own row after the parser
  acceptance audit; account for rejected forms via diagnostics.
- [ ] Prove `Do`, `While`, `Each`, procedures/processes, labels, program counter,
  and procedure stack compose those statement rules. Relate complete generated
  control state to source control; no per-model termination proof is needed
  merely to preserve the step relation.
- [ ] Prove selected invariant, reachability, assumptions/constraints,
  deadlock, refinement, fairness, and temporal-check semantics on both paths.
  Separate finite graph/trace consequences from liveness assumptions and
  checker execution limits.
- [ ] Compose the initial, expression, action, control, and checking theorems
  over **every accepted source constructor**. State the final theorem's exact
  domain, proof premises, and trusted components. Only then claim universal
  `#spec` fidelity; retain native–TLC parity as independent regression evidence.

## Current first slice and next gate

The first slice is arbitrary-length sequential `Do` programs with nonempty,
ordered root `Int` assignments from literals, prior-state reads and checked addition,
deterministic `Int` initializers of those forms, and the hidden program
counter. `SingleAssignment.tla` has a general composition theorem for complete
initial sets, labeled steps, ordered action/initial failures, and termination.
`ExactSequentialCheckingOutcomes` derives invariant, reachability, and
deadlock verdict agreement from equal complete initial/edge sets and
pointwise-equal selected state predicates. This is a graph-to-verdict rule:
it does not establish that an arbitrary authored predicate is lowered and
emitted identically. That property-output link, assumptions, fairness, and
checker resource-limit semantics remain open.
`ExactSequentialSelectedOutcome` adds the ordered-`Int` checking decision:
equal initial states, labeled edges, initial failure records, and reachable
action failure records imply the same selected result, with an evaluation
failure taking precedence over deadlock. Reversing that priority in the
generated rule breaks the theorem. This is conditional on all four evidence
sets agreeing; it does not prove that the actual TLA+ checker selects every
emitted initial-failure declaration. The renderer selects action failures in
its intrinsic invariant. It now also emits and checks a pure constant-level
disjunction of all declared initial-failure predicates; the missing-site
mutation and eight related initial-failure tests pass locally. That operator
is now selected by a separate, state-free TLC run before graph exploration;
the retained input and outcome are checked against the generated-TLA oracle.
Native validation retains successful initial states alongside a failure.
These changes pass focused local tests, but are not hosted evidence. The
initial-failure output link remains open: the separate run compares only the
existence of a failure, not its kind or operands, and a failure with no valid
initial state is rejected rather than certified. A module-level `ASSUME` in
the graph check would make a failing initializer a false proof premise; a TLC
`POSTCONDITION` runs after checking and does not establish evaluation-failure
precedence over deadlock.
The actual checking paths differ: generated Swift evaluates an authored
reachability predicate positively, while the TLA+ renderer negates it and
selects that definition as a TLC invariant. Neither transformation is proved
for arbitrary accepted predicates. The ordered-Int source witness now carries
the `#spec` default deadlock selection separately from compiled behavior.
Production checks require the root TLA configuration and generated Swift
`checksDeadlock` to retain that default. The generated TLA export checker
requires the checked constructor argument and a final return of that value.
Those output checkers remain project-owned trusted code. The focused test and
22 related ordered-assignment tests pass locally; hosted evidence is pending.
The current first slice has no
authored state predicate; its selected outcomes are the automatic
evaluation-failure check and default deadlock, not general invariant or
reachability predicates.
Production source/lowering and actual-output checkers plus wrong-value,
wrong-location, wrong-order, and omitted-failure mutations are described in
`README.md`. This is **not** coverage of other accepted constructors.

- [ ] Validate the default-deadlock output link for this slice. The source
  default, actual generated Swift declaration, generated export argument, and
  rendered `CHECK_DEADLOCK` directive are checked; flipped-value, decoy, and
  changed-return negative controls pass locally, while hosted admission remains
  pending. Explicit
  `Validation.checkingDeadlock` overrides remain accepted and need their own
  selection rule.
- [ ] Complete the actual TLA+ initial-failure checking output link. The
  separate TLC check now retains and verifies an existence verdict, but exact
  failure records and the failure-only case remain open. Do not count
  declaration presence, the existence verdict, or the conditional
  selected-outcome theorem as complete failure parity.
- [x] Finish the full local proof for the current dependent-initializer
  and checking-outcome rules. TLAPS `--strict --nofp` proved the complete
  `SingleAssignment.tla` module; the ordered-assignment and
  generated-initialization suites passed locally before the checking-outcome
  rule was added. This is not hosted evidence for the extension.
- [x] Baseline literal-initializer slice: ordinary CI, semantic-proof
  diagnostic, and full validation passed on frozen PR #397 revision
  `318e81f4b88acdcab0fe92224fee95a4d5c9e5b4`. The dependent-initializer
  extension in this worktree is not included in that evidence.
- [ ] Obtain the same hosted evidence for the dependent-initializer extension
  after its full local proof and related regressions pass.
- [x] Record the proof boundary below. The output checks do not prove their
  own correctness, and the local proof does not qualify a hosted revision.
- [x] Derive the sequential program's complete initial-set equality from
  separate guarded source and generated histories. `GuardedInitialHistoriesAgree`
  proves equality at every prefix. `OrderedSequentialIntProgramCompose` uses
  that result to prove equality after it adds the hidden program counter.
  The theorem does not assume equal initial sets. The actual Swift and TLA+
  output checks must still link each accepted initializer to its plan.
- [x] Check nested dependent `Int` addition's actual TLA+ initial-failure
  relations in source order. The emitted-output checker rejects swapped
  failure sites; this local regression does not establish every initializer
  expression's Swift/TLA+ output link.
- [x] Emit pure checked-arithmetic definedness as the ordered guard history
  used by `OrderedInitialGuardsPreserveFirstFailure`, so a later guard cannot
  evaluate an overflowing earlier result. The independent rendered-output
  check and related local regressions pass; hosted evidence for this revision
  remains outstanding.
- [x] Independently decode the actual generated Swift for deterministic
  `Int` initializer leaves and nested checked additions. The checker compares
  its ordered operations and operands to the compiled tree and rejects a
  swapped-operand mutation. This covers that output rule, not the native
  operation kernel or other initializer expression families.
- [ ] Then close **one missing link at a time** in the inventory above. Do not
  add upstream families or more named proof fixtures in place of rule coverage.

For the stated ordered-`Int` class, `SingleAssignment.tla` proves initial-set,
labeled-step, and failure composition from the rule premises. The proof does
not inspect emitted files.

`OrderedIntSourceSyntaxCheck` checks the recognized scoped, sequential `Int`
syntax against the parsed source model, including optional presentation labels
on shared variables. Its mutation test changes initial values, step identities,
reads, targets, and write order when `@TLAModel` invokes
`TLASpecVerifier.parseAndVerify`. Other accepted spellings that the syntax
checker does not recognize are not covered by this source-syntax link.
Standalone `#spec` expansion instead runs `SpecExpressionMacro` and its
`DSLRewriter` before the `TLASpec` builder. For the recognized ordered-`Int`
class, expansion now independently checks that the rewrite adds only the
binding identities and preserves the complete initializer and step syntax,
including registration; altered identities, reads, targets, and registration
are negative controls. This closes the syntax-to-expanded-Swift link for that
class, but does not by itself check the runtime `AlgorithmModel`. That link
now has a structural source witness emitted by the actual `#spec` macro.
For each registered algorithm in the recognized class, the runtime builder
must produce the same ordered declarations and statements before compilation;
changed initial values, labels, targets, reads, and write order are rejected.
The witness extractor and structural checker remain SwiftTLA-owned trust
boundaries, not a TLAPS proof of the Swift builder implementation. Other
accepted standalone `#spec` forms do not inherit this checked link by analogy.

`StraightLineAssignmentCheck` checks the lowerer and rejects changed operands,
writes, and control locations.

The Swift output check reads the emitted initializer and rejects swapped
addition operands, missing failure handling, and an early return. The TLA+
output check reads `Init`, actions, and failure relations. It rejects changed
values, changed control, and swapped failure sites. Standalone `#spec`
rendering now reconstructs the ordered-`Int` literal, dependent read/addition,
and program-counter `Init` clauses even before expression result types are
resolved; it requires the complete conjunction for this class. A focused
regression failed before that check and passes after it, as does the related
21-test ordered-assignment suite. This is local evidence, not a hosted result.
For an action marked by the source-to-lowered ordered-`Int` check, native
emission now requires the Swift-output verifier to decode every scalar leaf;
an unrecognized compiled value cannot use the opaque fallback. The focused
mutation replaces one captured `Int` value with an uncheckable `String`: the
old verifier accepted it, the strict verifier rejects it, and the related
36-test ordered-assignment/native-output suites pass locally. The standalone
`#spec` builder path also rejects this mutation; its 21-test ordered-assignment
suite passes locally. The verifier
and native operation kernel remain trusted, and hosted evidence for this
change is still pending.

The source parser, output checks, native update and visitor kernel, and TLA+
renderer remain SwiftTLA-owned trust boundaries. Documented Swift behavior is
trusted. Hosted evidence for these side-branch changes is still missing.

The detailed contract and slice evidence live in [README.md](README.md).
