# SwiftTLA compositional language proof plan

Working baseline: `98f3a8f8277e4e231626e033f948aab344e9a6c6`, 5 November 2026.

The target is semantic preservation for every accepted `#spec` program.
Independent source semantics must agree with the actual generated Swift and TLA+ configuration.
The observations include complete initial states, labeled transitions, reached failures and selected checking outcomes.
Documented Swift behavior is trusted. Every other implementation boundary needs a proof or an explicit open obligation.

The first milestone covers the existing literal/read/checked-addition pilot.
This proof instance does not restrict the accepted language. Every other accepted form stays accepted and visibly open.
The final milestone covers the entire accepted language through composition.

This file owns the working tasks and their evidence links.
The existing [language checklist](LanguageCompositionChecklist.md) remains unchanged and supplies the broader requirements.
The [product completion plan](../CompletionPlan.md) retains its separate corpus and admission scope.

## Completion rule

A constructor row identifies its accepted spelling, type, placement and compiler route.
A proof for one route does not close every use of the constructor.
Each row needs all six links:

| Link | Required result |
| --- | --- |
| Source | Independent meaning for arbitrary valid operands, including evaluation order and complete outcomes |
| Compilation | Actual parsing, binding, normalization and resolution supply the rule premises |
| Swift | Actual emitted code implements the rule under documented Swift behavior |
| TLA+ configuration | Actual emitted definitions and selected configuration implement the same rule |
| Composition | A parent theorem consumes the child result without assuming the missing correspondence |
| Boundaries | Every checker, decoder, helper and kernel obligation is proved or remains explicitly open |

A row with an unproved owned boundary remains open.
Mathematical child hypotheses are valid premises. Each compiler use must discharge them through already established child rules.
Named examples, rejected mutations, model parity and obligation totals support regression or admission claims.
They do not complete these six links.

For each completed task, record the following evidence beside its checkbox:

- The exact rule and accepted domain.
- The implementation files and source revision.
- The theorem and retained proof inputs.
- The assumption removed and the parent theorem that consumes the result.
- The remaining owned boundaries and the proof method for each discharged boundary.
- The separate regression and admission receipts.

## Current assets

These assets are reusable inputs. Their presence does not complete a milestone.

| Asset | Current limit |
| --- | --- |
| [Ordered Int expression rules](OrderedIntExpressionRule.tla) | Logical plan construction is proved under explicit hypotheses. Actual source and output interpretation remain open. |
| [Boolean rules](BooleanExpressionFamily.md) and [sequence rules](SequenceExpressionFamily.md) | Finite composition exists. Source, leaf and implementation obligations remain. |
| [Initialization composition](InitializationComposition.tla) | Complete logical state and failure-set rules exist. Actual event trace correspondence remains open. |
| [Framed action composition](FramedActionTreeComposition.tla) | Reusable action and frame rules exist. Each actual compiler route still needs its premises. |
| [Checking composition](CheckingSelectionComposition.tla) | The theorem consumes equal machine observations. It does not derive those observations from the compiler. |
| Native initial events and selected TLA prefix | Both representations exist for the current deterministic consumer. General correspondence remains open. |

All proof milestones below start open.

## Execution order

| Milestone | Dependency | Exit result |
| --- | --- | --- |
| M0 Observation contract and pilot domain | None | Exact pilot premises and complete observations |
| M1 Literal read and checked addition | M0 pilot contract | Three reusable rules connected to actual source and both outputs |
| M2 Complete initialization | M1 | Actual complete initial states and failures follow from child rules |
| M3 Atomic actions | M1 and relevant M2 state facts | Actual labeled actions preserve complete states and failures |
| M4 Sequential control | M2 and M3 | Actual pilot control follows from action rules |
| M5 Selected checking | M2 through M4 | Actual pilot checking follows from derived machine observations |
| M6 First complete program theorem | M0 through M5 | Preservation for every program in the precise pilot domain |
| M7 Remaining accepted constructors | M6 reusable machinery | Every accepted route has all six links |
| M8 Whole language theorem | M7 | Coverage and program induction cover every accepted `#spec` |

The global accepted-domain inventory continues during M1 through M6.
Its final completion is required for M8. It does not delay a justified pilot proof.
All source and proof work remains independent of archive availability and CI completion.

## M0 Observation contract and pilot domain

- [ ] M0.1 Define complete observations in the existing outcome rules.
  Include state identity, labels, disabled behavior, failure site, payload, preceding bindings and selected outcomes.
  Separate logical domains, enumeration capability, execution limits and model failures.
- [ ] M0.2 Resolve the failure-set and event-trace relationship.
  Specify source-required order, multiplicity and first-failure selection. State the preservation obligation for every observation projection.
- [ ] M0.3 State the exact existing pilot domain.
  Include parameter-free deterministic Int initialization, literal/read/add expressions, sequential ordered root writes, hidden control and default checking.
- [ ] M0.4 Map each pilot spelling and placement to its actual parser, builder, compiled constructor and diagnostic route.
  Record accepted forms outside this instance as open. Do not reject them or treat unsupported-checker returns as certificates.
  Include overload selection, constant folding and target-dependent Int bounds.
- [ ] M0.5 Define the complete-program theorem statement before its component proofs.
  State the relation between internal and source state. Include failure-only and empty-initial outcomes.

Owners: [outcome rules](InitializationOutcomeRules.tla), [initialization histories](InitializationComposition.tla),
[source witness](../../Sources/SwiftTLAPlugin/OrderedIntSourceSyntaxCheck.swift) and [compiled checks](../../Sources/SwiftTLA/StraightLineAssignmentCheck.swift).

Exit: the pilot theorem has explicit premises and observations. Failure sets cannot silently replace an observable event trace.

## M1 Literal read and checked addition

Complete these rows in order. Reuse the existing rules and checks.

| Row | Actual implementation obligations | Existing formal consumer |
| --- | --- | --- |
| E LIT | Decode supported source literals, retain their Int values and resolve their types. Prove actual Swift and TLA literal interpretation. | `OrderedIntExpressionRule` and its literal-history cases |
| E READ | Prove binding freshness, name-to-ID correspondence, layout ownership and available prefix values. Include captured values where the route uses them. | `UniqueLayoutNamesPreserveEveryReadValue` and partial-expression rules |
| E ADD | Derive ordered children and postorder construction from the actual visitor. Prove checked arithmetic, skipped children and complete failure payloads. | `EveryOrderedIntExpressionPreservesOutcome` and assignment/initialization composition |

- [ ] M1.1 Complete all six links for E LIT.
- [ ] M1.2 Complete all six links for E READ.
- [ ] M1.3 Complete all six links for E ADD.
- [ ] M1.4 Derive `ExpressionPlan` from actual accepted input and actual compilation.
  Bind the physical visitor to the existing synchronized history proof. A supplied correct plan cannot replace this obligation.
- [ ] M1.5 Prove the existing output checks are sound for these routes.
  Include their token grammar, scopes, helper binding and mandatory coverage conditions.
- [ ] M1.6 Instantiate both assignment and initializer composition with these results.
  Derive the required child facts for arbitrary supported nesting and valid prior bindings.

Implementation owners:
[source witness](../../Sources/SwiftTLAPlugin/OrderedIntSourceSyntaxCheck.swift),
[compiled checks](../../Sources/SwiftTLA/StraightLineAssignmentCheck.swift),
[lowerer](../../Sources/SwiftTLA/CompiledLowerer.swift),
[native emitter](../../Sources/SwiftTLAPlugin/NativeSwiftEmitter+Machine.swift) and
[TLA output check](../../Sources/SwiftTLA/StraightLineRenderedActionCheck.swift).

Formal owners: [expression rules](OrderedIntExpressionRule.tla),
[assignment composition](OrderedIntAssignmentComposition.tla) and [initializer composition](OrderedIntInitializationComposition.tla).

Exit: actual accepted pilot expressions supply the child theorem premises. No extractor, decoder or helper assumption disappears through renaming.

## M2 Complete initialization

- [ ] M2.1 Derive the actual dependency order and successful-prefix type invariant.
  Include raw Int storage, state identity, hidden control and partial bindings.
- [ ] M2.2 Connect each actual initializer evaluation to its established expression rule.
  Derive complete candidate states and reached failures at every prefix.
- [ ] M2.3 Prove actual native event collection retains site, payload and immutable preceding bindings.
  Derive first-failure selection from the complete observation contract.
- [ ] M2.4 Prove actual TLA initialization and failure observations correspond to the same source prefixes.
  Complete branch observations cannot rely only on the deterministic selected record.
- [ ] M2.5 Prove complete initial function, selected filtering and hidden-state assembly correspond to the logical history.
- [ ] M2.6 Discharge the evaluator and history premises at `OrderedIntInitializerChildrenComposeAllReachableStatesAndFailures`.

Owners: [native runtime](../../Sources/SwiftTLA/CompiledRuntime.swift),
[native emitter](../../Sources/SwiftTLAPlugin/NativeSwiftEmitter+Machine.swift),
[TLA producer](../../Sources/SwiftTLA/SpecCompilation.swift) and the existing initialization modules.

Regression owners: `InitialBranchFailureTests`, `DependentInitializationOutputProofTests` and `OrderedAssignmentLoweringTests`.

Exit: the actual implementation supplies complete initial states and failure observations. First-failure agreement alone is insufficient.

## M3 Atomic actions

- [ ] M3.1 Connect assignment evaluation and captured reads to the established expression contracts.
- [ ] M3.2 Prove ordered pending writes, complete-state materialization and unchanged frames.
  Include hidden state and the source rule for repeated targets.
- [ ] M3.3 Connect each pilot normalization and binding step to the actual lowerer.
  Preserve evaluation count, lexical scope, disabled branches and reached failures.
- [ ] M3.4 Prove actual Swift successor routing and actual TLA action bodies implement the same complete labeled outcomes.
- [ ] M3.5 Instantiate action-tree and frame composition from these derived child facts.

Formal owners: [assignment composition](OrderedIntAssignmentComposition.tla),
[action composition](ActionTreeOutcomeComposition.tla), [assignment trees](AssignmentTreeOutcomeComposition.tla)
and [frame composition](FramedActionTreeComposition.tla).

Regression owners: `OrderedAssignmentLoweringTests`, `ActionFrameConditionTests`, `AlternativeTraversalTests` and `NativeExecutionBoundaryTests`.

Exit: every pilot atomic action preserves its complete successor and failure observations for arbitrary valid prior state.

## M4 Sequential control

- [ ] M4.1 Prove source scheduling reaches atomic lowering exactly once.
- [ ] M4.2 Derive label identity, program-counter updates, fallthrough and terminal control from the actual sequential lowerer.
  Include synthesized equality and Boolean guards, their helper bindings and actual output interpretation.
- [ ] M4.3 Prove actual action enumeration and `Next` include every required pilot action without extra actions.
- [ ] M4.4 Compose initialization, atomic steps and hidden control for arbitrary pilot program length.

Owners: the existing algorithm scheduler/lowerer, native action routing, TLA producer and [sequential rules](SingleAssignment.tla).

Exit: the compiler supplies the complete machine assumed by the sequential theorem. Processes and procedures remain open until M7.

## M5 Selected checking

- [ ] M5.1 Derive actual reachable states and labeled edges from M2 through M4.
  Prove the owned traversal/kernel correspondence required by the pilot verdict.
- [ ] M5.2 Derive actual failure availability, default deadlock selection and failure precedence.
  Include empty initialization and failure-only initialization.
- [ ] M5.3 Prove the actual Swift selection, TLA failure probe, CFG behavior selector and `Spec` body preserve this checking contract.
- [ ] M5.4 Instantiate `ExhaustiveSelectedCheckingObservationsCompose` from derived machine facts.
  Do not supply equal initial states, edges or failures as unexplained assumptions.

Owners: [selection rules](CheckingSelectionRule.tla), [checking composition](CheckingSelectionComposition.tla),
the existing native validation methods, `TLCConfiguration` and the actual TLA producer.

Exit: every selected pilot verdict follows from the source contract. Other checking modes remain open until M7.

## M6 First complete program theorem

- [ ] M6.1 Compose M0 through M5 for arbitrary programs in the stated pilot domain.
- [ ] M6.2 Discharge every compiler-use premise through the accepted-route map and child proofs.
- [ ] M6.3 Audit every remaining owned assumption against the completion rule.
  Record proof methods and external proof-tool assumptions separately from project-owned code.
- [ ] M6.4 Complete the existing positive and corruption regressions on the exact implementation revision.
- [ ] M6.5 State the proved domain and every remaining accepted-language obligation beside the theorem.

Exit: one complete source-to-Swift-and-TLA program theorem exists for the pilot.
This milestone establishes the reusable method. It does not complete the whole-language target.

## M7 Extend the same proof to every accepted constructor

Each family uses the same six links. Existing conditional theorems remain reusable inputs.
Each accepted spelling, type and placement needs an explicit row.

- [ ] M7.1 Complete value identity, representation, equality and canonical order for all accepted value types.
  Include Bool, String, constants, sets, sequences, tuples, records, functions and hidden state.
- [ ] M7.2 Complete the remaining arithmetic, comparisons, Boolean operations, conditionals and calls.
  Include conversions, binders, `CASE`, `LET` and all failure paths.
- [ ] M7.3 Complete collections, domains, queries, quantifiers, selection, folds and random operators.
  Preserve exhaustive choice semantics separately from sampled execution.
- [ ] M7.4 Complete parameterized, expression and membership initialization, constraints and selected initial invariants.
  Include capability errors and logical domains that native execution cannot enumerate.
- [ ] M7.5 Complete all eight accepted action constructors through arbitrary action-tree composition.
  Include assignment, unchanged, guards, existential binding, conditionals, definitions, conjunction and alternatives.
- [ ] M7.6 Complete all accepted algorithm statements and envelopes.
  Include `Do`, `While`, `Each`, processes, procedures, calls, returns, fairness and hidden control stacks.
- [ ] M7.7 Complete every accepted checking mode and modifier.
  Include predicates, assumptions, constraints, temporal/refinement checks, fairness, symmetry, views, postconditions, decisive and sampled outcomes.
- [ ] M7.8 Reconcile the accepted-route inventory with every actual parser, builder, type and placement decision.
  Account for synthesized forms and formal-core-only constructors separately.

Exit: the accepted-route inventory contains no missing constructor and no incomplete six-link row.

## M8 Whole language theorem

- [ ] M8.1 Prove expression, initializer, action and algorithm induction cover every accepted constructor and nesting route.
- [ ] M8.2 Prove their composition preserves complete machine observations and every selected checking outcome.
- [ ] M8.3 Audit all premises for circular agreement assumptions and undisclosed owned trust.
- [ ] M8.4 Bind the final theorem and implementation claims to one exact revision.
- [ ] M8.5 Complete the separate hosted admission gate for that revision.

Exit: every accepted `#spec` falls within the proved domain. The composed result reaches the actual Swift and TLA+ configuration.

## First execution queue

1. Write the M0 pilot theorem contract and the three E LIT/E READ/E ADD dependency rows.
2. Start M1.1 with the actual literal route in `orderedIntPlan` and its source, Swift and TLA consumers.
3. Derive literal preservation under the exact accepted domain. Reuse existing arithmetic and encoding lemmas.
4. Bind that result to actual code and artifact interpretation. Keep any unresolved boundary open.
5. Instantiate the literal child case in both expression and initialization composition.
6. Record the removed assumption, proof evidence and next available child task.

The global event-order obligation remains explicit during this first work package.
An infallible literal proof cannot close failure-trace correspondence for arbitrary initialization.

### First work package Integer literal

Required result: for each supported target Int value `n`, the literal expression returns `n` without reads, writes or evaluation failure.
This result supplies a child rule. Complete initializer state assembly remains in M2.

- [ ] L1 Record the accepted source spellings, resolved type and placements covered by this first route.
- [ ] L2 State the independent literal outcome and its empty read/failure effects in the existing expression rules.
- [ ] L3 Prove the actual source/compiled literal cases preserve `n`, Int type and empty children.
  Start with both `orderedIntPlan` overloads in `StraightLineAssignmentCheck`.
- [ ] L4 Prove the accepted Swift literal tokens and TLA integer encoding denote that same `n`.
  Reuse the existing native decoder and signed-radix lemmas. Include zero, negative values and target bounds in the general argument.
- [ ] L5 Instantiate the literal child cases in the expression and initializer composition modules.
  Record the exact premises that these results discharge.
- [ ] L6 Retain the proof inputs and existing owner regressions for the exact implementation revision.
  Keep any unresolved source or decoder interpretation open. Do not promote a partial route to the complete literal family.

### Literal encoding checkpoint 6 November 2026

Status: implementation defect repaired; E LIT and L1 through L6 remain open.
The mandatory authored-algorithm check rejected six valid Int addends before the repair.
This was an output-check defect, not an observed incorrect generated integer.

The existing decimal-group checker now matches the producer's inclusive radix base case and negative zero remainder.
Direct Int initialization also uses this independent checker instead of asking the producer to construct its own expected text.
The producer, accepted syntax and formal theorem statements are unchanged.

The code-scoped numeric argument uses radix `r = 1000000000`:

1. For `abs(n) <= r`, the producer emits the decimal representation of `n`.
2. Otherwise Swift quotient and remainder give `n = q*r + remainder`, with `abs(q) < abs(n)` and `abs(remainder) < r`.
   The positive divisor avoids division overflow, including at `Int.min`; unsigned magnitude avoids negating that minimum.
3. Induction on magnitude therefore gives the value of the recursive TLA arithmetic term.
   Its final sign and remainder magnitude reconstruct `remainder`; a zero remainder uses `+ 0`.
4. The independent checker groups magnitude digits in blocks of nine.
   A leading chunk equal to `r` remains unexpanded, matching the producer's inclusive stopping condition.
   Negative nonzero chunks subtract; zero chunks add.
5. `SignedLiteralComposition` already allows an unrestricted integer leading prefix.
   Its signed fold covers that ten-digit prefix; adding and subtracting zero have the same integer meaning.

This argument assumes documented Swift integer/decimal operations and standard TLA integer arithmetic.
It is a manual correspondence argument for these two functions, not a mechanically checked Swift translation.
It does not establish TLC execution support for every 64-bit intermediate value.
Tokenization, binding, native decoder soundness, all accepted source routes and full initializer observations remain owned obligations.
No new formal proof execution is claimed.

The parent consumers remain `OrderedIntExpressionsSupplyCompleteAssignmentLeaves` and
`OrderedIntInitializerChildrenComposeAllReachableStatesAndFailures`.
They still need the actual source, plan and output correspondence premises; this repair does not discharge those premises wholesale.

Regression record: the unchanged production baseline at `98f3a8f` executed two tests and rejected six intended valid inputs.
After repair, the five selected existing suites passed all 52 tests.
The whole repair log is 82629 bytes, SHA256 `66824c514937438a717554dd1846d97482bf07a8a44724f969430211ce8636e8`.
All 1201 captured inputs were unchanged during that run.
An earlier standalone literal baseline passed and is retained as producer/runtime evidence, not rejection evidence.
The final occurrence/change guards are a subsequent test-only amendment; that changed owner passed its focused rerun.
These receipts establish regression behavior only. Hosted admission remains separate.

## Work discipline and admission

- Keep one active proof task from the dependency frontier.
- Give each new theorem an actual compiler owner and a parent proof consumer.
- Prefer a missing implementation link over another conditional family theorem.
- If a proof exposes a compiler defect, repair the existing owner and its existing regression case.
- Keep proof closure, implemented behavior, regression results and hosted admission as separate statuses.
- Use the existing guarded local diagnostics and existing pinned proof exception.
- Do not edit tracked files during a heavy local run.
- Do not change accepted DSL, proof premises, tool pins, budgets or timeouts to obtain a passing result.
- Do not add another evaluator, checker, model, fixture or runtime proof seam.
- Do not wait for an archive or terminal ROOT audit before authorized source/proof work.
- Do not mark a task complete from a test count, proof-obligation count or named-model comparison.

Each completed row retains its dependency links and exact source revision.
A later source change reopens the affected obligations. Evidence reuse requires an explicit source-equivalence argument.

The initial diagnostic filter uses the existing primary owners:

```sh
bash scripts/local-validation.sh swiftpm-test 'OrderedAssignmentLoweringTests|InitialBranchFailureTests|DependentInitializationOutputProofTests'
bash scripts/local-validation.sh static
```

For formal checks, use the existing serialized pinned TLAPS helper with the affected rule batch.
Keep its existing flags, backends and limits. Require the actual theorem result and exact proof-input bytes.
For a measured regression, retain the intended pre-fix failure and the positive post-fix result.

Hosted admission still requires exact revision/run/attempt evidence and complete required archive integrity checks.
Historical gaps retain their original scope. They cannot supply evidence for a new revision or block unrelated source work.
This planning task does not authorize merge, CI rerun, dispatch, cancellation, reviewer changes or goal-status changes.
