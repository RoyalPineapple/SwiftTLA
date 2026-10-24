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
| `unchanged` | Direct `.stays`; generated frame and terminal actions | General frame/output rule open |
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
- [ ] `.unchanged`: exact frame, including hidden state.
  The compiler checks action-constructor shape and assignment/frame target IDs
  across nested compiled actions. The generated Swift verifier independently
  checks the compiled frame variable and prior-state read. Expression semantics,
  TLA+ output, and the compositional theorem remain open.
- [ ] `.guard_`: enabled/disabled/failure distinction.
- [ ] `.existsAction`: all bindings, successors, and failures.
- [ ] `.ifElse`: branch selection and condition failure.
- [ ] `.define`: binding scope, capture, and failure.
- [ ] `.and`: ordered composition and first failure.
- [ ] `.or`: branch union, retaining success and failure together.
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
The actual checking paths differ: generated Swift evaluates an authored
reachability predicate positively, while the TLA+ renderer negates it and
selects that definition as a TLC invariant. Neither transformation is proved
for arbitrary accepted predicates. Both deadlock directives interpolate the
compiled Boolean directly; checking those printed literals against that same
Boolean would only duplicate the emitter, not independently prove source
selection. The current first slice has no authored state predicate; its
selected outcomes are the automatic evaluation-failure check and default
deadlock, not general invariant or reachability predicates.
Production source/lowering and actual-output checkers plus wrong-value,
wrong-location, wrong-order, and omitted-failure mutations are described in
`README.md`. This is **not** coverage of other accepted constructors.

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

`OrderedIntSourceSyntaxCheck` checks the authored syntax against the parsed
source model. Its mutation test changes initial values, labels, reads, targets,
and write order. `StraightLineAssignmentCheck` checks the lowerer and rejects
changed operands, writes, and control locations.

The Swift output check reads the emitted initializer and rejects swapped
addition operands, missing failure handling, and an early return. The TLA+
output check reads `Init`, actions, and failure relations. It rejects changed
values, changed control, and swapped failure sites.

The source parser, output checks, native update and visitor kernel, and TLA+
renderer remain SwiftTLA-owned trust boundaries. Documented Swift behavior is
trusted. Hosted evidence for these side-branch changes is still missing.

The detailed contract and slice evidence live in [README.md](README.md).
