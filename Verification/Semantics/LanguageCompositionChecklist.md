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
Production source/lowering and actual-output checkers plus wrong-value,
wrong-location, wrong-order, and omitted-failure mutations are described in
`README.md`. This is **not** coverage of other accepted constructors.

- [x] Finish the full local proof for the current dependent-initializer
  extension. TLAPS `--nofp` proved all 1,839 obligations in
  `SingleAssignment.tla`; the ordered-assignment and generated-initialization
  suites passed locally. This is not hosted evidence for the extension.
- [x] Baseline literal-initializer slice: ordinary CI, semantic-proof
  diagnostic, and full validation passed on frozen PR #397 revision
  `318e81f4b88acdcab0fe92224fee95a4d5c9e5b4`. The dependent-initializer
  extension in this worktree is not included in that evidence.
- [ ] Obtain the same hosted evidence for the dependent-initializer extension
  after its full local proof and related regressions pass.
- [ ] Record, for this slice, what is proved versus checked versus trusted:
  the actual-output checkers' correctness, remaining source parsing, SwiftTLA
  update/visitor kernel, and documented Swift behavior are not discharged by
  TLAPS. Give each link its rejected mutation.
- [x] Derive the sequential program's complete initial-set equality from
  arbitrary guarded deterministic initializer plans rather than assuming
  equal final sets. `GuardedSequentialIntInitialSetsAgree` constructs the
  common history and lifts it through the hidden program counter. Matching
  each accepted initializer expression's value and definedness function to
  its actual emitted Swift/TLA+ remains an output-link obligation.
- [ ] Then close **one missing link at a time** in the inventory above. Do not
  add upstream families or more named proof fixtures in place of rule coverage.

The detailed contract and slice evidence live in [README.md](README.md).
