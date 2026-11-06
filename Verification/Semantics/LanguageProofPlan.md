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

### Implementation first across the plan

The implementation queue spans M1 through M7 before deeper proof work on any one constructor.
Take small, measured repairs to existing compiler, output and checking boundaries first.
The proof dependencies above still govern proof closure; they do not block independent implementation repairs.

- [x] I1 Repair independent signed integer output checks and remove the direct-literal producer self-comparison.
  Published in `85264617`; regression and remaining proof limits are recorded below.
- [x] I2 Make the existing CFG check retain selected behavior and all configuration directives.
  Cover assumption-only, specification and Init/Next behavior, declarations, symmetry, views and postconditions.
- [x] I3 Repair finite scalar action-call encoding and domain order in the existing output check.
  Exercise quantified and expanded calls through their existing owners.
- [x] I4 Check the emitted fairness-free `Spec` body against its compiled state frame and Init/Next connection.
  Fairness terms and profile bodies retain separate open obligations.
- [ ] I5 Inspect the remaining source/output boundaries across initialization, actions and control for concrete implementation gaps.
  Fix measured gaps in their existing owners; preserve every accepted route.
- [x] I5a Resolve action names against known compiled module, model-value and binder declarations.
  Preserve action IDs, source labels and the valid single unbound `Next` case.
- [x] I5b Preserve state names that occupy `vars` and link generated refinements without duplicate instance declarations.
  Use substituted safety frames only when the mappings cover every actual declared abstract variable.
  Hidden or noncanonical frames retain the existing alias route and an open correspondence obligation.
- [x] I5c Retain generated-refinement model values in root declarations, instance substitutions and checking configuration.
  Preserve existing symbols and model-value identity when names collide; reuse established bindings on repeated imports.
  Concrete abstract constants and module-operator replacements retain separate open forwarding obligations.
- [x] I5d Keep public state names and declaration IDs while assigning distinct formal names for generated behavior and known declarations.
  Carry the same formal names through TLA/PlusCal, generated field identities, complete projections and initial failure prefixes.
  Unoccupied names stay unchanged; inherited standard/opaque namespaces and the general name-correspondence proof remain open.
- [x] I5e Forward closed constant assignments through generated-refinement instances and root configurations.
  Reuse equivalent root bindings and preserve literal bytes, including embedded assignment separators.
  Module-operator replacements and nonliteral configuration-value export retain separate open obligations.
- [x] I5f Bind generated source key paths through source declaration names before allocating formal symbols.
  Preserve escaped Swift names and the direct/projecting mapping routes.
  General key-path interpretation and source/query correspondence remain open.
- [ ] I6 Reconcile implementation coverage with the accepted-constructor inventory.
  Keep remaining implementation omissions separate from unfinished formal arguments.

Implementation checkboxes do not complete the six-link proof rows.

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

### Broad implementation checkpoint 6 November 2026

I2 through I4 extend existing production checks and existing test owners; they add no new checker, model or evaluator.
The CFG check now verifies the complete ordered directive text, including behavior, declarations, symmetry, views and postconditions.
The UTF-8 comparison preserves whitespace inside string constants; the producer's symmetry selection is passed explicitly.
The finite-call check reuses the independent integer encoder and orders quantified set members by their emitted text.
The existing behavior check also verifies the complete default `Spec` body when base fairness is empty.
Fairness terms, profile bodies, non-scalar/state-dependent invocation domains, token/namespace soundness and compiler/source correspondence remain open.

Measured baselines retained 18 ignored CFG corruptions, then four accepted `Spec` corruptions, one ignored string-whitespace change,
four valid expanded-call rejections and six valid quantified-call rejections.
An initial quantified control stopped at its coverage guard because parsing the fixture chose expanded calls; it receives no rejection credit.
The corrected control uses the existing runtime-built domain and requires the quantified branch.
Native runtime argument/state assertions passed before the measured output-check rejections.
After repair, all 63 selected tests passed on unchanged captured producer/test inputs.
No formal proof or hosted admission result is inferred, and no six-link proof row is completed by this checkpoint.

### Action-name allocation checkpoint 6 November 2026

The existing action-name owner exposed four collisions with `Spec`, `Init`, a state field and multi-action `Next`.
Native transition IDs remained valid; three cases reached export diagnostics and the state-field case returned a conflicting symbol.
The final name pass now runs after lowering, reserves known declarations, model values, binders and generated operators,
and retains the valid single unbound `Next` behavior. Source labels, declaration identities and action IDs are preserved.
The suffix-capture control also reserves an identity constant named `Spec__2`.

All 99 selected tests passed, including existing external-client checks, on unchanged captured producer/test bytes.
One intentionally stopped setup attempt and one Swift type-checker failure executed no tests and receive no rejection/proof credit.
No resource, tool, pin or timeout was changed to repair either setup issue.
Opaque/imported namespaces, non-action declaration collisions, physical name interpretation and the full namespace proof remain open.
This is implementation correspondence support, not completion of a six-link proof row.

### State-frame and refinement checkpoint 6 November 2026

The state-name owner exposed a generated `vars` alias colliding with an accepted state declaration.
The generated refinement owner also exposed a single-variable target referenced through an absent `vars` alias,
duplicate declarations for equal instance substitutions, and collisions between different substitutions of one instance.
The initial two-test baseline reported two issues. The expanded one-test refinement baseline reported six issues;
these overlap the initial export faults and are not eight independent semantic failures.

The existing renderer now omits the optional tuple alias when its name is occupied.
The existing generated-refinement linker substitutes the safety frame only when every actual declared abstract variable is mapped.
Equal instances are reused; different mappings get separate names and corresponding import provenance.
The final owner also checks a three-variable mapped frame in declaration order and the complete hidden `pc, row` alias fallback.

The six selected existing suites passed all 55 tests, including the native fairness and external-client controls.
After adding the frame guard cases, the final two-test refinement owner passed on unchanged captured inputs.
Its repeated test overlaps the earlier run; these counts must not be added as distinct cases.
A missing `try` caused a test-source compile failure with zero executed tests, and the first hidden-frame coverage guard
assumed the wrong declaration order. Both were corrected without production, resource or timeout changes.
Neither is a production semantic mismatch or proof-rejection result.

Canonical declaration/instance interpretation, general hidden or noncanonical mappings, other namespace collisions,
source correspondence, import semantics and refinement/checking kernels remain owned open obligations.
No formal proof or hosted admission is inferred, and no six-link proof row is complete.

### Generated refinement model-value checkpoint 6 November 2026

The generated-refinement linker copied the abstract module without its model-value bindings.
The existing enum/array target initialized correctly and retained both values in its own configuration,
but the concrete export lacked root declarations, instance substitutions and checking assignments for them.
The first unchanged-production baseline reported five issues in one test.
An expanded baseline reported ten checks of the same gap, including repeated and colliding imports;
these are overlapping checks, not fifteen independent faults or observed TLC mismatches.

The linker now reads canonical bare model-value assignments from the existing target configuration.
It reuses an established root binding for the same value or declares a fresh root symbol before the instance.
The instance substitution and root CFG retain the original model-value identity even when the symbol is renamed.
Repeated links reuse renamed bindings as well as instance declarations.
The same link step handles direct TLA and authored PlusCal bundles and retains their import provenance.
Target parameter assignments, invariant selection and constraints are not imported as concrete checks.

All 32 tests across the six selected existing suites passed on unchanged captured inputs.
The final changed three-test owner also passed, including repeat-after-collision and PlusCal controls.
Those three tests overlap the earlier run and must not be added as distinct cases.
No model, fixture, evaluator, checker family, theorem, pin, dependency, corpus, budget or timeout changed.

Canonical configuration/identifier interpretation, concrete abstract constants, module-operator replacement forwarding,
import/instance semantics and native/TLC refinement kernels remain owned open obligations.
These are implementation and regression receipts, not a SANY/TLC execution, new formal proof, hosted admission
or completion of a six-link proof row.

### State-symbol allocation checkpoint 6 November 2026

Accepted state fields named `Init`, `Next`, `Spec`, `TRUE` and `FALSE` occupied generated behavior or literal names.
The existing layout now retains each source declaration and ID while assigning its physical formal name once.
Rendering, authored PlusCal, generated field identities, complete state projections, graph metadata and lazy failure prefixes
use that formal name. Swift fields and action labels retain their source identity. Existing suffix names are reserved first.
The existing compiled fixture now exercises a public `State.Init`, its two initial values, successor and formal projection.

The first attempted baseline reached an unregistered test-label coverage guard and receives no collision-rejection credit.
The corrected unchanged-production baseline reported fifteen issues across five name variants; its expanded two-test baseline
reported twenty-seven overlapping checks, including emitted field metadata and failure-prefix keys.
Native values, transitions and failure-site guards passed before repair.

The first broad repair run executed ninety-eight tests and found three pinned module differences confined to the spelling
of the compiler-owned `Terminating` action. Its allocator now retains that owned name when free; occupied names still allocate
separately. The pinned proof inputs are unchanged. The final focused run passed all ninety-eight tests in ten suites,
including the existing external-client checks, on unchanged captured producer and test bytes.

Inherited standard and opaque namespaces, PlusCal keywords, other declaration kinds, general name correspondence,
complete source/IR/output interpretation and parent composition remain owned open obligations.
These are implementation and regression receipts, not a new formal proof, hosted admission or completion of a six-link row.

### Generated refinement binding checkpoint 6 November 2026

The generated linker retained identity model values but omitted closed constant assignments.
Its existing assignment reader now preserves the complete right-hand side after the first separator.
The existing symbol allocator forwards every unbound target assignment and reuses equivalent root bindings.
The existing configured fixture covers a boolean, a finite set and text containing an assignment separator,
including repeated imports and authored PlusCal. Explicit parameter mappings retain precedence.

The corrected unchanged-owner baseline executed one test with twelve overlapping export issues.
Its earlier fifteen-issue version unnecessarily requested a new boolean symbol; the final control requires reuse.
The first attempted target lacked the required configured-model conformance and executed no tests.
After repair, fifty tests passed. A reviewed concrete-field operand was then corrected to use its typed field identity;
all four refinement owner tests passed again in the subsequent binding baseline.

Both source-key-path overloads used the physical formal name before source binding.
Their actual compiler baseline reported two unresolved `Init__2` errors, one per direct/projecting argument case.
Escaped `default` source controls passed first. The existing field identity now exposes its unescaped Swift source name
internally; both builders use it for source lookup. Formal names remain the output identity.
The combined final run passed sixty-nine tests in ten selected suites on unchanged captured inputs,
including the existing external-consumer controls. These runs overlap and are not additive coverage totals.

Module-operator forwarding, nonliteral closed-constant configuration, general key-path ownership and interpretation,
source/query correspondence, complete observations and composition remain owned open obligations.
The pinned TLC parser's numerical token handling and `IntValue` arithmetic capacity are also separate from Swift `Int`
and from the mathematical integer rules. Primary-source inspection is not execution or a proof of that value correspondence.
All accepted forms remain in scope. No new formal proof, hosted admission or six-link closure follows from this checkpoint.

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
