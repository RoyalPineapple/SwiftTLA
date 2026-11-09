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
- [x] I5k Bind authored procedure parameters and their backing state to the same allocated formal name.
  Preserve parameter/variable IDs, genuine occupants and runtime call values; cover unoccupied and occupied names in the existing owner.
- [x] I5l Reserve `Terminating` for actual generated or authored termination contexts, preserving a free formal-core action name.
  Keep ordinary action IDs, enablement and successor values unchanged. General namespace/control correspondence remains open.
- [x] I5m Reserve imported standard operator names during variable and action allocation.
  Preserve source IDs, public field names and names from absent modules. Other declaration and import namespaces remain open.
- [x] I5n Retain every reached native action failure through the existing validation callback.
  Preserve selected-first convenience results, callback stopping, callback errors and failure multiplicity.
  Complete action event sites, before-prefix values and TLA event correspondence remain open.
- [x] I5o Prevent lexical binders from capturing selected standard-module operators.
  Finalize binder names against the same actual import set as states and actions, preserving binder identities.
  Other declaration namespaces, opaque imports and general binding correspondence remain open.
- [x] I5p Keep source property identities and labels while allocating distinct formal property names.
  Carry invariant, reachability, temporal and refinement names through behavior, CFG, authored export and native formal projection.
  Preserve selected property IDs and source-facing descriptions. Other declarations, opaque imports and general binding correspondence remain open.
- [x] I5q Check Init, stuttering Next and the complete frame for emitted base and fairness-profile specifications.
  Apply to outputs with state or named actions. Keep whole-body equality when fairness is empty.
  Retain the existing action-call and configuration checks.
  Projected, bound and mixed unsupported fairness tails, checker soundness and reconstructed export-metadata correspondence remain open. I5u checks the simple unprojected family.
- [x] I5r Allocate formal operator names against owning-module standard exports and generated declarations, preserving source IDs through imports and qualified instances.
  The existing binding table carries resolved exported names; local operators and binders also reserve actual imported aliases.
  Existing owners cover direct and qualified calls, recursion, explicit refinement targets and a measured lexical capture.
  Owner exports are also finalized against model values retained across the compiled closure, then propagated through direct imports and qualified instances.
  The existing import owner reproduced a caller model-value collision; the shared repair passed 52 focused tests while retaining model values, native results and lexical/standard reservations.
  Importer-only reserved symbols, late configured/runtime values, opaque imports and general namespace correspondence remain open.

- [x] I5s Emit checked Int initialization failure-event sets across supported nondeterministic prefixes.
  The existing renderer and checker retain supported value and membership-domain addition failures with site, operands and full before-prefix. Lazy domain branches preserve their valid sibling. The public compiled and resolved exports produce matching complete TLA modules for the existing domain variants.
  The final diagnostic passed 103 tests in six existing suites, including changed-input guards and actual event-loss rejections. Schema v5 prepares an emitted event-set theorem and an empty-set proof control; their execution requires separate evidence. Order, multiplicity, other failure kinds and generic correspondence remain open.

- [x] I5t Keep runtime parameter constants distinct from generated declarations and project their actual formal names into generated configuration metadata.
  Reuse the existing declaration reservations and binder IDs. Source parameter identities, Swift configuration fields and ordinary names remain unchanged.
  The existing owner reproduced both generated-name collisions and stale metadata for allocated aliases. The repair passed 30 tests in eight existing suites, including external-consumer contracts. General namespace and source/backend correspondence remain open.

- [x] I5u Check complete unprojected fairness clauses for Next, unbound actions and unbound action groups.
  When every clause in a base or profile specification has these forms, derive its strength, full frame, action identities and clause list directly from typed metadata.
  Other lists retain the existing Init/Next/frame check only. The executed baseline accepted 30 changed clauses; the final existing-owner regression rejects them and passed 49 tests in seven suites.
  This repairs an output-check gap. Generic fairness meaning, source/metadata correspondence and checker soundness remain open.

- [x] I5v Allocate legal TLA declaration names for accepted fairness-token prefixes and letterless identifiers.
  Preserve source identities, Swift names and values while allocating state, action, property, runtime-parameter and ordinary value-binder names.
  Reuse existing collision handling; leave source admission unchanged. Five existing owners reproduced 35 emitted-name issues before the repair.
  The guarded repair passed 181 tests in nine suites. Operator, module, constant/model-value, record-payload and explicit external-contract namespaces remain separate owned boundaries; general name correspondence remains open.

- [x] I5w Allocate physical operator names without changing source lookup or operator identity.
  Apply the existing stem and collision rules to owned operator IDs, including local recursion and operator-valued formal parameters; escape their accepted keyword spellings.
  Direct and qualified imports retain the callee's allocated names. Three existing owners reproduced 19 emitted-name issues; the repair passed 212 tests in twelve suites.
  I5x covers model-parameter keywords. I5y covers predefined names in allocated declarations and binders. Explicit contracts and general namespace/source/backend correspondence remain open.

- [x] I5x Preserve accepted model-parameter keyword names while allocating legal formal constants.
  Reuse the existing reserved-word set in the shared physical stem; keep source admission, parameter references, public names and configuration fields unchanged.
  The executed baseline reported nine naming issues while accepted-source and label/identity controls passed. The repair passed 217 tests in thirteen suites.
  This is implementation evidence. I5y covers predefined names in allocated declarations and binders. Arbitrary value encoding, explicit contracts and general name correspondence remain open.

- [x] I5y Reserve predefined TLA names during physical declaration and binder allocation.
  Reuse existing collision allocators for actions, properties, model parameters, lexical binders and owned operators. Preserve state aliases and imported callee names.
  Source admission, public names, identities and raw values remain unchanged. Nine baseline tests reported 49 naming issues; separate raw-value controls passed.
  The guarded repair passed 240 tests in fourteen suites, including external Swift consumers. Constants/model values and explicit module contracts retain separate encoding obligations.
  This is implementation evidence. General namespace correspondence, SANY interpretation and all complete six-link proof rows remain open.

- [x] I5z Allocate physical formal-instance namespaces while retaining source handles and IDs.
  Reuse the existing stem and collision allocator after all module bindings and model values are known. Keep source lookup and structural provenance unchanged.
  Carry allocated names through qualified calls, both refinement exporters, imported configuration forwarding and authored PlusCal declarations.
  Existing owners reproduced naming, output-guard and lexical-capture failures. The guarded repair passed 207 tests in fourteen suites, including the external consumer contract.
  Module names, generated-instance contracts, raw values and general namespace/source/backend interpretation remain open. This closes no complete six-link proof row.

- [x] I5aa Allocate module-file names consistently across headers, references and export metadata.
  Reuse the existing stem and freshness allocator for root and imported user modules, reserving standard module names and enclosing refinement files.
  Preserve public source names, compilation identity and structural provenance paths. Carry physical names through TLA, authored PlusCal, generated Swift exports, configuration references and ownership/dependency records.
  Existing owners reproduced prefix, letterless, standard-name and nested import collisions. The guarded repair passed 206 tests in fourteen suites, including the external generated Swift consumer contract.
  This is implementation evidence. General namespace soundness, generated/opaque module contracts, raw values, SANY interpretation and all complete six-link proof rows remain open.

- [x] I5ab Preserve record keys through legal TLA construction, access and configured-value transport.
  Keep ordinary and keyword field tokens. Use string-keyed function syntax for other unique record keys and the empty record, retaining the original data names.
  Carry compiled field operands once through an eager tuple before selection; retain existing generic record-set rendering when the bare-field optimization does not apply.
  Reuse raw function formatting with capture avoidance and mark encoded configuration definitions through the existing formal-string protocol.
  Existing owners reproduced key, empty-constructor and encoding faults. A separate wrong-candidate baseline exposed the missing eager carrier while native evaluation raised the exact unread-field division-by-zero error.
  The corrected guarded run passed 171 tests in sixteen suites. This is implementation evidence, not SANY/TLC execution or a complete record proof. Duplicate raw keys, nested function/effectful children, generic projection, source/backend/kernel interpretation and complete observations remain open.

- [x] I5ac Preserve literal constructors in source keys and compilation fingerprints.
  Encode source values with the existing tagged length format, independently of TLA formatting.
  Retain raw record field order and deterministic set/function ordering without conversion to compiled values.
  The existing owner reproduced three collisions in both source keys and compiled identities. The repair passed 241 tests in twenty suites.
  Opaque fingerprints change. Source names, declaration IDs, values and accepted forms remain unchanged.
  This is implementation evidence. General source-key injectivity, source/ID/backend interpretation and all complete six-link proof rows remain open.

- [x] I5ad Preserve closed-constant source names and values through legal output symbols.
  Allocate physical names in existing output metadata after source reads resolve to literal values.
  Reuse existing stem and freshness rules across declarations, assumptions, configuration, generated exports, refinements and authored PlusCal.
  Reserve known imported model-value tokens before parent bindings and aliases. Keep the existing collision guard.
  Two existing owners reproduced 37 output issues. A parent/child case exposed one additional collision in the first candidate.
  The expanded repair passed 193 tests in eighteen suites, including the external compiler contract.
  Source declarations, values, IDs, accepted forms and raw model-value tokens remain unchanged.
  Identity model-value encoding, later sibling/generated/runtime namespaces and general source/backend/observation correspondence retain separate obligations.
  This is an implementation result. No complete six-link proof row or whole-language preservation follows.

- [x] I5ae Keep operational action errors out of completed model-failure observations.
  Share the existing six excluded initial-recovery cases through the existing error enum.
  Apply that classification to independent alternatives, generated action parts and visitors, and the default machine visitor.
  Preserve logical failure retention, callback errors, stopping and state rollback. Execution limits propagate in their original error channel.
  The actual baseline reported twelve issues across two existing owners. The repair passed 172 tests in twenty-two suites.
  The mandatory output check rejects a removed classification guard. Existing Swift witnesses change only their catch conditions.
  Full error/source correspondence, complete event sites and prefixes, TLA observations and checker/kernel soundness remain open.
  This is an implementation result. No complete six-link proof row or whole-language preservation follows.

- [x] I5af Omit bounded loop bodies for literal or lexically known false Boolean filters.
  Reuse existing tuple syntax and source-scope values, after the existing literal-range guard.
  Preserve unfiltered and true-filter order, following actions and their values. Add no evaluator or source restriction.
  The actual builder/peer baseline reported twelve issues across sixty-three tests. The repair passed 255 tests in twelve suites.
  Other accepted filter predicates remained unfiltered at this checkpoint. I5ag extends the implementation coverage.
  Generic filtering/effects, binding/type interpretation, full assembly and Swift/TLA correspondence remain open. No complete six-link row follows.

- [x] I5ag Preserve known per-index primitive predicates during bounded builder-loop assembly.
  Extend the existing integer constant folder with Boolean values, comparisons and short circuit, retaining Swift checked arithmetic and signed quotient/remainder.
  Use existing scoped decoding so the loop variable overrides a same-named module constant. Supply missing Boolean-literal shape metadata in the existing type inference.
  The committed-producer baseline reported 36 issues across twelve cases. A first repair exposed nine issues in three Boolean-alias cases; the corrected repair passed 270 tests in fourteen suites.
  The primary owner compares 21 predicates with independently selected indices, actual Swift builder registration, peer action/API metadata and compiled successor values, including a following action.
  Unknown filters retain their accepted path. Unhandled scalar spellings, contextual types, operator binding, effects, traps and full source/IR/backend correspondence remain open. This closes no complete six-link row.

- [ ] I5ah Reconcile custom record witnesses with structural formal identity.
  Repair graph keys and successor deduplication using resolved fields, including nested values. Reconcile modeled equality and collection-key behavior as separate related routes.
  Preserve accepted records. Do not replace the obligation with a rejection of existing custom witnesses or a graph-key-only claim.
  Modeled `==`/`!=` now bind each operand once and reuse structural comparison over resolved fields, including nested collections, instead of invoking nominal record witnesses.
  The existing custom-witness record owner reproduced three false-invariant issues in five executed tests. The repair passed 50 tests in nine suites, including actual initial/reached predicates, a nested sequence, transitions, complete two-state checking and external-client contracts.
  Existing cross-type comparison now descends through same-type composites and sorts nested set/map members structurally; finite cases compare their encoded values. This cannot recover members already collapsed by native storage.
  Receipts are in `.git/swifttla-proof-evidence/record-predicate-identity-2026-11-09/` in the primary checkout.
  Public generated State identity now descends resolved record fields and contained arrays, sets, maps and unions, bypassing nominal record equality/hash witnesses. Existing snapshot synthesis, successor deduplication and both traversal indexes consume it.
  The existing local-choice owner reproduced a lost count-2 state and missed Bounded failure: five executed baseline tests reported sixteen issues. The corrected repair retains both choices, rejects ambiguous send without committing, and reports that reached failure through graph and streaming validation.
  Shallow typed helper functions keep generated syntax bounded without raising parser resources. The standard Hasher is bound through the existing library namespace; an unused source Swift alias remains accepted. Unordered members match one-to-one and hash without iteration-order dependence; storage collapse is still separate.
  The final focused run passed 146 tests in sixteen suites, including history-only/archive-only key differences, equal reordered sets, a twelve-state signed-block graph and external clients. Broader checks exposed a finite-union size regression in the earlier comparison change; its correction preserves the existing 256-case guard and the named-alias/noncanonical-finite paths.
  Receipts are in `.git/swifttla-proof-evidence/record-state-identity-2026-11-09/` in the primary checkout. Four introduced compilation/fixture failures executed zero tests; the subsequent 112-test run had one size-guard issue and earns no all-pass credit. Snapshot and State constructor guard bodies remain byte-exact.
  Generated Configuration now reuses the same resolved-field equality and hashing. The existing mismatch owner reproduced equal configurations for record values 1/2, collapsed configuration keys and mixed admission by both actual exploration paths: ten baseline tests reported five issues in one case.
  The repair passed 103 tests in fourteen suites, plus the existing separate-package typed client. Same-value configurations, direct initial values, structural hash coherence, both mismatch guards and earlier state-key controls pass. Configuration domain validation remains unchanged; record membership and native storage remain separate open boundaries.
  Receipts are in `.git/swifttla-proof-evidence/record-configuration-identity-2026-11-09/` in the primary checkout. Initial fixture field-access compilation failure executed zero tests; the corrected fixture uses the existing expression facade and formal set literal.
  Generated Action equality and hashing now share the resolved-type identity traversal, retaining case tags and every public argument field. The same metadata zip supplies associated types in the enum declaration and its witnesses.
  The existing record-action owner reproduced four issues in ten baseline tests: record arguments 1/2 produced distinct states and formal calls, but typed actions compared equal and a dictionary label cache overwrote the first call.
  The repair passed 108 tests in fifteen suites, including direct sends and literal formal payloads, same-argument/hash/tag controls, retained label-cache entries, earlier State/Configuration keys, primitive action/actor execution, unchanged output guards and the existing separate-package typed client.
  Receipts are in `.git/swifttla-proof-evidence/record-action-identity-2026-11-09/` in the primary checkout. The native record-set domain remains separate: this direct-argument repair does not claim complete action enumeration or generic fairness/label interpretation.
  Explicit record set literals and constant set values now retain typed members in arrays, deduplicating with the existing structural comparator. Action/initial enumeration, configuration and selected-action/initial membership, and the existing symbolic membership predicate reuse this path. All member expressions are built before deduplication; no formal projection is forced.
  The existing owners reproduced nineteen issues in ten baseline tests: missing count-2 candidates and graph state, accepted action/configuration values outside the domain, and an invalid selected initial state. The repaired graph has three states and twelve correctly labeled edges; repeated domain members produce one choice and repeated singleton initial values produce one initial state. Rejected sends leave the snapshot unchanged.
  The focused run passed 131 tests in twenty-one suites, including earlier identity controls, scalar/sequence/function membership, output guards and the separate-package typed client. Receipts are in `.git/swifttla-proof-evidence/record-finite-domain-2026-11-09/` in the primary checkout. The first repair failed compilation before tests because it called a Core-internal sort helper; replacing that call with its standard sort preserved module visibility.
  Source Swift Set construction before formalization remains separate from explicit formal SetExpr source; static parsing/builder correspondence for arbitrary custom witnesses is not proved. Other domains and storage already collapsed by native collections, plus quantifier/map/filter/fold consumers, remain open. Structural domain deduplication currently scans quadratically.
  Value-initializer matching now uses the existing structural order in both directions for resolved record-containing types, retaining the original scalar guard and short-circuit path. No formal projection is forced.
  The existing public initial-selection owner reproduced three wrong requests accepted through coarse record witnesses: a packet, its sequence and its set. Correct values and reordered sets stay accepted; changed values now throw invalidInitialState. An occurrence-checked control makes the actual output compare the candidate with itself, and the existing selection checker rejects it at the intended path.
  The focused run passed 76 tests in eleven suites, including dependent and random-subset initialization, record unions and the separate-package typed client. Receipts are in `.git/swifttla-proof-evidence/record-value-initial-matching-2026-11-09/` in the primary checkout. The checker pins the typed comparator binding and selected/candidate operands independently; general comparator-body interpretation remains an owned boundary.
  Snapshot identity now includes the already structural public State and resolved hidden record-containing fields. Parallel-update merging supplies a compiler-owned structural equivalence to the existing Sendable helper; absent writes and the scalar default retain their prior behavior.
  The existing process-local and action owners reproduced 26 issues in eleven baseline tests: four hidden-distinct targets collapsed to two, five graph nodes collapsed to three, and contradictory record writes committed. Matching writes, prior public choices and valid selections remain positive controls. The repaired graph retains all five states; contradictory sends reject without committing.
  The existing flat child equality/hash traversal is reused byte-for-byte across public identity, hidden identity and merge equivalence. An initial nested ordering expansion produced malformed parser output in KVsnap; the flat traversal accepts it without changing nesting, stack, resource or type limits. Earlier compile/setup failures executed zero tests and earn no semantic rejection credit.
  The focused run passed 116 tests in 18 suites, including scalar merge witnesses, output checks, process/control/initial failures, actual KVsnap compilation and the separate-package typed client. Receipts are in `.git/swifttla-proof-evidence/record-hidden-merge-2026-11-09/` in the primary checkout. The existing fixture graph cap changes from three to five solely to cover the added hidden-state branches; workflow/tool resource budgets stay unchanged.
  Snapshot field layout and identity signatures remain checked; the merge check pins the complete surrounding rule and typed current/incoming relation binding. The shared helper bodies, public/hidden layout split, containsNominalRecord/type routing, leaf/finite/union embeddings and callback denotation remain owned proof boundaries.
  Native collection storage and other selected-domain/collection-consumer routes remain open. Native leaf String/enum/view identity, general identity-method interpretation and graph/checker mathematical correspondence also remain owned. This identity work closes no complete six-link row.

- [ ] I5ai Preserve string identity across raw enum values and checked string views.
  Default String-enum extraction now uses the inherited canonical string encoding. Explicit `.string(rawValue)` and `.constant(rawValue)` keep their raw encodings.
  Declaration uniqueness still checks the prior raw spellings for defaults, retaining Unicode aliases and all case names. Finite views use the distinct encoded members without changing public finite-shape or core-domain validation policy.
  The committed-producer baseline reported three projection/decoder/Init issues in 34 tests. Review exposed an introduced alias rejection; its correction passed 85 tests in seven suites, including actual typed alias projection, view round trip and transition, plus an explicit raw-string control.
  Receipts are in `.git/swifttla-proof-evidence/default-enum-string-identity-2026-11-09/` in the primary checkout. Initial test-authoring compilation failure has zero semantic rejection credit.
  Raw enum-to-string views still cross native equality, collections and snapshot identity with different semantics. Nominal alias reconstitution, source/core conformance meaning and Unicode/version alignment remain owned boundaries. A changed encoder or equality operator alone does not complete this task or a six-link proof row.

- [x] I5aj Carry raw fairness enabledness through constrained exploration and checking.
  Actual successor traversal now retains selected-scope enabledness before pruning, through both graph routes, scenario dispatch and independent native validation. Conditional temporal checks retain the supplied data.
  Complete graphs retain fairness for later refinement queries; requested query errors keep their original error, decisive safety/model failures keep priority, and incomplete summaries expose no complete fairness data. No action replay reconstructs enabledness.
  The published-producer baseline reported wrong verdicts in both graph APIs; the existing kernel owner separately exposed dropped conditional enabledness. Review reproduced and corrected a delayed-refinement regression before publication.
  The final guarded run passed 139 tests in sixteen suites with all 1201 captured inputs exact. Receipts are in `.git/swifttla-proof-evidence/constraint-fairness-enabledness-2026-11-08/` in the primary checkout.
  Handwritten scenario overrides must accept and forward the new fairness parameter. Projection meaning/evaluation, view quotient adequacy, record/string identity and source/TLA/kernel correspondence remain open; this wiring repair completes no six-link proof row.

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
| R02 Reads | Scoped state/parameter/local reads, captures and bound values | `TypedFacadeScope`, layout IDs, binder scopes; `OrderedIntExpressionRule` read cases | Root Int initializer binding/availability has a scoped code-case argument below; arbitrary lexical ownership, captures and full correspondence remain open |
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
| R29 Builder assembly | Named registration, lexical aliases and parser/builder repetition routes | `parseSpecClosure`, `parseForLoop` and result-builder assembly before algorithm lowering | Known primitive per-index filters are repaired in I5ag; other accepted filters can still expand without filtering. General source assembly remains open. |

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
R29 records a separate assembly obligation: the top-level loop parser expands a literal closed integer range in iteration/body order.
It omits the body for the known primitive predicates described in I5ag when their per-index result is false.
Other accepted filters still take the unfiltered path, an unresolved implementation gap.
Public result-builder availability alone does not prove that a spelling is accepted by `#spec`.
I6 remains unchecked. All six proof links for these rows remain open unless an actual derived result is recorded.
After I5j, the next work package is M0/M1 and the literal/read/addition chain below.
The remaining inventory continues alongside it; it does not justify another unbounded implementation sweep before the pilot proof.

## M0 Observation contract and pilot domain

- [x] M0a Extend the existing integer-enumeration guard to unbounded sequence enumeration.
  Propagate the original capability error through generated and compiled initial collection.
  This local recovery result does not complete the observation contract below.
- [x] M0b Propagate finite collection representation limits through the same branch handler.
  Keep powerset, range and function-space capacity errors out of completed model-failure observations.
  The measured baseline, focused repair result and ordered-history contract appear below. This does not complete the observation contract.
- [x] M0c Separate call-depth and missing-context errors from logical recursive-domain failures in existing initial recovery.
  Preserve original operational errors. Retain logical function-domain failures in both generated and compiled collection.
  Both existing-owner baselines failed for the intended reasons. The focused repair passed 87 tests in twelve suites.
  This is an implemented routing result, not completion of the observation or checking proofs.
- [x] M0d Check the existing zero-variable initial function with the complete output contract.
  Distinguish one empty state from no states. The accepted assumption-only baseline exposed a missed corruption.
  The one-line guard repair passed 56 tests in six existing suites. This is an output-check result, not complete initialization proof.
- [ ] M0.1 Define complete observations in the existing outcome rules.
  Include state identity, labels, disabled behavior, failure site, payload, preceding bindings and selected outcomes.
  Separate logical domains, enumeration capability, execution limits and model failures.
- [ ] M0.2 Resolve the failure-set and event-trace relationship.
  Specify source-required order, multiplicity and first-failure selection. State the preservation obligation for every observation projection.
- [x] M0.3 State the exact existing pilot domain.
  Include parameter-free deterministic Int initialization, literal/read/add expressions, sequential ordered root writes, hidden control and default checking.
- [ ] M0.4 Map each pilot spelling and placement to its actual parser, builder, compiled constructor and diagnostic route.
  Record accepted forms outside this instance as open. Do not reject them or treat unsupported-checker returns as certificates.
  Include overload selection, constant folding and target-dependent Int bounds.
- [x] M0.5 Define the complete-program theorem statement before its component proofs.
  State the relation between internal and source state. Include failure-only and empty-initial outcomes.

Owners: [outcome rules](InitializationOutcomeRules.tla), [initialization histories](InitializationComposition.tla),
[source witness](../../Sources/SwiftTLAPlugin/OrderedIntSourceSyntaxCheck.swift) and [compiled checks](../../Sources/SwiftTLA/StraightLineAssignmentCheck.swift).

Exit: the pilot theorem has explicit premises and observations. Failure sets cannot silently replace an observable event trace.

### Pilot source domain and program contract 7 November 2026

M0.3 and M0.5 complete definitions only. Their implementation correspondence and the program theorem remain unproved.
The pilot is an instance of the accepted language, not a new acceptance restriction.
Every other accepted form remains in M7 and the route inventory.

The source envelope contains one registered scoped `Algorithm`, without parameters, formal imports, refinements, processes or procedures.
Its body declares at least one Int shared variable before a finite, nonempty sequence of `Do` steps.
Each declaration is one lexical `let` with `scope.sharedVar(initial: e)`.
Every initial read refers to an earlier declaration. The initializer dependency graph is therefore acyclic.
Each step has one qualified, statically identified String-backed enum label and a nonempty sequence of root `Assign(target, to: e)` statements.
Repeated targets remain allowed. Each right-hand side observes the earlier assignments in that atomic step.
There are no explicit `Stop`, branch, loop, guard, local binding or other statement forms in this first instance.
Fallthrough reaches the next step, then the distinct terminal control location and its terminal self-loop.

Expressions use representable integer numerals, optional unary minus on numerals, declared root reads, parentheses and ordered addition.
The numerals include the supported decimal and radix spellings and separators.
Closed Swift additions can become literals; state-dependent formal additions retain their checked evaluation rule.
Other closed arithmetic, bound-member spellings, casts and nominal encodings remain separate routes.
The source type is standard Swift `Int`, at its full target width. This does not replace it with a smaller range for TLC.
Source/type/operator binding and the native/TLA integer-capacity links remain proof obligations, not supplied agreement assumptions.
No initial filter, membership initializer, user property, fairness, constraint or checking modifier belongs to this first instance.
Default deadlock selection and generated type obligations remain explicit, with the actual request and operational limits retained.

`OrderedIntSourceSyntaxCheck.components` identifies the scoped declarations and pure-assignment `Do` shape.
Its `value` path, both `orderedIntPlan` overloads and `verifySequentialIntAssignments` are the corresponding implementation owners.
These guards locate the route; their existence does not prove source, builder, normalization or output correspondence.
`AlgorithmLowerer.lowerSequential` owns fallthrough, hidden control and the emitted terminal action.
The zero-variable assumption-only case is a separate initialization base case, outside this pilot envelope.
The macro rejects a wholly empty model. It accepts an assumption-only model with no variables.

For each source program `p` in that domain, let `C(p)` denote the actual macro, parser, lowerer, resolver and both output routes.
The desired theorem must derive the following facts, rather than assume equality of source and compiled observations:

1. Source states contain declared values and an abstract control location.
   The native snapshot and TLA state projections retain all of these identities and values, including terminal control.
   Public visible fields alone do not replace the hidden-control projection.
2. Both outputs represent every source initial state and every reached initial failure, without extra outcomes.
   Sites identify source declarations. Failure payloads retain operand order and the complete preceding binding, including control.
   Native event histories retain count, position and first-event selection.
3. For every reachable source state and label, both outputs have exactly the source's complete atomic outcomes.
   Successful assignments commit in order, preserve unwritten fields and perform the required control transfer.
   A reached expression failure prevents that step's commit and retains its label, before-state and complete constructor payload.
   Disabled steps add neither a successor nor a failure. The terminal self-loop and its identity are included explicitly.
4. Reachability, failure availability and the selected deadlock outcome follow from those derived initials and labeled edges.
   Operational inability to finish must remain an explicit incomplete result, never a completed verdict inferred from a prefix.
   Actual Swift selection, TLA failure probes, CFG selectors and checker kernels must supply this connection.
5. Source and actual program composition satisfy these facts for arbitrary finite declaration, expression and step counts.
   `ExpressionPlan`, evaluator agreement, correct decoding and equal reachable graphs are conclusions to discharge at compiler uses.
   They cannot serve as unexplained implementation premises for the program theorem.

The complete observation carrier also includes no initial states with no failure, and no states with reached failures.
Source deterministic value initialization in this pilot yields one state or one reached failure.
It cannot justify arbitrary empty-domain cases.
Empty membership domains and selected false initial filters remain M2/M7 obligations.
One empty binding is the initialization seed. It is not the empty set of states.
`InitializationComposition`, `SingleAssignment` and `CheckingSelectionComposition` supply the existing formal consumers.
M0.1, M0.2, M0.4 and all M1 through M8 proof milestones remain open.

### Ordered initial observation contract 7 November 2026

`InitializationComposition` now defines `InitialObservation` with separate indexed state and failure histories and their counts.
Indices start at one. An empty history has count zero and an empty function domain.
The carrier retains order and multiplicity for finite returned observations. It also represents intermediate prefixes.
Total final bindings and complete source outcomes remain separate requirements.
Infinite logical domains remain accepted, outside this finite returned-history carrier.
Their capability and checking results still require correspondence.

`InitialSetProjection` supplies the existing set-based result. `InitialFirstFailure` supplies its derived first-record view.
The new extension postcondition preserves every earlier entry and appends one event at the next index.
The indexed-append obligations retain that postcondition and both projections.
Two negative obligations retain equal set and first-record views despite a dropped repeated occurrence or reordered later events.
These abstract counterexamples expose information loss. They do not claim that a particular source program produces repeated events.
The first pinned hosted run at `4612a657` left one reordered-history obligation unproved, at line 96 of 720 module obligations.
The retained source snapshot and input checksum match that exact Git blob.
The proof body now exposes its finite indices, event positions, typing, set equality and unequal second entries separately.
Its theorem statement and premises are unchanged. The pinned Linux proof job at `905a224d` discharged all 750 module obligations.
The retained snapshot SHA256 is `82ba7762fced358533e7a09e383620d0a7ce8af81610bd5b3e9fc0feb1d081d7`, matching the current module bytes.
This confirms the logical history rules and repaired obligation. It does not establish actual source/event correspondence or current admission.
Every existing definition and theorem outside the inserted block remains unchanged.

The local runtime argument uses documented Swift control flow, Array value semantics and `append` on normally returning calls:

1. These callback counts describe direct calls by one handler invocation.
   If its visit returns normally, the handler does not invoke its callback directly.
   A caught Native error outside the excluded cases invokes the nonthrowing callback exactly once.
   A mapped Eval error follows the same path after its existing conversion.
   Unmapped Eval errors and other thrown errors propagate without a callback.
2. The excluded cases are integer/sequence non-enumerability, collection cardinality overflow, an unrepresentable powerset, call-depth exhaustion and missing checking context.
   Both catch arms rethrow the original error, preserving its Native or Eval channel.
   An inner recovery returns normally after its callback, so an enclosing handler does not observe that same throw again.
   An excluded error propagates through enclosing handlers without becoming a model event.
3. Each actual compiled callback constructs one event and appends it to its local failure array.
   The emitted callbacks do the same. Neither collector sorts, deduplicates or removes failure entries.
   For a defined event projection `p`, formal entry `i` is `p(failures[i - 1])`.
   Array append therefore satisfies the indexed extension postcondition with unchanged earlier entries.
   This derives local retention for the actual callback stream without assuming that set equality retains its history.
4. `InitialEvaluationOutcomes` stores both arrays as values. Its first-failure properties read `failures.first`.
   The public generated initializer forwards the failure array unchanged and maps states in their existing order.
   Thus this transport preserves counts, positions and repeated occurrences.
   Event construction stores the lazy prefix closure. It does not perform formal conversion during recovery.

This manual code-case argument does not derive which source branches reach callbacks or their order.
It also does not prove site/value projections, generated symbol binding, complete state assembly or TLA failure histories.
The event projection must be defined. Projection errors and host execution limits remain separate owned boundaries.
The shared handler now propagates call-depth and missing-context errors through their original channels.
Its existing Eval conversion also maps logical recursive-domain failures to the existing native function-domain failure.
Direct compiled action evaluation still throws its original Eval error. Initial-state collection uses its existing normalized model-failure channel.
The focused routing run passed 87 tests in twelve existing suites.
Sampling, action/checking kernels and general classification correspondence remain open.
M0.1, M0.2, M2.3 and whole-language preservation remain open.

The existing routing owner now invokes actual powerset, range and function-space operations through both error channels.
With production bytes unchanged, one test reported twelve issues: six capacity callbacks and six missing expected throws.
The earlier internal-shape propagation check still passed. The first launch failed in shell setup and executed no tests.
The repair changes the shared handler rather than collection bounds, source acceptance or evaluation algorithms.
The guarded repair run passed thirty-three tests in six suites on all 1,201 unchanged captured inputs.
Existing sibling states, ordered model failures, membership, sampling and unbounded-domain controls passed.
Only this plan changed after that run. These local results do not establish hosted admission or the new formal obligations.

The next routing packet used unchanged `4612a657` production for both baselines.
Two existing operational tests reported six issues: three incorrect failure callbacks and three missing expected throws.
Three existing recursive-domain tests reported four issues, while their native recovery and direct action controls retained their expected behavior.
The repair adds no new model, fixture, checker or evaluator. It changes the two existing shared error owners.
Its guarded run passed 87 tests in twelve suites after a 1,241.51-second build.
All 1,201 captured inputs remained unchanged through execution.
The whole 90,301-byte log has SHA256 `28c0bc5611328d213531c0f8c7fe359e1eb4cca3f9f28e5a658a728182eb236a`.
The subsequent edits affect proof/documentation only; the tested production and test bytes remain exact.
The independent hosted history-proof failure is retained separately. Local runtime results do not establish its repair or hosted admission.

## M1 Literal read and checked addition

Complete these rows in order. Reuse the existing rules and checks.

| Row | Actual implementation obligations | Existing formal consumer |
| --- | --- | --- |
| E LIT | Decode supported source literals, retain their Int values and resolve their types. Prove actual Swift and TLA literal interpretation. | `OrderedIntExpressionRule` and its literal-history cases |
| E READ | Prove binding freshness, name-to-ID correspondence, layout ownership and available prefix values. Include captured values where the route uses them. | `UniqueLayoutNamesPreserveEveryReadValue` and partial-expression rules |
| E ADD | Derive ordered children and postorder construction from the actual visitor. Prove checked arithmetic, skipped children and complete failure payloads. | `EveryOrderedIntExpressionPreservesOutcome` and assignment/initialization composition |

- [ ] M1.1 Complete all six links for E LIT.
- [ ] M1.2 Complete all six links for E READ.
- [x] M1.2a Derive the available typed root-state read child for the unshadowed, parameter-free scoped initializer route.
  The [read-child argument](InitializationFamily.md#root-state-read-initializer-child) follows source handle binding, actual layout lookup, checked/resolved ID transport and mandatory dependency validation.
  It derives current-prefix reads in the compiled runtime and native/TLA output rows, supplying the checked expression and typed-initialization consumers under the named interpretation conditions.
  Its one-node plan and zero-prefix seed derive the checked read rule's premises explicitly. The existing copied-value and branching-correlation owners passed in the 63-test focused parser suite, using typed execution for the copied values. This manual result leaves captures, other placements and full E READ open.
- [x] M1.2b Check the concrete ready-read evaluator instance and its complete initialization parent.
  `ReadyReadInitializersComposeCompleteStatesAndFailures` constructs read rows from the current prior binding and derives readiness from an earlier-key premise.
  Its proof body supplies the existing history and terminal-selection consumers without an evaluator-agreement premise at read positions. Other constructors and selected checks retain their own agreement premises.
  The exact `a9815a06` module passed all 368 obligations in the pinned Linux run at `3c3cd1ab`; retained source, log, input and tool receipts are under `.git/swifttla-proof-evidence/ready-read-initialization-composition-2026-11-08/hosted-3c3cd1/` in the primary checkout.
  This checks the constructed formal instance and parent use. Actual source/ID/binding correspondence remains the separate manual argument above; set equality does not establish ordered failure observations. Full M1.2 and whole-language preservation remain open.
- [ ] M1.3 Complete all six links for E ADD.
- [x] M1.3a Derive the call-free Int addition node case from its established child contracts.
  The [addition-child argument](InitializationFamily.md#checked-addition-initializer-child) follows actual scheduling, checked helper/error transport and TLA expression guards into the checked `CombinedAdditionRule`.
  Eight independent parser-context rows passed at two source placements, including nested failure precedence and retained before-prefix. This is a scoped manual code-case result with separate regression evidence; all six E ADD links, the full visitor mapping and complete TLA initial-event correspondence remain open.
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
  I5s supplies an implemented event-set expression for guarded Int value/add and supported membership-domain initialization, including lazy domain addition failures. Its generic source/Swift/TLA relation and ordered observations still require proof; the prepared v5 deterministic case is separate admission evidence.
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
  The [source rewrite repair](InitializationFamily.md#source-rewrite-token-classification) retains operator classification in the existing recognized path.
  Its unchanged-production baseline accepted a recovered negative operand; the two-line repair passed 156 tests in six suites. General placement and binding coverage remains open.
  The [grouped constant repair](InitializationFamily.md#grouped-closed-integer-source-values) also restores source-witness recognition for closed prefix negation.
  Its actual two-test baseline accepted a changed radix builder; the shared collector repair passed 156 tests in six suites. Nonconstant prefixes and full L1 remain open.
  The [closed unary-plus repair](InitializationFamily.md#closed-integer-unary-plus) adds the corresponding identity branch to existing decoding and witness collection.
  Actual accepted-builder and missed-rejection baselines precede the final 210-test combined pass; general binding and full L1 remain open.
- [x] L1a Connect the registered Algorithm's unannotated shared literal declaration to its compiled child and root.
  The [source-use argument](InitializationFamily.md#registered-algorithm-shared-literal-source-use) derives registration, scope-member selection, literal decoding, `.shared` transport and the actual ordinal target.
  It supplies the source-use premise of the literal initializer instance under the existing AST/type/bounds hypotheses.
  The existing value-table owner gains the registered placement. Its baseline exposed artificial control state for declaration-only Algorithms; the two-guard repair passed 167 tests in four sibling suites without changing the normalizer.
  Other placements, overrides, binding and full L1 remain open.
- [x] L2 State the independent literal outcome and its empty read/failure effects in the existing expression rules.
  `SourceNode` selects `Success(n)` without inspecting state, read keys or histories. The raw-source and [output meaning argument](InitializationFamily.md#native-and-mathematical-tla-integer-literal-meaning) state its empty model read/write/failure effects.
  This defines the leaf's independent meaning; it does not prove parsing, source binding or a complete observation contract.
- [ ] L3 Prove the actual source/compiled literal cases preserve `n`, Int type and empty children.
  Start with both `orderedIntPlan` overloads in `StraightLineAssignmentCheck`.
- [x] L3a Derive scalar literal extraction and recognized value-initializer acceptance from the actual code.
  The local proof below uses documented Swift semantics. Full L3 and its source/type/call-coverage obligations remain open.
- [x] L3b Derive scalar constructor normalization and mandatory lowerer-check coverage from actual callers.
  The [code-case proof](InitializationFamily.md#scalar-literal-normalization-and-lowerer-coverage) covers `VarDecl`/`NamedVar`, builder/shared paths and the same-source layout/zip loop.
  It removes the local wrapper and authored-control skip assumptions. Resolved typing, later identity transport and full L3 remain open.
- [x] L3c Derive separation of live compiled expression occurrences and preservation of occurrence identity across copies.
  The [identity argument](InitializationFamily.md#compiled-expression-occurrence-identity) uses immutable, childless Swift object tokens instead of random UUIDs.
  It removes the expression-token collision premise from resolver/cache reasoning. Cache context completeness, payload/type transport and full L3 remain open.
- [x] L3d Derive typed literal transport through actual checking and resolution for the compiled pilot case.
  The [transport argument](InitializationFamily.md#typed-scalar-literal-transport-through-resolution) derives the persistent Int-type invariant and both first-visit/cache-hit literal cases.
  It supplies the scalar evaluator and initializer consumer without assumed checked/resolved literal agreement. Source typing, other scope routes and full L3 remain open.
- [x] L3e Supply the primitive input type for the unannotated scoped shared literal route.
  The [source-type argument](InitializationFamily.md#inferred-scalar-source-types-and-native-type-binding) follows normalization, explicit resolved witnesses, layout and the macro's shared resolver.
  It discharges L3d's `.int` input premise for that route, including occupied scalar names. Other annotations/placements and full L3 remain open.
- [x] L3f Derive the resolved initializer's target order and reached ID-prefix domain from the actual runtime.
  The [target/prefix argument](InitializationFamily.md#literal-initializer-targets-prefixes-and-composition) follows layout enumeration, scheduling, checked/resolved ID transport, mandatory dependency validation and every pending-insertion case.
  For a proper literal, the actual dictionary write is its fresh singleton extension with no new model failure.
  General value typing, printed-name projections, emitted-language interpretation and complete event histories remain open.
- [ ] L4 Prove the accepted Swift literal tokens and TLA integer encoding denote that same `n`.
  Reuse the existing native decoder and signed-radix lemmas. Include zero, negative values and target bounds in the general argument.
  The [actual formatter argument](InitializationFamily.md#native-and-mathematical-tla-integer-literal-meaning) now derives native leaf value, signed renderer recursion and independent decimal grouping at exact `3ee2c933`.
  Namespace/operator/parser and actual checking-kernel interpretation remain owned; mathematical encoding does not close full-width TLC execution.
- [x] L4a Retain token text and operator classification in the complete Int initial-output check.
  Five actual negative literal outputs kept identical token text while changing prefix-minus tokens to binary operators.
  Correct emitted positives and all mutation guards passed on unchanged production. The guarded repair passed 55 tests in five existing suites.
  This implementation task does not complete L4 or establish general parser-recovery soundness.
- [x] L4b Check parsed statements for recognized scalar Int action captures and writes.
  The existing division owner executed one test with one accepted malformed negative operand under unchanged production.
  Correct output, unique mutation, token-text equality, kind difference and local recovered-binding guards passed.
  The guarded repair passed 88 tests in seven existing suites. This is implementation closure only; unsupported value routes and general parser soundness remain open.
- [x] L4c Bind emitted primitive annotations independently of model declarations named Int, Bool, String or Swift.
  Reuse the library's existing literal-associated types; keep nominal types and exact multi-token output checks.
  The source baseline executed three wrong-domain failures; the native baseline was a generated compile failure with zero tests.
  The 324-test diagnostic passed the repaired behavior but failed three old-format expectations. A five-owner follow-up passed 46 tests after test-only migration.
  The [scoped argument and receipts](InitializationFamily.md#inferred-scalar-source-types-and-native-type-binding) keep library/helper binding, TLA interpretation and full L4 open.
- [x] L4d Derive the actual emitted literal binding, state assembly and TLA leaf constraint under named interpretation conditions.
  The [output-row argument](InitializationFamily.md#emitted-literal-initializer-row-and-typed-relation-consumer) follows ID-indexed slots, constructor fields and integer projection; the real equality/type predicates allow exactly the literal extension.
  It supplies the literal position of the already checked `TypedInitialRelationsRetainAllStatesAndFailureEvents` instead of assuming backend child agreement.
  This is a manual code-case result. Syntax/name/library/TLA interpretation, full-width checking and full L4 remain open. L5a records the separate checked formal instance.
- [ ] L5 Instantiate the literal child cases in the expression and initializer composition modules.
  Record the exact premises that these results discharge.
  The output-meaning argument supplies the concrete `Success(n)` instance to `IntExpressionOutcomesSupplyInitializerOutcomes` and the existing initializer leaf result.
  It derives the singleton candidate and empty failure set. L3f supplies the runtime ID-target/prior-domain link; actual source-use coverage, backend projections and full L5 remain open.
- [x] L5a Check the concrete literal evaluator instance and its complete initialization parent.
  `LiteralIntInitializersComposeCompleteStatesAndFailures` now constructs literal rows instead of assuming their agreement, and passes the derived fact to the existing complete-initialization theorem.
  Only other constructors and selected checks retain agreement premises. The code-case argument supplies the runtime target/prefix connection.
  Earlier published runs failed the final parent invocation and selected-terminal typing/equality. The second body-only refinement passed the pinned Linux check at `b33d8979`: all 277 module obligations proved. Its statement and premises are unchanged. The retained source, runner and tool receipts bind that result to the published revision; full L5 and actual source/backend correspondence remain open.
- [ ] L6 Retain the proof inputs and existing owner regressions for the exact implementation revision.
  Keep any unresolved source or decoder interpretation open. Do not promote a partial route to the complete literal family.

The complete initial-function check now retains exact token text and SwiftSyntax operator classification, with the angle-delimiter equivalence below.
Its existing lexical-line template parsing, function-kind guard and ordered-expression checks remain unchanged.
The actual baseline executes the existing generated declaration and output-check route for five negative values.
Each changed binding occurs once. The corrupted function has equal token text, different token kinds and reported parser errors.
All five corruptions passed the original check; valid generated functions passed their positive checks.
The all-kind comparison rejected valid existing initializers during compilation; no tests executed.
Its actual first mismatch was expected `binaryOperator("<")` versus actual `leftAngle`.
The pinned parser consumes generic delimiters as angle tokens; fragment parsing can retain operator tokens instead.
The comparison now allows an angle token paired with an operator token only when their text is identical.
It does not equate prefix and binary minus. Counts, all other kinds, the function guard and ordered child checks remain intact.
The existing diagnostic now reports the first differing token. The guarded repair passed 55 tests in five existing suites.
All 1,201 captured inputs remained exact through execution. The five malformed negative literals were rejected with correct positives retained.
The build took 1222.17 seconds. The whole 83226-byte log has SHA256 `e58e9cf6307b5ca92054f4f2a28363c46c49851d2de8903d06cd6a956688fd58`.
Only proof-status documentation changed afterward. These are local regression receipts, not general output-check soundness or hosted admission.

Three unpublished blanket parser-error guards failed during compilation before tests ran.
They rejected existing configured corpus initial functions. The declaration factory is restored byte-exact to `6f7702cc`.
Those compile failures supply no executed rejection evidence. No parser limit, accepted DSL, numerical emitter or checker template changed.
General recovery, printing, token grammar, scope/type/helper binding and other directly constructed syntax routes remain open.
No new formal rule or proof execution is claimed by this repair.

The separate action-output baseline exposed the same text-only false acceptance in a captured divide operand.
The actual corrupted local `VariableDeclSyntax` reports an error, while the original generated function is error-free.
The action owner now retains each part's first statement from the existing parsed token tree.
For values recognized by its existing direct or arithmetic Int rules, captures and writes require a parsed variable declaration or conditional without recovery errors.
This guard leaves all value, target, frame and continuation checks in place. It adds no parser, evaluator or fixture and does not inspect entire configured declarations.
Other value shapes, parser-library fidelity and full output interpretation retain separate obligations.
The guarded repair passed 88 tests in seven existing suites after a 1241.14-second build, with all 1,201 captured inputs unchanged.
The whole 95954-byte log has SHA256 `93e480ae2a1c81fb848ef2eddaec80a0d5251f3be45fa2e15bdb562b46d2b79b`. Only proof-status documentation changed afterward.
These receipts close L4b as an implementation task. They do not close L4, E LIT, a six-link row or hosted admission.

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
L2 now records the independent leaf definition. L1, L3 through L6 and E LIT remain open as complete tasks.
The local code-case results are partial inputs to them.

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

### Procedure and action name repair checkpoint 7 November 2026

The procedure lowerer derives parameter BinderIDs and backing VariableIDs from the same parameter list.
Previously, reserving every binder spelling made storage occupy its own alias: an otherwise free `parameter0`
became `parameter0__2`, while authored PlusCal still used the old binder name.
The existing renderer owner failed on unchanged production. Its extended occupied/unoccupied cases both executed
the actual call and independently produced output eight; the final baseline then reported three formal-name issues.
An earlier test-source compile error executed zero tests and supplies no rejection evidence.

Compilation now excludes only these paired aliases from their own state reservations, allocates storage names once,
and merges the resulting names into the existing binding table. Other binders and actual declaration occupants remain reserved.
The pairing preserves IDs and ordinal lookup; unchanged layouts preserve the referenced backing variables.
Header, authored body and direct-TLA state declarations now agree in both cases.
This is a scoped implementation argument, not a proof of every procedure, binding or control route.

The unchanged generated-machine owner separately exposed a free formal-core action named `Terminating`
rendered as `Terminating__2`; enablement and the expected successor value four still passed.
Action allocation now reserves that name when an actual generated termination action or authored PlusCal context requires it.
The actual generated termination release rule and all genuine global occupants remain unchanged.
No public action identity, source label or successor calculation changes.

The final combined guarded run passed 210 tests across 13 suites on 1,201 exact inputs,
including the actual external consumer. The whole-log SHA256 is
`b8decb1acccfd249dec3cb0cb830138a9f4b427d2800e5f3f52b59d7d085e09c`.
Only the existing native-code-generation test owner changed next: its two substring guards had rejected
legitimate `SwiftTLA.TLAValue` primitive literal-associated type paths, rather than formal-runtime execution.
Token guards now permit only those three paths and reject raw formal storage and construction.
Both actual outputs pass; both syntax-valid, occurrence-checked changed controls per owner are rejected.
The unchanged native baseline ran 26 tests with two issues; its repaired run passed all 26,
whole-log SHA256 `271bd46920d9438ded99a12a7ab577a0e50f66b4affeacf92a116cb406ec1069`.
All producer and earlier selected owner bytes remained exact across this test-only change.

These receipts repair the four observed ordinary-CI cases at parent `4e7b1a5f`; they do not replace that failed run.
General namespace/import/source interpretation, PlusCal translation and checking kernels remain owned obligations.
I5, I6, every complete six-link row, M0 through M8 and universal preservation remain open.

### Imported standard operator name checkpoint 7 November 2026

The existing allocator omitted names from the standard modules in each rendered module.
Accepted `Len` and `Cardinality` states executed the expected transition from zero to one.
Their exports retained names that collide with the imported operators.
Two executed baseline tests reported eighteen name and projection failures.
The first repair passed 101 tests across eight suites for the always imported modules.

A second baseline covered `Int`, `Nat`, explicit TLC imports and explicit Randomization imports.
The runtime values and free-name controls for absent modules passed.
Two executed tests reported twenty-six name and projection failures for imported operators.
These baselines expose output allocation faults, not runtime value mismatches or local SANY failures.

The existing standard-module enum now supplies its named exports.
The allocator uses the same explicit, required, default and symmetry modules as the renderer.
The occupied-name set then feeds the existing variable and action allocators.
Source declaration names, IDs and public field names stay unchanged.
The existing projection, renderer and procedure-binding routes consume the allocated formal names.

The metadata matches the [pinned module sources](https://github.com/tlaplus/tlaplus/tree/867aefb69ffc2452031292587b389d1fc3eb43ff/tlatools/org.lamport.tlatools/src/tla2sany/StandardModules).
`Integers` exports `Nat` through its nonlocal extension of `Naturals`.
Local instances in the other reviewed modules do not supply additional exported names.
This is a reviewed source interface, not a JAR reconstruction or a proof of the standard operators.

The final guarded run passed 101 tests across eight suites, including the external consumer.
All 1,201 captured inputs stayed exact. Only this plan changed afterward.
The result covers the occupied and free names through runtime values, projections, native metadata, direct TLA and authored PlusCal.
The whole log has SHA256 `f76032bb838040f1c0cf40c8fa9dd8afad260c7dea0de045e040e14846331cb9`.

Constant, model-value, property, formal-operator and other binder declarations retain separate namespace obligations.
Opaque imports, source binding, parser and kernel interpretation also remain open.
I5, I6, every complete six-link row, M0 through M8 and whole-language preservation remain open.
These local results do not establish hosted admission.

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

### Native action failure delivery checkpoint 7 November 2026

The existing distinct-failure choice reached division by zero, then a negative modulo divisor.
The published native visitor delivered only the first failure.
The measured baseline executed one test and reported this missing second callback.
Its legacy selected-first result and original selected TLA assertions passed.

The existing action-part traversal now collects reached model errors in order.
Each failing part stops its dependent continuation while independent alternatives continue.
Duplicate errors from distinct branches remain distinct callbacks.
The existing private successor routes return this collection without a second evaluator.
Convenience APIs still select its first error. Validation delivers the complete collected payload list after successful successors.
Callback exceptions retain their original identity and are excluded from model-failure classification.
A callback can still stop delivery. Constant-false guards retain their existing immediate return without an unreachable catch.

The existing output checks require the collection envelope and retain their original action-body checks.
The existing choice owner rejects removal of an actual failure append after checking correct output.
The migration updates 38 existing Swift witness files and preserves 388 original action-part core bodies.
It adds no model, public API, evaluator, checker family or test seam.

The final guarded diagnostic passed 153 tests across 19 suites.
It covers failure order and multiplicity, selected-first results, callback stopping and errors, and affected output witnesses.
The complete log contains 32414 bytes with SHA256 `f80f62fac246b60a1058c2cb55ed5f3403d5e592f87b8eec42d1df615bd1ed35`.
Evidence is retained under `.git/swifttla-proof-evidence/action-observation-boundary-2026-11-07/` in the primary checkout.
The final input binding derives from the preceding captured manifest and the recorded sole dispatcher-witness change.
It is not an independently captured pre-run manifest.

This repair delivers native error payloads through the existing callback contract.
It does not add complete action event sites, branch identities or before-prefix projections.
The selected TLA payload rules and snapshots remain unchanged. Complete TLA branch events remain open.
Source and lowering correspondence, output-checker soundness, callback interpretation and checking kernels remain owned proof boundaries.
I5, I6, every complete six-link row and the whole-language theorem remain open.

### Imported operator and local binder checkpoint 7 November 2026

The existing tuple-binding owner accepts a quantifier whose source binder is named `Len`.
Its compiled initial state and invariant evaluation retain the expected value.
The pre-repair TLA output binds `Len` and then emits `Len(Len)`, capturing the imported length operator.
One executed baseline test with two argument cases reported two output-name issues.
The ordinary `tuple` control passed. This was an output binding defect, not a measured runtime mismatch or SANY result.

The shared lowerer now finalizes binder names against the actual standard-module exports selected after lowering.
The same import-name set supplies variable and action reservations.
The existing fresh-name allocator avoids current declarations, binders and operators.
Binder identities, expressions and runtime values remain unchanged.
Procedure parameters still receive their final backing-variable names through the existing mapping.

The existing owner covers implicit `Len` and `Cardinality` imports and explicit `TLCGet` imports.
An absent TLC module leaves `PrintT` free.
The final assertion reads the emitted quantifier name and checks its use by the imported length call.
It does not prescribe a fresh-name suffix or derive expected runtime values from the renderer.
The original executed baseline used suffix-specific assertions before this test cleanup.
Its retained bound `Len` also violates the final noncapture requirement.
The final assertion text was not rerun on old production.

The guarded repair passed 164 tests across six existing suites, including the external consumer.
The build took 1467.89 seconds, followed by 205.020 seconds of selected execution.
All 1201 captured inputs remained exact.
The whole 106736-byte log has SHA256 `e0482fba470efa1e03c0f6043e4a80d499fc7c068327b9bd9e13ff7d5b0ddccb`.
The final suffix-independent owner then passed separately on unchanged production with five argument cases.
Evidence is retained under `.git/swifttla-proof-evidence/standard-module-binder-names-2026-11-07/` in the primary checkout.
Only this plan changed after the final diagnostic.

This repair supplies a compiler-to-rendered-name implementation guard.
It does not prove arbitrary source scopes, imported operator semantics, general namespace correspondence or TLA checker interpretation.
Constants, model values, properties, formal operators and opaque import namespaces retain separate obligations.
I5, I6, every complete six-link row and the whole-language theorem remain open.

### Property declaration projection checkpoint 7 November 2026

The existing property-name owner now compares ordinary, imported-operator and generated-behavior names.
Its first stateless variant incorrectly required a generated `Spec` definition and is retained as a test-construction failure.
It supplies no repair credit.
The corrected scoped-state baseline executed one test with three argument cases and two issues.
The ordinary `safe` case passed its runtime, label-identity, definition and selection controls.
`Len` remained a selected imported operator name. `Spec` reached the existing mandatory whole-Spec output rejection.
These are measured output-boundary failures, not local SANY results or observed runtime value mismatches.

The compiled property layout now separates its source declaration and formal name.
The existing allocator pattern reserves imported operators, generated behavior, known declarations and helper names.
It allocates property names before variable and action names, retaining all source identities and property IDs.
The same names reach invariants, reachability checks, temporal checks and both refinement forms.
CFG selections and the native formal-property projection use these allocated names.
Source-facing compilation descriptions, public property cases and display labels retain their source identities.
Helper allocation also reserves the resulting formal names.
Authored export still uses source property IDs to select the corresponding compiled definitions.
Existing declaration checks and the complete Spec output check remain active.

The existing owners cover ordinary names, imported `Len`, generated `Spec` and contextual `Terminating` collisions.
They retain label identity, predicate values, native name projection, authored placement and formal/generated refinement mappings.
The first repair launch failed during test compilation because two new cases referenced a plugin-only resolver.
It executed zero tests and supplies no rejection evidence.
Those cases now use the existing public render API. Production code remained unchanged for the next run.

The final guarded diagnostic passed 87 tests across eleven existing suites, including the external-consumer checks.
Its incremental build took 263.76 seconds, followed by 208.981 seconds of selected execution.
All 1201 captured inputs remained exact through that run. Only this plan changed afterward.
The complete 36350-byte log has SHA256 `50772cf22280d56c5ef612bb3650f47c3d58ffa0f5b335de21da0e3aedbef66d`.
Evidence is retained under `.git/swifttla-proof-evidence/property-declaration-symbols-2026-11-07/` in the primary checkout.

No new model, fixture type, checker family, evaluator, dependency, public application API or accepted DSL form was added.
Constants, model values, formal operators, opaque imports and general namespace correspondence retain open obligations.
Source and lowering correspondence, checker soundness, imported semantics, complete events and checking kernels remain open.
I5, I6, every complete six-link row and the whole-language theorem remain open.

### Fairness-profile behavior connection checkpoint 7 November 2026

The existing scenario owner retains strict satisfaction, relaxed violation, equal initial states and equal labeled edges.
Its first new checker call paired finalized generated output with separately reconstructed compiler metadata.
That positive call failed at finite-invocation checking before the mutation was reached.
It supplies no corruption credit. Correspondence between that export and this reconstructed metadata remains open.

The corrected baseline uses the actual module output from the same compiled program as its checker metadata.
Correct output, original native outcomes and CFG selectors pass.
The existing test requires one profile prefix occurrence and a changed input before invoking the checker.
Replacing that profile's Init conjunct with TRUE was accepted.
The executed baseline reported one intended issue in one test on unchanged published production.

The existing finite-invocation checker now validates the Init, Next and full-frame prefix for the base specification and each profile.
It retains its existing guard for outputs with state or named actions.
It retains exact whole-body equality when the compiled fairness list is empty.
Nonempty fairness tails remain unchecked here, including operator strength, action scopes, projections and helper meaning.
The change does not impose a line count or parser restriction on those tails.
The existing owner rejects missing Init, changed Next, an unowned frame and duplicate headers for both base and profile output.
Every corruption has a correct-output baseline, occurrence guard, changed-input guard and specification-specific diagnostic check.

The guarded repair passed 157 tests across seven existing suites.
The build took 1380.24 seconds, followed by 2.033 seconds of selected execution.
All 1201 captured inputs remained exact. Only this plan changed afterward.
The complete 107754-byte log has SHA256 `84ddbbe77965a503f475b833d23b5a57223287202fcde1c5ed15b2736324debf`.
Evidence is retained under `.git/swifttla-proof-evidence/fairness-profile-frame-2026-11-07/` in the primary checkout.
No new model, fixture, parser, checker family, evaluator or public API was added.

This is a structural output-check implementation repair.
It does not prove fairness preservation, TLA interpretation, arbitrary source correspondence or checking-kernel soundness.
Selected checking still needs derived equal machine observations and predicates.
I5, I6, every complete six-link row and the whole-language theorem remain open.

### Formal operator projection and recovery-control checkpoint 7 November 2026

The existing transition owner now exercises ordinary, `Len` and `Spec` operator names.
Its unchanged-production baseline executed one test with three arguments and two intended name-collision issues.
The original transition, two-state exploration and invariant/trace outcomes passed.
This is an emitted-name regression baseline, not hosted TLA-kernel execution or a language proof.

The compiler retains source operator IDs and assigns distinct names for collisions with selected standard exports and generated declarations in the owning module.
Existing dependency-first module compilation passes actual exported names to direct imports and qualified instances.
The compiler binding table retains the source-name-to-ID link.
Explicit library `Spec` refinements use the actual instance-qualified linked ID; generated behavior `Spec` remains the behavior target.
A first repair attempt stopped during compilation because one combined set expression exceeded Swift's type checker.
It executed no tests and supplies no rejection credit. Ordinary set unions corrected that expression.

The first executed repair passed 177 tests across nine suites.
Read-only review then identified a lexical capture risk in its unpublished name projection.
An extended existing import owner reproduced it: direct imported `Len` and a distinct local `Len_1` both emitted `Len_1`.
One executed test with three arguments reported one intended issue; native transition/exploration controls and other cases passed.
Actual imported aliases now participate in the existing operator and binder reservations.
The expanded guarded repair passed 211 tests across twelve existing suites.
All 1201 captured inputs remained exact. The build took 1413.56 seconds and selected execution took 204.241 seconds.
The complete 117436-byte log has SHA256 `f59ea57c51750bede9b7ce64c1e2a4a360c1f3868badf6cd1d54731a964d4a3c`.

Published `06d2855a` ordinary CI independently failed the existing signed-division negative control.
Its malformed-binding guard assumed that binding was the first generated statement.
Actual action parts now wrap their bindings in a `do/catch` recovery envelope.
The guard failed before the spacing corruption checker ran; it establishes no compiler mismatch or rejection result for that case.
The existing test now follows the changed binary-minus token to its owning recovered variable declaration.
It retains root function typing, syntax-error checks, token text equality and kind difference, unique mutation, changed input and actual rejection/path checks.
The guarded existing signed-integer suite passed 14 tests.
Only that test file changed after the 211-test run; only this plan changed after the 14-test run.
Exact input sets, complete logs, baseline failures and review receipts are under `.git/swifttla-proof-evidence/formal-operator-symbols-2026-11-07/` in the primary checkout.

No new model, fixture type, checker/evaluator family, public application API, dependency, pin, budget, timeout or accepted-language restriction was added.
These are implementation and regression results. They do not prove namespace or parser soundness.
Importer-only reserved symbols, constants/model values, opaque imports, typed explicit-library refinement export and general source/backend correspondence remain owned boundaries.
Complete events, every complete six-link row, I5, I6 and the whole-language theorem remain open.
Current hosted admission must be established separately for the final published revision.

### Parameter export and metadata checkpoint 8 November 2026

The existing parameter-resolution owner reproduced two boundaries on unchanged production:
runtime parameters named `Init`, `Next` or `Spec` retained generated declaration names,
and configuration field identities for allocated `limit` and `Len` aliases retained their source names.
The final baseline executed one test with six cases and eight intended issues.
The compiler now uses its existing generated-declaration reservations for runtime parameters;
the configuration emitter obtains each formal name from the same resolved binder table as export.
It preserves source references and Swift configuration fields and rejects missing formal bindings.

The guarded repair passed 30 tests across eight existing suites, including configuration execution,
PlusCal export, assumptions and external generated-refinement/parameter contracts.
All 1201 captured inputs remained exact. Only this plan changed after execution.
The complete 78616-byte log has SHA256 `7bfc96639bd8372c102b1e121f0036f618343cc359b38ef1bae585be62d05713`.
Baselines, input hashes and review receipts are retained under
`.git/swifttla-proof-evidence/parameter-generated-names-2026-11-07/` in the primary checkout.
This is implementation and regression evidence. Namespace soundness, actual source/backend correspondence,
every complete six-link row and whole-language preservation remain open; hosted admission is separate.

### Simple fairness output checkpoint 8 November 2026

The unchanged checker accepted 30 altered clauses across weak and strong Next, action and action-group cases.
The executed baseline compiled and ran one test; correct-output, unique-occurrence and changed-input controls passed.
This measured output-guard acceptance, not an observed incorrect renderer result or checking verdict.
The shared mandatory checker now derives the supported clauses from typed strength, layout action IDs and the complete state frame.
It does not call the renderer to construct its expected fairness text.
It compares the complete body only when every clause has a supported unprojected, unbound form.
Projected, parameterized, each-action, expanded-call and mixed unsupported tails retain their earlier prefix check and remain open.

The first diagnostic passed 50 tests in seven suites. Test-only consolidation then removed duplicate inline model setup
and moved the same six cases and 30 corruptions into the existing resolved-action-name owner.
The final guarded diagnostic passed 49 tests in seven suites; all 1201 captured inputs remained exact.
Its complete 11696-byte log has SHA256 `a4dd7ca2a61f2e60cfd7e956b8708c11d6676c5e4d1e9c701907141dd085d319`.
Only this plan changed afterward. Exact inputs, baseline, logs and review receipts are retained under
`.git/swifttla-proof-evidence/simple-fairness-output-2026-11-08/` in the primary checkout.
No fixture type, registered model, renderer, evaluator, checker family, dependency, pin, budget or timeout was added or changed.
These are implementation and regression results. Fairness semantics, actual source/metadata interpretation,
checker soundness, every complete six-link row, hosted admission and whole-language preservation remain open.


### TLA declaration lexical boundary checkpoint 8 November 2026

The exact pinned TLA JavaCC grammar separates `WF_` and `SF_` fairness tokens from identifiers.
An underscore-led identifier must also contain an ASCII letter.
Existing source admission accepts names such as `WF_count`, `SF_count` and `_1`.
Five existing owners reproduced 35 invalid emitted-name observations while their source identity, API and runtime-value controls passed.
This baseline compiled and executed; it was not an observed SANY/TLC process failure.

The compiler now derives physical declaration stems at the existing allocation sites and reuses their collision handling.
State and property aliases reserve source names; action and binder allocation retains its existing occupied-name rules.
Source admission, declaration IDs, Swift field names, public action-binding labels and parameter references remain unchanged.
The procedure exact-name path remains linked to its backing state allocation.

The guarded repair passed 181 tests across nine existing suites, including lexical scope, formal operators,
procedure calls, canonicalization, generated-code metadata and existing external-consumer contracts.
All 1201 captured Git payloads remained exact through execution. The build took 1506.73 seconds; execution took 201.779 seconds.
The complete 113181-byte log has SHA256 `213f55e11bec46c083a188ba31343e6387c2132806537cbbe11396d4c0adf78c`.
Only this plan changed afterward. Baseline, exact pinned grammar, captured inputs and complete logs are retained under
`.git/swifttla-proof-evidence/tla-declaration-stems-2026-11-08/` in the primary checkout.

No new model or fixture type, checker/evaluator family, public API, dependency, pin, budget, timeout or source restriction was introduced.
This is a measured implementation repair, not a parser/kernel proof or hosted admission.
Module, free-constant/model-value, opaque import, operator, record-payload and explicit external-contract naming remain separate owned boundaries.
The ready-read composition candidate remains unverified; every complete six-link row and whole-language preservation remain open.


### Operator declaration lexical boundary checkpoint 8 November 2026

Three existing tests reproduced 19 emitted-name issues on unchanged `d98c0c5c` production.
The cases cover owned definitions, operator-valued parameters, direct/qualified imports and local recursion.
Source IDs, higher-order values, the reached invariant trace, import capture guards and recursive results passed their controls.
The existing binding-table finalization now reuses the physical stem, keyword escape and occupied-name allocator.
Imported IDs retain the actual callee export name; source lookup and executable operator IDs remain unchanged.

The guarded repair passed 212 tests in twelve suites after a 1447.63-second build and 196.574-second execution.
All 1201 captured inputs remained exact. The complete log and its SHA256 are retained in
`.git/swifttla-proof-evidence/tla-operator-stems-2026-11-08/repair-1-result.json` in the primary checkout.
Only this plan changed afterward. No model/fixture type, checker/evaluator family, public API, source restriction or tool/resource setting changed.
This removes measured emitted-name counterexamples; it is not a SANY/TLC execution, namespace soundness proof or hosted admission.
Model-parameter keyword spellings, predefined symbols, explicit module contracts, value encodings and generic correspondence remain separate obligations.
The ready-read theorem still requires its exact pinned result; every complete six-link row and whole-language preservation remain open.


### Measured integer-set proof-body repair 8 November 2026

Published `d98c0c5c` ordinary CI failed its pinned proof job.
The complete source-bound diagnostic artifact reports one undischarged obligation out of 359 in `OrderedIntInitializationComposition`:
`IntegerSetConstructorSuppliesEveryTypedInitialState`, step `<1>3`, line 606.
The failing statement is inherited unchanged from `bac1d6cd` and lies outside the added ready-read block.
The module failed; no checked ready-read result or candidate admission follows from the other obligations.

The repair changes only that proof body. It makes the typed interval outcome and both generated-leaf substitutions explicit.
The theorem statement, premises, existing definitions, ready-read block, prover settings, pins, budgets and timeouts remain unchanged.
This repair is unverified until the exact revised module passes the pinned prover.
Existing Swift/test bytes retain the separate 212-test local regression receipt; static checking cannot establish the mathematical result.
The failure artifact, exact snapshots, tool receipts and log are bound in `/tmp/swifttla-d98c0c-admission/ordinary/math-current-failure-audit.json`.
The remaining source/IR/backend and ordered-observation obligations, every complete six-link row and whole-language preservation stay open.


### Model-parameter keywords and checked read composition checkpoint 8 November 2026

The accepted `#spec` parameter names `IF`, `LET` and `CONSTANTS` retained invalid bare formal names.
Two existing owners ran on unchanged production: the naming owner reported nine issues,
while source admission, public-name retention, label-independent identity and existing reference/metadata controls passed.
The shared physical-stem helper now reuses the existing reserved-word set. Source acceptance predicates are unchanged.
The guarded repair passed 217 tests across thirteen suites, including existing generated-code consumer contracts.
All 1201 captured inputs remained exact through execution; only these two documentation files changed afterward.
The complete 122483-byte log has SHA256 `52d92ab43d3e957cebb563ccf9779a77bbdd7d4e113c9814f4e5ddd28d53ab4e`.
Exact inputs, baseline, whole log and review receipts are under `.git/swifttla-proof-evidence/model-parameter-keyword-stems-2026-11-08/` in the primary checkout.

Separately, the pinned Linux job `128656680365` on published `3c3cd1ab` proved the complete `a9815a06` initialization module.
Its 368-obligation result includes the unchanged ready-read theorem and the repaired integer-set proof body.
The actual 296891-byte diagnostic ZIP, every entry CRC/hash, source snapshots, input hashes, job log and pinned-tool receipts are bound.
A byte-exact durable copy is retained in the ready-read packet's `hosted-3c3cd1` directory; it is one hosted delivery, not a new capture.
This closes the scoped formal M1.2b instance: read evaluator equality is derived from earlier-key prefixes and feeds the existing complete set-valued history/terminal parents.
Other constructors and selected checks still supply correspondence; actual source/ID/type/backend interpretation and event order/multiplicity remain open.
The hosted proof-input snapshot contains the previous `SpecCompilation.swift`, not this keyword repair; no hosted source execution or admission transfers.
The ordinary parent is terminal success, but whole parent ROOT audits and full admission remain incomplete. Every complete six-link row and whole-language preservation remain open.

Read-only review of the exact pinned SANY source also identifies the next predefined-symbol boundary.
Its symbol table rejects redefinitions of built-ins, including `STRING`, `FALSE`, `TRUE` and `BOOLEAN`.
These source files and Git-blob receipts are retained in this keyword packet's `predefined-symbol-lookahead` directory.
No regression or repair for that separate allocation boundary is claimed here; raw value encodings and explicit external contracts stay separate.

### Predefined declaration allocation checkpoint 8 November 2026

Pinned SANY source rejects declarations that redefine `STRING`, `FALSE`, `TRUE` or `BOOLEAN`.
Nine existing tests reproduced 49 naming issues on unchanged `d50b52fe` production.
Source identities, values, action enablement, import capture, recursion and reached-trace controls passed.
A separate positive baseline retained integer and raw model-value arguments through lexical shadowing.

The shared allocation paths now reserve these four names. Source validation and raw-value validation remain byte-exact.
The guarded repair passed 240 tests in fourteen suites after a 1461.19-second build and 237.277-second execution.
All 1201 captured inputs remained exact. Only this plan changed after that run.
The complete 130809-byte log has SHA256 `2dcb56fe5259f9a62aa9fbf8a9465b1f005c4df52285295c2aebdd9a7ee5ab7d`.
Inputs, baselines, pinned source receipts and results are retained in `.git/swifttla-proof-evidence/predefined-symbol-allocation-2026-11-08/` in the primary checkout.
This removes measured declaration collisions. It does not prove namespace soundness or execute SANY.
Raw values, explicit module contracts, module/instance names and general encoding remain separate owned boundaries.
All mathematical source bytes remain unchanged. No new theorem, hosted admission or whole-language preservation follows from this repair.

### Formal instance namespace checkpoint 8 November 2026

Accepted instance names were copied directly into TLA declarations and qualified calls.
The unchanged compiler produced 58 failures across four existing tests, including output-guard rejections for `Init`, `Next` and `Spec` collisions.
A separate recursive-call baseline reported two incorrect prefixes while its execution and local-value controls passed.
The authored-output baseline reported twelve naming failures across direct TLA and PlusCal output.
These baseline runs overlap and are not additive coverage totals.

The existing instance layout now retains its source namespace and a separate allocated formal name.
The final closure pass chooses names after bindings and model values are known, preserving occupied sibling and lexical names.
Qualified exports and both refinement paths use the allocated name. Lookup keys, IDs, canonical source encoding and provenance paths retain the source name.
Source and raw-value validation remain unchanged. The repair adds no model, fixture type, checker, evaluator or public API.

The guarded repair passed 207 tests in fourteen suites after a 1467.57-second build and 218.295-second execution.
All 1201 captured inputs remained exact. Only this plan changed after that run.
The complete 124152-byte log has SHA256 `1806b94b269f58db7872acd8b5588ca3be9abd229a608d335a3da24c0e498510`.
Inputs, baselines, logs and reviews are retained in `.git/swifttla-proof-evidence/module-instance-names-2026-11-08/` in the primary checkout.
These local results establish the measured implementation repair. General namespace soundness and SANY interpretation remain separate owned boundaries.
Module names, generated-instance contracts and raw-value encoding remain separate owned boundaries.
All mathematical source bytes remain unchanged. Source/IR/backend interpretation, complete ordered observations and whole-language preservation remain open.

### Module-file naming checkpoint 8 November 2026

Accepted module names with `WF_` or `SF_` prefixes, letterless names and names shared with standard modules reached inconsistent file, header and reference output.
The existing owners reproduced 38 naming failures across two tests on unchanged `547fff13` production.
A separate nested-import baseline reproduced four naming failures in one test with two argument cases.
Source identities, ordinary names, native imported execution, configuration and closure controls passed.
The earlier 27-issue baseline overlaps the 38-issue run; these are not additive coverage totals.
A test setup error and the first repair's scope error each executed zero tests and supply no rejection credit.

The existing module allocator now assigns physical root and user-import names while retaining source names and identities.
Standard library references keep their canonical names. Enclosing and earlier refinement module files constrain child allocation.
Direct TLA, authored PlusCal, actual generated Swift export metadata, configuration forwarding and bundle provenance consume the returned physical names.
The repair uses three existing producer files and two existing test owners, with no new fixture type, checker, evaluator or public API.

The guarded repair passed 206 tests in fourteen suites after a 1476.23-second build and 212.910-second execution.
All 1201 captured inputs remained exact. Only this plan changed after that run.
The complete 128815-byte log has SHA256 `d380f7e422cbd49422eee94a355e50b106ea7ccc2b415565947f8c4082c305eb`.
Inputs, baselines, logs and review receipts are retained in `.git/swifttla-proof-evidence/module-file-names-2026-11-08/` in the primary checkout.
This establishes the measured implementation repair, without SANY execution or a general namespace theorem.
All mathematical source bytes and the protected language checklist remain unchanged.
Generated/opaque module contracts, raw values, source/IR/backend interpretation and complete ordered observations remain open.
No new hosted admission or whole-language preservation follows from this local result.

### Record key encoding checkpoint 8 November 2026

Accepted record fields with fairness-token prefixes or letterless names reached bare TLA field syntax.
Raw configuration records also printed arbitrary and empty keys without a legal representation or required encoding marker.
The corrected baseline reported 99 output-contract issues across two existing tests while normal/keyword fields, keys, types, native execution and domain cardinalities passed.
A separate existing-owner baseline reported 47 issues, including two empty-constructor issues; its other 45 issues overlap the earlier run.
The first baseline contained eight mistaken optimization-route assertions. Those are retained as test setup mistakes, not compiler fault evidence.

The initial formatting repair passed 171 tests, but source review found an uncovered strictness risk.
The pinned TLC implementation evaluates a function operand with `KeepLazy` during application, while a record constructor evaluates every field.
A new case in the existing owner confirmed the exact native division-by-zero error from an unselected field.
The initial candidate then failed four eager-output contract assertions across direct and typed output.
That baseline binds the actual initial repair bytes, rather than claiming unchanged committed production.
No local SANY or TLC execution is claimed by these output-contract assertions.

The corrected compiled representation evaluates operand tuples in a singleton comprehension before constructing the string-keyed function.
Existing fresh-name allocation supplies the carrier, key and result names. Operand positions occur once and retain their order.
Raw closed record data reuses function formatting; function binders avoid capture by raw model-value references.
Ordinary and keyword fields retain their existing token forms. Source admission, data keys, public names and values remain unchanged.
The next checkpoint records the coupled source-fingerprint repair found before publication.
Configured definitions use the existing formal-string marker, including byte-distinct Unicode key encodings.
The existing bridge already canonicalizes nonempty string-keyed functions as records. Its source and pins did not change.

The corrected guarded repair passed 171 tests in sixteen suites after a 1447.45-second build and 2.203-second execution.
All 1201 captured inputs remained exact. Only this plan changed after that run.
The complete 116380-byte log has SHA256 `88f4f8122252c66cf23b2446bc30bfd876da9a7c1551e4b913b72aaa2a6cd30b`.
Inputs, baseline results, pinned source, logs and reviews are retained in `.git/swifttla-proof-evidence/record-field-encoding-2026-11-08/` in the primary checkout.
These results establish the measured implementation repair under named language/tool interpretation boundaries.
Duplicate raw-key payloads keep their existing formatting and retain a separate value-contract obligation.
Nested function/effectful child outcomes, generic Unicode/type projection, complete event correspondence and checker/decoder/kernel soundness remain open.
All mathematical source bytes and the protected language checklist remain unchanged. No complete six-link record row, new theorem, hosted admission or whole-language preservation follows.

### Source literal identity checkpoint 8 November 2026

Final record review found that source literal keys used TLA formatting instead of value constructors.
The record formatter made a record and a string-keyed function share the same source key.
The same problem affected their enclosing tuples. Boolean true also shared its key with the model value `TRUE`.
The existing compiled-identity owner reproduced all three collisions against committed `33e281c5` producers.
One executed test reported six issues: each pair collided in both its source key and its compiled specification identity.
The existing nominal-type and raw-value distinction controls passed. No setup or compiler failure supplied this baseline.

The source literal path now uses an overload of the existing tagged length encoder.
It visits raw value constructors directly and orders set members and function keys deterministically.
It preserves stored record fields without conversion to compiled values, which can reorder duplicate-key payloads.
All existing action, property, temporal and operator-body identity paths consume the corrected literal leaf.
Opaque compilation fingerprints change. Source names, layout IDs, value data and accepted-source predicates remain unchanged.
The existing depth and lexical-scope controls retain their structure with the corrected literal encoding.

The guarded repair passed 241 tests in twenty suites after a 1554.02-second build and 229.783-second execution.
All 1201 captured inputs remained exact. Only this plan changed after that run.
The complete 133086-byte log has SHA256 `62bfebc0a67f321c6c8d6ef797ffbff10239185dc03f889cae75f8fa0c2edb3c`.
The baseline, inputs, logs and reviews are retained in `.git/swifttla-proof-evidence/literal-source-keys-2026-11-08/` in the primary checkout.
These receipts support the implementation repair. They do not prove a general key-injectivity or source/value correspondence theorem.
Duplicate raw-key meaning, Unicode/string interpretation, source binding, output/helper/kernel semantics and complete observation correspondence retain their separate obligations.
No mathematical source or protected-checklist bytes changed. No complete six-link row, hosted admission or whole-language preservation follows.


### Closed-constant symbol checkpoint 8 November 2026

The existing source guard accepts fairness-prefixed, letterless, predefined and inherited names for closed constants.
Output metadata printed those names directly into TLA declarations, assumptions and configuration.
The first baseline against committed `ec224eb0` producers reported 29 output issues across seven tests.
The expanded baseline included generated behavior names and reported 37 issues. These counts overlap.
Source names and values, native cardinality results, ordinary names and existing import/refinement controls passed.
The macro fixture also compiled and executed its generated export. No setup failure supplied these results.

The metadata constructor now allocates physical closed-constant names with the existing stem and freshness functions.
Source reads already resolve to literal values before this step. The source declarations, values and IDs remain unchanged.
The existing metadata consumers carry the physical names through direct, typed and generated exports, configuration and authored PlusCal.
Identity model-value constants retain their raw token. Their general encoding rule remains separate.

The first candidate passed 193 tests in eighteen suites. Review then added a parent/child case in the existing refinement owner.
A parent `WF_Limit = 3` chose an alias that captured the child model-value token `_WF_Limit`.
Native initialization passed before the existing export guard rejected that collision.
This baseline ran one test with one issue against the exact first-candidate producer bytes, rather than committed `ec224eb0` producers.

The module loop now supplies the model-value tokens from previously compiled imports before it allocates parent symbols.
The source closure visits imports and named instances before it appends each module. The root is its last entry.
The incremental token union equals the previous final union. It now also supplies each earlier allocation step.
Bindings and declaration names reserve this prefix. Raw data tokens remain unchanged, and the collision guard remains byte-exact.
This source argument concerns the known compiled-import frontier. Other sibling, generated-target and runtime-introduced namespaces retain separate obligations.

The corrected guarded run passed 193 tests in eighteen suites after a 1483.52-second build and 229.925-second execution.
All 1201 captured inputs remained exact. Only this plan changed after that run.
The complete 125557-byte log has SHA256 `a718ad6f4796b6ef320fd0b7afeccc4727e8d16576b6f10d7a40fc54edbff125`.
Inputs, baselines, logs and reviews are retained in `.git/swifttla-proof-evidence/constant-declaration-names-2026-11-08/` in the primary checkout.
These are implementation regression receipts. No local SANY/TLC execution, new theorem, complete proof row or hosted admission follows.
The mathematical sources and protected language checklist remain unchanged. Whole-language preservation remains unproved.


### Operational action-error checkpoint 8 November 2026

Initial recovery already excluded enumeration, collection capacity, call-depth and missing-context errors from model failures.
Generated action recovery and the independent-alternative helper caught every native evaluation error instead.
The existing recursion owner now exercises the actual validator, rather than only direct execution.
On unchanged committed `2c5567a2` producers, recursion exhaustion returned an evaluation-failure summary and emitted one model-failure event.
Five actual capability/capacity operations also visited a later alternative and emitted its update after the earlier branch could not finish.
The executed baseline ran thirty tests in two suites with twelve issues. Its existing logical-failure, callback and transactional-state controls passed.
No setup or compiler failure supplied this evidence.

The existing error enum now classifies all its cases explicitly, retaining the six earlier operational exclusions.
Initial recovery reuses that classification and preserves the original Native or Eval error channel.
Independent alternatives and generated action parts now catch only model errors.
The generated outer visitor and default `StateMachine` visitor apply the same distinction while preserving their callback-error guards.
Operational errors propagate without a completed model-failure observation. Logical failures retain their existing collection and ordering behavior.
Context-free successor enumeration now propagates its original missing-context error rather than wrapping it as a model action failure.
No error case, accepted source predicate, execution limit, evaluator or model fixture changed.

The mandatory action output check requires the classification guard and rejects its occurrence-checked removal.
Thirty-nine existing Swift witness files change only their catch conditions: 389 node guards and one outer guard.
Reversing those substitutions restores every original witness byte.
The mathematical TLA sources and protected language checklist remain unchanged.
The existing default-visitor positive integration passed; its operational filters also have a source-case review, not a new injected-error fixture.
Full error meaning, source binding, generated symbol interpretation, complete event sites/prefixes and TLA/checker/kernel correspondence remain owned obligations.

The guarded repair passed 172 tests in twenty-two suites after a 1532.99-second build and 6.237-second execution.
All 1201 captured inputs remained exact. Only this plan changed after that run.
The complete 109146-byte log has SHA256 `c8f89c87de0e678884d7cb00db9a4cd7873e18b91c5744bdf01fc6192941b1d3`.
Inputs, baseline, witness migration, logs and reviews are retained in `.git/swifttla-proof-evidence/action-operational-failures-2026-11-08/` in the primary checkout.
These are local implementation regression receipts. They establish no new mathematical theorem, complete six-link row or hosted admission.
Whole-language preservation remains unproved.


### Static builder-loop filter checkpoint 8 November 2026

The peer parser expanded a top-level bounded loop without reading its `where` clause.
The existing parser owner now compares actual `#spec` result-builder execution with the production peer verifier, generated API metadata and compiled successors.
On unchanged committed `9e9bafca` producers, four false-filter spellings each added three spurious actions, API cases and successors.
Literal false, parenthesized false and two bound-Boolean spellings supplied those cases.
The actual builder produced no actions or successors. Unfiltered, literal-true and true-alias peer controls passed.
The executed baseline ran sixty-three tests in one suite with twelve issues. No setup or compiler failure supplied that evidence.

The existing loop parser now unwraps parentheses and reads literal or already known source-scope Boolean values.
A known false value returns before assembling the body. The existing literal-range guard still runs first.
The return exits only the loop parser, so subsequent specification declarations remain in order.
After the baseline, the same owner adds an ordinary trailing action and independently expected successor values as composition controls.
These additional positive controls receive no separate baseline-failure credit.
No new evaluator, checker, helper, nominal fixture/model type, source rejection, dependency, pin, budget or timeout was added.

This is deliberately a scoped repair, not complete `where` lowering.
At this checkpoint, other accepted predicates retained the unfiltered expansion and could produce incorrect registrations. I5ag extends that coverage below.
That is an unresolved implementation boundary, not merely an unfinished mathematical proof.
Arbitrary predicates and effects need their actual Swift binding and evaluation connection. Full builder/source assembly also remains open.
The measured source-scope interpretation, generated code, TLA output and checker/kernel connections do not complete a six-link proof row.

The guarded repair passed 255 tests in twelve suites after a 1451.24-second build and 216.146-second execution.
All 1201 captured inputs remained exact. The run included the existing external compiler contracts.
Only this plan changed after that run. Its complete 131425-byte log has SHA256 `5548f8464ea52f99255c90b936761df49d12d705288dcd1b4dd8a298d960221b`.
Inputs, baseline, logs and reviews are retained in `.git/swifttla-proof-evidence/static-builder-loop-filters-2026-11-08/` in the primary checkout.
Mathematical TLA sources and the protected language checklist remain unchanged.
These are implementation regression receipts, not a new theorem, hosted admission or whole-language preservation proof.

### Scalar builder-loop filter checkpoint 8 November 2026

The existing owner now checks 21 predicates against independent selected indices and actual Swift result-builder execution.
The peer verifier must retain the same action/API order and compiled successor values, including a trailing action.
Known Boolean/Int bindings, comparisons, unary negation, short circuit and arithmetic use the existing constant folder.
Signed quotient/remainder follow Swift rather than the formal arithmetic operators. Scoped decoding keeps a loop variable ahead of a same-named module constant.

On committed `1780afcd` producers, twelve predicate cases produced 36 issues in 63 tests.
The first repair passed the per-index arithmetic cases but retained three Boolean-alias failures: nine issues in a 270-test run.
The source type inference omitted Boolean-literal shape metadata. The correction supplies that shape without weakening the folder's primitive-value guard.
The additional Boolean-equality and module-constant shadowing controls were added after the initial baseline; their credit is limited to the actual later executions.

The guarded correction passed 270 tests in fourteen suites after a 1447.97-second build and 218.140-second execution.
All 1201 captured inputs stayed exact. The whole 134420-byte log has SHA256 `016c4e9ee96bde10ad5b46594770405e55fd9e2359dc7fc1a3bd23c077b5f04f`.
The first attempt's outer shell recorder failed after its test run; the failed test summary remains retained. The corrected run retained exit zero through the guarded wrapper.
Inputs, both failed baselines, whole logs and reviews are retained in `.git/swifttla-proof-evidence/scalar-builder-loop-filters-2026-11-08/` in the primary checkout.

Unknown or unhandled predicates remain accepted and can still assemble incorrect registrations.
Contextual types, overload binding, other scalar spellings, effects, traps and complete source/builder/output interpretation remain owned boundaries.
These filter receipts do not address the separate I5ah–I5aj findings from the source-traced main audit.
No new evaluator, checker, nominal fixture/model, dependency, pin, corpus, resource limit or source rejection was added.
Mathematical TLA sources and the protected language checklist remain unchanged. These are implementation regression receipts; all six-link rows and universal preservation remain open.
