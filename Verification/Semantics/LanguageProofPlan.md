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
  Module-operator replacements and general value correspondence retain separate open obligations.
- [x] I5d Keep public state names and declaration IDs while assigning distinct formal names for generated behavior and known declarations.
  Carry the same formal names through TLA/PlusCal, generated field identities, complete projections and initial failure prefixes.
  Unoccupied names stay unchanged; inherited standard/opaque namespaces and the general name-correspondence proof remain open.
- [x] I5e Forward closed constant assignments through generated-refinement instances and root configurations.
  Reuse equivalent root bindings and preserve literal bytes, including embedded assignment separators.
  Module-operator replacements and general formal-import configuration retain separate open obligations.
- [x] I5f Bind generated source key paths through source declaration names before allocating formal symbols.
  Preserve escaped Swift names and the direct/projecting mapping routes.
  General key-path interpretation and source/query correspondence remain open.
- [x] I5g Route expression-form integer configuration values through existing definitions.
  Keep the inclusive direct-token boundary and recurse through finite sets without restricting accepted values.
  Pinned evaluator capacity and general integer correspondence remain separate open obligations.
- [x] I5h Share definition-backed final binding for closed constants and runtime parameters.
  Preserve typed constant values through generated refinement links and omit parameter-value helpers from imported templates.
  Guard literal, nested model-value alias, direct compiler, generated, authored and selected profile transport in existing owners.
  General formal imports, module replacements, integer representation and implementation correspondence remain open.
- [x] I5i Keep generated nested-link allocation independent of runtime parameter values.
  Retain parameter ownership, unconfigured declaration/profile namespaces and potential helper names through copies.
  Reuse closed bindings, allocate each instance once across output forms, and retain source/native controls for both configurations.
  General namespace/source correspondence, formal imports and module-operator forwarding remain open.
- [x] I5j Preserve captured state reads in zero-based sequence literals and fills.
  Reuse the existing fresh-name allocator and one shared fill constructor; reserve root parameter names for rendered local binders.
  Retain the existing empty-sequence, membership and failure controls. General binder/source correspondence remains open.
- [ ] I6 Reconcile implementation coverage with the accepted-constructor inventory.
  Keep remaining implementation omissions separate from unfinished formal arguments.

Implementation checkboxes do not complete the six-link proof rows.

### I6 first-pass accepted-route inventory

This is a source-owner map and a finite expansion queue, not an acceptance or preservation certificate.
Each row is parameterized by the actual admitted child types and lexical placement.
Its guards must be reconciled with the parser, builder and type checker before I6 is complete.
Presence in an internal enum, a fixture or a dispatch switch does not establish membership or correctness.
Formal-core forms accepted inside `#spec` stay in scope even when they are not the application authoring style.

Common expression owners are `SpecParser.decodeTypedFacadeValue/decodeTypedFacadeExpr`,
`SourceTypeResolver`, `CompiledLowerer`, `CompiledTypeChecker`, `NativeSwiftEmitter`,
`CompiledEvaluator` and `CompiledTLARenderer`. The native interpreter and generated-code routes need separate links.
Type schemas include primitive and nominal values, finite/union/OneOf values, sets, arrays, dictionaries,
tuples and records recursively; a row does not silently replace them with integer examples.

| Route | Source forms and placement to reconcile | Distinct implementation link / parent consumer | Current limit |
| --- | --- | --- | --- |
| R01 Scalars | Integer spellings and signs, Bool/String literals, enum cases and bounds | `SourceIntegerLiteral`, `decodeEnumCase`, `decodeSwiftIntegerBound`; expression child rules | Literal regressions exist; source binding, representation and kernel correspondence open |
| R02 Reads | Scoped state/parameter/local reads, captures and bound values | `TypedFacadeScope`, layout IDs, binder scopes; `OrderedIntExpressionRule` read cases | Names repaired; arbitrary lexical ownership and prefix availability unproved |
| R03 Arithmetic | Plain Swift constant folding separately from typed formal `+ - * / %` and `integerDivided` | `decodeSwiftIntegerValue` versus formal operation lowering; `OrderedArithmeticFailures` | Overload/placement reconciliation and full target-Int/backend range open |
| R04 Boolean/conditional | `!`, `&&`, `||`, comparisons and supported conditional expressions | Lazy children, skipped failures; Boolean and conditional composition rules | Actual source/output and complete evaluation observations unproved |
| R05 Set construction | Closed Swift/SetExpr values separately from `SetExpr.literal` queries | `decodeTypedSetValue` versus `decodeTypedSetLiteral`; membership/Boolean parents | Purity, occurrence identity and admitted element types need explicit guards |
| R06 Set operations | Membership, subset, union/intersection/difference, cardinality, subsets, flattening and Sum | Typed collection methods, binders and finite-domain kernels | Parent rules and failure/order correspondence incomplete |
| R07 Bound expressions | Filtering, mapping, flatMapping, ForAll/Exists, expression Select and formal choice | Typed closure scope versus algorithm Choose; expression/Boolean consumers | Choice order, no-match and nested failures retain open links |
| R08 Swift arrays | Array literals/constructors, count, subscripts and edits | `SwiftArrayValue`, typed decoder offsets, tuple operations; sequence rules | Zero-based source versus formal indexing must be derived per route |
| R09 DSL sequences | TupleExpr and Pair/Triple/Quintuple, head/tail/append/concat/remove/prefix/select | One-based typed APIs and sequence constructor/composition rules | Compound types, dynamic bounds and complete failures open |
| R10 Zero-based sequences | Literals/fill, sequence domains, conversions and ZSequences calls | `decodeZeroBasedSequenceFill`, imported operator signatures | Representation and imported-operator correspondence open |
| R11 Dictionaries/functions | Swift dictionary literals/mapping, Function/PartialFunction, domain/keys/apply/update/override | Key/value schemas, totality and missing-key handling; function/assignment consumers | Type/placement guards and generic parent proof missing |
| R12 Function spaces | Functions domains, direct membership and converted membership | `functionSpaceMembership` optimization versus enumeration | Each capability and evaluation route needs its own correspondence |
| R13 Records/views/unions | Immutable nominal/structural fields, OneOf cases and checked `assuming` views | Source record metadata, projections, conversion and rollback | Existing view proofs are scoped; general typed representation open |
| R14 Random expressions | RandomSubset/RandomElement in initializers and queries | Sampling separately from complete initial support and selected reconstruction | Sampling bounds are not exhaustive outcomes; generic source correspondence open |
| R15 Checking effects | Registers/set, checkingLevel/checkingDiameter and PrintT | `SpecParser+Checking`, validation context and emitted obligations | Evaluation count, precedence and observable effects need the M0 contract |
| R16 State/initialization | sharedVar/localVar value or memberOf initialization at each legal scope; formal Variable forms | Dependency order, hidden state, event/prefix collection; initialization composition | Complete TLA branch events and arbitrary-prefix correspondence open |
| R17 Atomic writes | Assign to roots, collection entries and record paths; ordered repeated targets | `scheduleAtomicStatements`, pending writes and materialization; framed action composition | Actual substitution, failure rollback and all lvalue routes unproved |
| R18 Atomic branches | Do/When/Assert, Let/With/If/Either/Choose and bound-step arguments | Algorithm parser, branchwise continuation, action enumeration | Source guards, captures, labels and complete outcomes open |
| R19 Sequential control | Registered Algorithm, While/Goto/Stop/Skip and fallthrough | Algorithm lowering, pc/termination routing; `SingleAssignment` | General accepted control/use premises not discharged |
| R20 Processes | Static/configured Each populations, local/exposed families and scheduling | Process binders, family layout, native routing and authored PlusCal | Population/identity/frame proof and parent composition open |
| R21 Procedures/reuse | Procedure/Call/Return, recursion, bound Macro statements and local expressions | Hygienic substitution, argument capture and call-stack state | Full source and control-composition links missing |
| R22 Safety/reachability | Invariant, InitialStates selection and positive Reachable | Predicates, initial filtering and witness/verdict selection | Checking composition still assumes equal machine observations |
| R23 Temporal/fairness | Base temporal forms plus all/conditional/alwaysStep composition, bound/process/projected fairness and profiles | Temporal lowering, native checker and Spec/profile bodies | Existing bounded comparisons do not prove generic temporal preservation |
| R24 Validation | Registered Validation, Bind, check selection, expectations, exhaustive/decisive/simulation modes and limits | Scenario compiler, native validation, TLCConfiguration | Expected failures, unavailable results and resource limits need explicit contract links |
| R25 Symmetry | Registered immutable symmetry and applicable safety scenarios | Native unreduced graph versus formal quotient/checking | Orbit/quotient and selector correspondence open |
| R26 Formal functions/imports | FormalDefinition, local recursion/LetIn, registered formal calls, Import/Extends and replacements | Source/module parsing, typed function plans, native/TLA calls | Actual imported-code interpretation and generic function parents open |
| R27 Instances/refinement | Formal and generated Instance/Refinement, direct/projecting maps, configuration and hidden frames | Existing typed linker, mapping and refinement checkers | Closed-value forwarding repaired; general formal imports, module replacements and refinement proof open |
| R28 Export/observation | Native machine/projection, direct TLA, authored PlusCal, CFG/profiles and selected initial reconstruction | Existing emitters, bundle closure, codecs and checking kernels | Complete source-to-output/checker soundness remains open |
| R29 Builder assembly | Named registration, lexical aliases and parser/builder repetition routes | `parseSpecClosure`, `parseForLoop` and result-builder assembly before algorithm lowering | Reconcile actual accepted reachability; a parser branch or public builder method alone does not establish it |

I6 next actions are to reconcile exact signatures/type/placement guards within these rows,
separate actual missing/incorrect routes from implemented-but-unproved ones, and batch measured repairs by owner.
The first grouped transport repair, closed constants and generated refinement forwarding (R27/R28), is recorded under I5h.
The measured Boolean nested-link case is repaired under I5i. General template/source correspondence and formal-import bindings
retain separate obligations; each next repair still requires an actual accepted-route baseline.
The pinned integer-capacity/representation boundary (R01/R03) is a separate implementation blocker for a full-Int claim.
Candidate collection-member routes require public-API and source-guard evidence before being labelled defects or extended.
The reviewed R13 nominal-record route rejects custom initializers in the scanned record declaration, recursive or generic
record shapes, wrapped/lazy instance fields, accessors and missing explicit field types. Constructor arguments retain their labels
and source order before the existing complete-field check. This does not establish extension/imported binding ownership.
The enum collector separately guards its supported direct/exhaustive encoding forms and unique encoded case values;
dynamic encodings are diagnosed. These are source-guard observations, not a proof of either nominal representation.
The bounded R16 through R25 guard review also distinguishes independent parameterized Do (one through three typed domains)
from enclosing Algorithm control, procedure arities, process populations, registered property handles and validation selections.
The existing validation lowerer requires complete closed parameter bindings, rejects duplicate/foreign selections,
restricts simulation expectations and selects symmetry only with applicable checks. These guards do not establish kernel or verdict semantics.
R29 records a separate assembly obligation: the top-level loop parser expands a literal closed integer range in iteration/body order,
while public result-builder availability alone does not prove that a spelling is accepted by `#spec`.
I6 remains unchecked. All six proof links for these rows remain open unless an actual derived result is recorded.
After I5j, the next work package is M0/M1 and the literal/read/addition chain below.
The remaining inventory continues alongside it; it does not justify another unbounded implementation sweep before the pilot proof.

## M0 Observation contract and pilot domain

- [x] M0a Extend the existing integer-enumeration guard to unbounded sequence enumeration.
  Propagate the original capability error through generated and compiled initial collection.
  This local recovery result does not complete the observation contract below.
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
- [x] L3a Derive scalar literal extraction and recognized value-initializer acceptance from the actual code.
  The local proof below uses documented Swift semantics. Full L3 and its source/type/call-coverage obligations remain open.
- [ ] L4 Prove the accepted Swift literal tokens and TLA integer encoding denote that same `n`.
  Reuse the existing native decoder and signed-radix lemmas. Include zero, negative values and target bounds in the general argument.
- [ ] L5 Instantiate the literal child cases in the expression and initializer composition modules.
  Record the exact premises that these results discharge.
- [ ] L6 Retain the proof inputs and existing owner regressions for the exact implementation revision.
  Keep any unresolved source or decoder interpretation open. Do not promote a partial route to the complete literal family.

### Scalar literal code-case result 7 November 2026

Let `n` be any target `Int` value. The source constructor for this local result is `.value(.int(n))`.
Raw tokens, nominal values, conversions and membership domains retain separate obligations.
The result uses documented Swift pattern matching, value copies, arrays, dictionary updates and synthesized equality.
It is a manual proof of code cases, without a mechanically checked Swift translation or new TLAPS execution.

1. The source `orderedIntPlan` starts with one pending root and empty node/index arrays.
   With expected type `.int`, its literal arm copies `n` into `.literal(n)` and appends index one.
   The pending stack is empty after that arm. The return condition holds, yielding exactly that singleton plan.
   Neither the read-name set nor the renaming map supplies the payload.
2. The compiled overload first applies its `requireTypes` guard. Its literal arm also requires empty children.
   It then copies the integer payload into the same singleton plan.
   With `requireTypes: false`, this result supplies no result-type fact.
3. A successful singleton literal plan cannot come from a read or an unsupported root.
   A read has a different enum tag. An add root places its expanded frame below its child tasks.
   The add node is last after its child tasks complete. Unsupported roots return `nil`.
   Combined with the literal-arm guard, synthesized plan equality requires the same payload and empty children.
4. `verifyInitialIntExpression` always recognizes the stated source constructor.
   Normal return forces the lowered value initializer to contain that proper literal, without establishing its type.
   `verifyResolvedInitialIntExpression` also recognizes this proper lowered literal, so its unsupported-plan return cannot apply.
   Its successful resolved comparison requires the same payload, empty children and result type `.int`.
   When its variable type is `.int`, `ProgramResolver` invokes that check for a proper literal entry.
5. `CompiledEvaluator.evaluate` returns the stored literal before it creates evaluation tasks or a scope.
   Consequently, this expression returns `.integer(n)` without a model-state read or a model evaluation failure.
   In `CompiledRuntime` the value-initializer branch then copies the prior bindings, assigns the target and appends its continuation.
   With a fresh `VariableID`, the update preserves every prior binding and stores `.integer(n)` at that ID.
   This supplies the local map-update shape used by `GeneratedExtension`.
   Source-name and value projections remain M2 obligations.
   This local expression adds no failure event. It does not establish complete state assembly or later invariant outcomes.

The extractor, initializer-check, resolver, evaluator and runtime bodies for this argument remain unchanged from `d25a0818`.
The reviewed recovery helper invokes its callback only after a caught error, which the literal case does not produce.
These facts remove the local literal-payload and interpreter-dispatch assumptions for the stated entry shapes.
The existing literal cases in `OrderedIntExpressionRule` and `IntExpressionOutcomesSupplyInitializerOutcomes` can consume those child facts.
The full parent still needs source-constructor correspondence, matching initializer/target identities, value projections, type and call coverage, and both output interpretations.
No general visitor, layout, token, helper-binding, TLA/CFG or kernel soundness follows. L3, E LIT and all six-link rows remain open.

### Raw integer literal code-case result 7 November 2026

This result removes the numerical-decoder premise before the scalar literal result above.
Its input is a well-formed Swift integer literal syntax node, optionally preceded by the standard unary minus.
Its contextual type is the standard library `Int`, and its value `n` is representable by that target type.
The decoder and source context must have the same Int width and bounds. Host/target agreement remains an owned premise.
Decimal, binary, octal and hexadecimal spellings are covered, including separators, leading zeros and either case of hexadecimal digits.
Unlabeled single-expression parentheses are covered at the typed value decoder by finite recursion.
Type and operator binding are premises here. Arbitrary user-defined literal types and overloaded operators remain separate accepted routes.

The independent meaning is the positional numeral's signed integer value in the stated radix.
Evaluating this literal yields `n`, reads no model state, writes no model state and reaches no model evaluation failure.
The existing `SourceNode` literal case represents that value outcome as `Success(n)`.
Its branch does not inspect `state`, `reads`, `left`, `right` or either child history.
This local effect statement does not supply a failure-trace contract for other expressions.

The argument uses the documented [Swift literal grammar](https://docs.swift.org/latest/documentation/the-swift-programming-language/lexicalstructure/)
and [integer parsing contract](https://developer.apple.com/documentation/swift/fixedwidthinteger/init(_:radix:)).
Swift ignores numeral separators and leading zeros. The radix prefixes select bases two, eight and sixteen. Absence selects decimal.
For a representable integer string, conversion returns its represented value.
These language and standard-library operations are within the documented Swift trust boundary.

1. Let `m` be the unsigned magnitude of `n` and let the target width be `w`.
   Since `n` is representable, `m` fits the corresponding `UInt`, including `abs(Int.min)`.
   `SourceIntegerLiteral.value` removes separators and the applicable radix prefix, then parses exactly those digits into `m`.
   It neither changes the radix of a leading-zero decimal numeral nor interprets its digits as a state name.
2. In the positive case, `m <= Int.max`. Exact conversion returns `n`.
   In the negative case with `m == Int.min.magnitude`, the explicit minimum branch returns `Int.min` without negating it.
   Every other negative case has `m <= Int.max`. Exact conversion followed by safe negation returns `n`, including negative zero.
   Thus every stated input returns `n` rather than `nil`, without arithmetic overflow or a model-state operation.
3. The independent `OrderedIntSourceSyntaxCheck.integer` removes the same inert separators and selects the same radix.
   It parses the signed digit string directly as `Int`. Its representable result is also `n`.
   With requested type `.int`, its `value` caller therefore constructs `.value(.int(n))`.
   This discharges numerical agreement of the two decoders without treating their agreement as the definition of source meaning.
4. In `decodeStateExpr`, the two earlier probes require member access syntax, so neither captures the stated literal input.
   The integer branch therefore returns `.value(.int(n))`.
   In `decodeTypedFacadeValue`, `decodeSwiftIntegerValue` explicitly excludes a recognized direct literal.
   For an Int context the intervening enum, call, collection and member-access cases do not apply.
   The direct integer branch returns the same constructor. Parentheses recurse with the same expected type.
   `typedFacadeValueType` also recognizes the unwrapped literal as `.int`.
5. This constructor fact and the scalar literal code-case result give the same payload in the resolved literal and its empty child list.
   They also give compiled interpretation `.integer(n)` for the checked Int initializer route.
   `CompiledValue.rendered(using:)` maps that scalar directly to `.int(n)` without consulting layout names.
   For a fresh target and a typed prior binding map, `IntExpressionOutcomesSupplyInitializerOutcomes`
   and `InitializerLeafRetainsCompleteStatesAndFailures` then give the singleton extension and empty failure set.
   Here `SwiftIntMin` and `SwiftIntMax` denote those same bounds, and `IntInitializationDomains` remains a premise.
   This literal leaf uses the already derived child value, rather than assuming an arbitrary matching expression history.
   The caller still must supply the matching source target, fresh ID, typed prior map and value projection.

This is a manual code-case proof under documented Swift semantics, not a mechanically checked Swift translation or new TLAPS execution.
It assumes faithful SwiftSyntax node/token input and standard type/operator binding. It does not prove those owned links.
Formal `Int.min`/`Int.max` member access, conversions, enum encoding, constant arithmetic and other initializer placements remain distinct routes.
Generated Swift token/scope interpretation, complete TLA initialization, actual TLC integer capacity and parent call coverage remain open.
L1 through L6 and E LIT remain open as complete tasks. The two local code-case results are partial inputs to them.

The existing `AlgorithmBuilderParsingTests.parsedAndBuiltLiteralInitializersShareIdentity` owner now checks independent expected values
for fifteen integer spellings through actual parsing, compilation and compiled initial outcomes.
It retains the prior Bool, String and array variants, checks one state and no failures, and still checks builder identity.
The focused run passed three tests in three suites, including the existing escaped-string and signed-TLA-rendering owners.
All 1,201 captured inputs remained unchanged during execution. These are regression receipts, not universal proof or hosted admission.
No model, fixture, production decoder, evaluator, checker family or formal theorem was added or changed.

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

### Integer configuration transport checkpoint 6 November 2026

The parameter exporter classified every nonnegative integer as a direct CFG literal, while the existing integer formatter
emits arithmetic expressions above one billion. The existing value-classification guard now retains direct tokens only
through that inclusive boundary. Larger and negative values, including values inside finite sets, use the existing
definition-backed configuration path. No accepted value or DSL form was rejected.

The unchanged-production baseline executed three tests with eighteen overlapping direct/authored encoding issues
for three new argument cases. The inclusive direct-literal control and previous value cases passed.
The repaired configuration suites passed all twenty-four tests on unchanged captured inputs.
This is a transport regression, not TLC execution, an integer arithmetic proof or hosted admission.
The pinned parser and arithmetic capacity, nonliteral closed constants and full source/value correspondence remain open.

### Closed constant and refinement transport checkpoint 6 November 2026

The existing generated refinement fixture admitted a negative closed constant, but the pre-fix exporter wrote its
expression directly into CFG. One actual test failed at the missing definition-backed binding after its native initial
state and prior literal controls passed. That requirement stopped the run before the later quoted/import assertions;
those assertions receive only the post-fix execution credit below.

The final artifact constructor now applies the existing literal-versus-definition distinction to both closed constants
and runtime parameters. Generated exports carry typed `ConstantDecl` values into this boundary, and refinements retain
those values instead of parsing rendered value expressions. All three handwritten artifact-constructor callers were
migrated to the required underscored metadata argument. Application model State, Action and Transition APIs are unchanged.
Definition expressions use actual root aliases for model values, preserving string contents and record field names.
The linker imports the unconfigured module template because its explicit substitutions bind each target parameter.
The existing direct abstract-model case now reuses one module across distinct parameter configurations.
Template invariance through nested configuration-dependent constant reuse and name allocation is not established.

The first focused run passed forty-four tests in seven suites on all 1,201 unchanged captured inputs.
The final run passed the same forty-four tests after adding independent fixed literal expectations, a profile-only helper
collision, nested model-value aliases, direct compiled constant export and distinct configured imports in existing owners.
Production bytes were unchanged between the runs. These overlapping runs are not additive coverage totals.
No local TLC execution, new theorem, six-link closure, binary reproduction or hosted admission follows from them.

The reviewed macro guard is exactly two unlabeled arguments, no trailing closure, a literal name and a value decoded in
empty source scope that the existing static-value checker accepts. That checker admits value nodes and recursively closed
set literals. The formal-core `Constant` API has its separate `TLAValueConvertible` route; its broader values do not prove
that corresponding macro spellings are accepted. General formal-import configuration, module-operator forwarding,
pinned integer capacity, helper/decoder soundness and source-to-output correspondence remain explicit owned boundaries.
All proof milestones and I6 remain open.

### Nested configuration-linking checkpoint 6 November 2026

The existing stuttering refinement fixture now uses a finite Boolean parameter in a tautological stay guard.
Existing callers supply their configuration explicitly. There is no new fixture/model type, corpus case or state field.
The first variation failed compilation because the parameter was unused; zero tests executed and no semantic credit
was assigned. After the guard made its use explicit, the unchanged-production baseline executed one actual test with
two issues: different module text across the Boolean configurations and a real duplicate-module error on the second
nested import. Earlier native safety/fairness, shifted/repeated-link and provenance controls passed first.

Runtime parameter equality in one configuration is no longer treated as a closed constant binding.
The final artifact retains parameter ownership and the original declaration/profile namespace.
Helper prefixes ignore serialized runtime values. Potential helper names are reserved even when a current literal
parameter needs no helper. Each instance name is chosen once for the actual, authored/profile and unconfigured exports.
Only the initial namespace and current template are retained, rather than every intermediate template version.
These are compiler/linker implementation changes; their general correspondence proof remains open.

The final focused run passed forty-eight tests in eight suites on all 1,201 unchanged captured inputs.
It checks native safety/fairness under both Boolean configurations, actual parent import of both nested instances,
closed-binding ownership, repeated-instance provenance, a helper/property-name collision and namespace-looking string data.
The finite fixture guards and fixed output expectations are regression evidence, not an all-program invariance proof.
General formal-import configuration, module replacements, integer representation, complete observations and all six-link
proof rows remain open. No local TLC run, new formal proof, binary reproduction or hosted admission is inferred.

### Sequence capture checkpoint 6 November 2026

Status: I5j implementation repaired; E READ, R10, I6 and every six-link proof row remain open.
An existing sequence fixture now deliberately names its earlier state and configuration parameter like the generated indices.
Its literal and filled sequence values have independent element expectations; the bounds and existing fixture type are unchanged.
The unchanged-production baseline at `9f68362f` executed one test with forty-five issues:
forty-four initial-value/membership discrepancies and one exported binder/configuration-constant collision.
The native binder identities alone did not prevent the separate rendered-name collision.

Both fill construction routes now share the existing sequence-construction family and avoid free state-variable names.
Literal construction uses the same existing freshness operation for all element expressions.
Ordinary compiled binder allocation also reserves root runtime parameter names before choosing a rendered local name.
This repairs the measured captures without changing public APIs, accepted forms, expression types or evaluator/checker families.
General source-generated hygiene, exact-name control binders, formal imports and name/identity correspondence remain open.

The final guarded run passed sixty-six tests across nine existing suites, including the previously failing owner,
empty and large sequence cases, failure controls, configuration, indexing, mapping, lexical bindings and record siblings.
All 1,201 captured inputs stayed unchanged. The whole log is 85,667 bytes,
SHA256 `7e51ce4c2ffe4113062332f35501b6175e5d4036f7909ca9e9e2567f38e02ba3`.
Only this plan changed afterward. These are regression receipts; no local TLC execution, formal proof or hosted admission is inferred.

### Initial enumeration checkpoint 7 November 2026

Status: M0a implementation repaired. M0.1 through M0.5 remain open.
An attempt to enumerate `Seq(S)` for a nonempty element set cannot return a complete finite list of initial states.
For each natural length, repetition of one element produces a different valid sequence.
The existing recovery helper nevertheless converted that capability error into a reached model failure.
The unchanged-production baseline at `d25a0818` ran one existing test with two issues.
Both generated and compiled `initialOutcomes()` returned zero states and one sequence-enumeration failure event at initializer one.
The selected-state and transition controls, including a 10,000-element witness, ran before those failing expectations.

The shared helper now propagates sequence-enumeration errors through both catch arms, matching its existing integer-domain guard.
This local exception-routing result follows directly from the two guards: each original error leaves its catch arm before the recovery callback.
Neither guard returns a completed empty result. Selected-state construction still checks membership without requesting full enumeration.
Ordinary mapped model errors retain the existing callback and event collection.
Finite collection cardinality, power-set size, recursion depth, sampled execution and checking-context classifications retain separate obligations.

The guarded repair run passed seventeen tests across five existing suites on all 1,201 unchanged captured inputs.
The owners cover generated/compiled sequence outcomes, mathematical integers, ordinary initial failures, output checks and support binding.
The whole log is 75,594 bytes, SHA256 `443c0635de9163d1106f41a013c9dbfe4066e059c9c196ac2b995a2edd60d9b5`.
Only this plan changed afterward. The repair introduces no new model, fixture type, evaluator/checker, API signature, domain bound or resource limit.
The local literal code-case result has its own reasoning above. Neither result completes E LIT, M0, hosted admission or whole-language preservation.

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
