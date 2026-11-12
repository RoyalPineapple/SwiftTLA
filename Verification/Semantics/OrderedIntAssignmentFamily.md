# Ordered Int expressions and assignment outcomes

## Current proof-core work

This follow-up starts from published `de7f1c1c60f7fe87ab9c7f301b1180c237941169`.
Its ordinary CI passed. Full validation failed after nine required workers failed to acquire runners.
Both runs are terminal, and root reconciled the retained evidence and missing work.
The revision is not admitted. The historical results below keep their original scope.

The first proof slice contains integer literals, prior-state reads and checked addition.
It uses the existing registered, scoped `Algorithm` route.
The canonical `SequentialDependentIntInitialProofModel` initializes `first` to 1 and `second` to `(first + 2) + 1`.
Its labeled step assigns `first` to `second + 1`.
The sequential lowerer also supplies hidden control state and terminal control.
Other accepted expressions and control forms remain in scope for later proof work.
This slice does not restrict language acceptance.

The source meaning evaluates the left addition child before the right child.
A reached child failure stops that expression.
If both children succeed, addition returns the representable sum or its ordered overflow payload.
Raw Swift constant folding remains a separate source-elaboration obligation.
The eight internal `OrderedIntNode` cases cannot inherit the three-constructor expression theorem.

### Deriving the plan bounds

`OrderedIntExpressionRule` already defines the postorder index-stack operations in `ExpressionIndexStack`.
The new construction lemmas reuse those operations and `HistoryAppend`:

- `PostorderAppendPreservesIndexBounds` proves that retaining a stack prefix and pushing the new index preserves index bounds.
- `PostorderConstructionSuppliesExpressionPlan` derives the earlier-child requirement from typed storage and stack construction.
- `CompletedPostorderConstructionSelectsTheLastNode` proves that the sole final root is the last appended node.

The prefix bounds themselves no longer need to be supplied as an independent invariant.
`PostorderIndexOperations` records the empty stack, prefix removal, append, child selection and successful final height.
It does not require bounded intermediate stacks.
`PostorderIndexOperationsKeepEveryPrefixBounded` proves those bounds by induction over append events.
`PostorderIndexOperationsSupplyTheConstructionInvariant` then derives the existing `ExpressionIndexStack` predicate.
Together with typed storage, these results supply `ExpressionPlan` and its final-root fact.

The operation records correspond to the actual array mutations as follows:

| Actual visitor operation | Formal operation |
| --- | --- |
| `indices = []` | Initial height zero and empty index function |
| Leaf `indices.append(nodes.count)` | Retain the full prior prefix and append the new node index |
| Binary `indices.suffix(2)` | Select the left root below the right root |
| `indices.removeLast(2)` | Retain the prefix of length `before - 2` |
| Parent `indices.append(nodes.count)` | Append the parent index above the retained prefix |
| Successful `indices.count == 1` | Final height one |

The formal position `p` corresponds to Swift array position `p - 1`.
Stored node indices already use `nodes.count`, so their values are one-based in both representations.
The binary arity guard supplies the nonnegative retained-prefix bound.
This operation map is a source review under documented Swift array behavior.
It is not an automatically checked translation of the Swift statements.

`ExpressionNodeStorage` requires typed literal and read slots, integer child slots, and zero child slots for leaves.
It does not assume that addition children precede their parent.
The construction theorem derives that fact from the existing stack equations.
Existing theorem statements, definitions and premises remain unchanged.

These lemmas do not yet prove that the actual Swift visitors produce the formal construction trace.
Both `orderedIntPlan` visitors append leaves and use a pending stack for ordered child traversal.
Their source-to-trace correspondence, literal values, read identities, layout mapping and state projection remain explicit proof obligations.
The compiled visitor also needs the required resolved type correspondence.
No source-to-implementation link is claimed closed by these construction lemmas alone.

### Source review of the actual visitors

This argument applies to the two existing `orderedIntPlan` overloads in `StraightLineAssignmentCheck.swift`.
It uses documented Swift enum, value, array and dictionary behavior.
It is a deductive source review, not a kernel-checked translation of Swift into TLA+.
The mapping from these Swift statements to the formal construction trace remains an explicit proof boundary.

For an initial requested type of `.int`, every pending entry also requests `.int`.
Only the literal, state-read and addition cases match that requested type.
Addition schedules both children with `.int`.
The other five node constructors require Boolean or set types, so they cannot enter a successful Int-root plan.
An unsupported Int expression returns `nil`; it does not produce a wider plan.
Thus an additional runtime filter for the eight internal tags is unnecessary for this specific route.
The `.memberOf` route requests `.set(.int)` and does not inherit this argument.

Define the independent input tree as `Literal(n)`, `Read(k)` or `Add(left, right)`.
Define its encoding by concatenating the left subtree encoding, the right subtree encoding and the parent node.
Each child index names that subtree's final node in the concatenated encoding.
This definition describes syntax and ordered children; it does not evaluate the expression.

The subtree invariant starts with any existing node prefix and index-stack prefix.
Processing one supported subtree preserves both prefixes, appends exactly its encoding and pushes exactly its root index.
Structural induction gives the following cases:

1. A literal appends the associated Int value and pushes the new `nodes.count`.
   A read appends its mapped name and pushes the same new count.
   Neither operation changes an earlier node or index.
2. An unexpanded addition pushes its expanded marker, then the reversed child entries.
   Because `popLast` removes the last entry, the left subtree completes before the right subtree.
   Applying the subtree invariant twice leaves their two roots above the original index prefix.
3. The expanded addition takes those two roots with `indices.suffix(2)`.
   `operands[0]` names the left root, and `operands[1]` names the right root.
   It removes only those roots, appends their ordered addition node and pushes the new count.

Starting with empty prefixes gives a single root at the final node.
`PostorderAppendPreservesIndexBounds` supplies the corresponding prefix-bound step.
The existing `ExpressionIndexStack` equations describe the leaf pushes and binary folds.
The two other construction lemmas then supply the plan bounds and final-root fact.
Only append events advance the formal construction index; unexpanded-parent visits leave that index unchanged.

The compiled overload follows the same pending-stack order.
Its leaves require zero children, and addition requires exactly two children.
Each state-variable ID must resolve through the supplied name table.
With `requireTypes: true`, every visited node must also have the requested Int result type.
The earlier untyped lowerer check supplies structural correspondence, not resolved type correspondence.

The synthesized `OrderedIntNode.Equatable` comparison includes tags, associated literal values, read names and ordered child indices.
Array equality also preserves node count and order.
This encoding has a unique inverse on the three-constructor tree grammar.
A literal or read pushes its corresponding tree.
An addition combines the last two trees in left-to-right order.
Induction over the input tree shows that reconstruction returns that tree with its mapped read names.
Equal successful encodings therefore identify the same tree after the supplied name mapping.
For a supported source tree, its source plan exists.
The subsequent comparison therefore throws if the lowered plan is missing or different.
The unsupported-source early return cannot bypass this comparison for that tree.

This argument still requires a correct source-name/ID association and an Int-valued state projection.
`verifyInitialIntExpression` rejects duplicate layout names before comparing plans.
`verifyResolvedInitialIntExpression` assigns distinct synthetic names to distinct IDs, then reuses that table across both plans.
These checks do not establish parser extraction, original variable identity or layout/type correctness by themselves.
Those facts, actual output decoding and complete failure collection remain separate obligations.

The source-to-builder path already has a production witness consumer.
`#spec` emits `_checkingOrderedIntSource`, which calls `AlgorithmModel.matchesOrderedIntSource` on the real builder result.
The model macro also compares its parsed model with the source witness.
The matcher checks component order, variable initialization, step label, target, expression and assignment order.
Those consumers compare an extracted witness; they do not prove that its syntax extraction is correct.
The next proof interface must reuse these consumers before adding another status API.

### Pending-frame induction

The formal rule now also models the actual expanded flag and pending-stack schedule.
`PendingVisitStep` separates an unexpanded addition, a completed leaf and an expanded parent.
Expansion places the parent marker, right child and left child onto the stack in that order.
The last stack position therefore visits the left child first.
The requested Int type remains fixed by the source-review argument above.

The proof attaches an expected syntax prefix to each pending frame.
These prefixes are ghost proof data. They do not add runtime storage or evaluate expressions.
`PendingVisitContract` requires each completed frame's exit prefix to match the next frame's entry prefix.
For a parent expansion, the left child starts with the old prefix.
The right child expects that prefix plus the completed left root.
The parent marker expects both completed children in their original order.
Folding those two children restores the old prefix plus the parent root.

`ExpandedFramesThreadLeftThenRightIntoTheParent` proves these three frame contracts compose.
Expansion and completion both preserve the pending contract.
`PendingVisitHistoryPreservesTheSourceRootContext` lifts those results across a finite visit history.
`SuccessfulPendingVisitReturnsOnlyItsSourceRoot` derives a single final syntax root when the pending stack becomes empty.
It does not assume that the completed subtrees already agree with an emitted plan.

This is a traversal-contract proof for finite successful histories.
It does not prove termination or construct a retained trace from an actual Swift execution.
The following synchronized proof connects that prefix to the formal record view of the plan-node arrays.
Binding this record view to the physical Swift enum arrays remains a separate source-verification boundary.
The source-to-formal operation map remains manually reviewed, rather than checked by a Swift translation verifier.
No source-to-implementation proof row is marked complete by this intermediate traversal proof.

### Node payloads on the same visit history

`SynchronizedNodeHistory` now threads plan-node emission through that same pending-frame history.
An unexpanded addition schedules work without appending a node.
A completed literal, read or parent appends exactly one node and advances the node count once.
The formal record view corresponds to the existing private enum cases:

| Swift plan node | Logical record fields |
| --- | --- |
| `.literal(value)` | Literal tag and the same value payload |
| `.read(name)` | Read tag and the same name payload |
| `.add(left, right)` | Addition tag and the two ordered child indices |

Unused logical fields have zero values.
An origin table records each appended node's source term as ghost proof data.
It adds no runtime storage or public API.
`NodeRootsMatchVisitPrefix` relates the real index-stack model to those source terms.
For a parent, the pending contract supplies the source children in their original order.
The coupling then identifies the origins of the two referenced child indices.
Child correspondence is derived at that fold, rather than assumed for the completed output.

`SynchronizedNodeHistoryPreservesEverySourcePayload` proves every appended node retains its tag, value or name, and ordered children.
It also preserves all earlier node payloads.
`SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot` derives the final node's source root and preserves the complete per-node relation.
These results use one visit history, including scheduling steps that append no node.
They do not assume equality between a supplied source plan and output plan.

`ExtractedNodePlan` projects these record fields into the existing `ExpressionPlan` interface.
Unused literal slots use zero. Unused read slots use any supplied key from `Keys`.
These choices only make the logical arrays total; they do not add reads or change the Swift node representation.
`SuccessfulSynchronizedVisitSuppliesItsExpressionPlan` derives that plan from a successful synchronized history.
Its remaining type hypotheses are explicit: visited source literals fit the Int bounds, read names belong to `Keys`, and state values have the Int type.
The proof does not establish those hypotheses for arbitrary compiler input.

Actual Swift execution must still supply the stated source view and node-update history.
Literal decoding, source variable identity, resolved types, layout IDs and state projection remain owned obligations.
For sequential writes, captured values also need a correct environment projection.
A plan match does not justify reading every later assignment from one unchanged prior state.
The current pilot contains one assignment, while other accepted action forms remain in scope for later composition.
The actual generated Swift and TLA+CFG connections, complete failure collection and whole-language theorem remain open.

### Layout names and integer read values

`UniqueLayoutNamesPreserveEveryReadValue` consumes the initializer checker's actual name-count guard.
For a finite ID table, equal domain and name-range counts imply an injective name map.
The proof uses the pinned standard-library finite-set theorem, rather than a new cardinality algorithm.
The same result then preserves every integer read through the inverse name projection.
Only a chosen subset of IDs needs integer values.
Other layout entries, including hidden control state, do not acquire an Int assumption.
The inverse is a mathematical description of name lookup; no runtime inverse or observer is added.

The physical association follows these existing operations under documented Swift behavior:

1. `CompiledLayout.init(source:)` enumerates the normalized variable declarations.
   It copies each declaration name and uses its enumeration index as `VariableID.ordinal`.
2. `verifyInitialIntExpression` builds its ID-to-name table from that layout.
   Its set-count guard rejects repeated names before it compares supported source and compiled plans.
   A supported source read must belong to that table's name set.
   A compiled read must find the same canonical name at its ID.
   Equal private node plans therefore preserve the read identity relative to this layout.
3. `CompiledState.value(for:)` selects the value at that ID's ordinal.
   `CompiledState.projection(using:)` uses the same ordinal and copied declaration name.
   For an integer slot, `CompiledValue.rendered(using:)` returns `.int` with the unchanged integer payload.
   With the same compilation and layout, both paths therefore retain that read value.

This argument is relative to the normalized declarations, not yet to the original authored syntax.
Name identity here uses Swift String equality.
TLA identifier parsing and escaping, and generated Swift field names, remain separate output boundaries.
Partial initialization uses an ID dictionary; an unavailable binding raises an initialization error.
The full-state read argument does not establish that a partial initial binding is already available.

Resolved type checks also need their actual conversion path.
`canProjectRead` can accept nominal or finite representations for an Int use.
Thus an Int result annotation alone does not establish raw Int storage.
`checkedOccurrence` retains the computation type and adds `.convert` when the expected type differs.
`ProgramResolver` retains that operation.
A successful three-constructor resolved plan cannot contain this converted read, because its visitor does not accept `.convert`.
This is an occurrence fact; it is not a reachable-state type invariant.

`CompiledState` checks its value count at construction, but it does not check each slot's type.
Initialization and action preservation must still establish integer storage for the IDs used by this slice.
The caller must also supply the matching compilation and layout.
Captured values in multi-write actions need their own environment correspondence.

The source-to-record interpretation remains a reviewed deduction, not a mechanically checked Swift translation.
The name projection theorem closes a conditional mathematical read-value premise.
It does not close source extraction, actual output acceptance, complete failures or a whole implementation row.
No further standalone traversal or index lemmas are needed for this slice.

### Supported-source acceptance contract

Normal checker completion is useful only after a coverage condition is established.
For this slice, the source contains a registered scoped `Algorithm`, prior-state Int reads, literals and checked additions.
Its initialization and single labeled assignment must reach the existing source and resolved checks.
The canonical owner supplies this accepted route without changing production code.
Other accepted routes remain open; they do not become compilation errors for this proof.

For this condition, the existing consumers give the following implication:

1. `components` and `value` extract the ordered variable and step witness.
   Prior reads use the names already entered in `roots`.
   Literal-only Swift arithmetic is folded separately, with its overflow checks.
2. `verifyRewrite` permits the inserted identity arguments and compares the remaining source tokens.
   `checkingBuilderOutput` attaches the witness to the real result.
   `_checkingOrderedIntSource` compares that result through `matchesOrderedIntSource`.
   A mismatch adds a diagnostic, and source validation rejects that diagnostic.
   The model macro separately compares its parsed model with the extracted witness.
3. The supported source plan exists by the three-constructor subtree argument.
   Thus its initializer check cannot take the unsupported-source early return.
   Successful comparison preserves the node sequence, literal values, canonical read names and ordered child indices.
   The resolved comparison also requires Int types at every visited node.

This is a conditional source deduction, not a new certificate API.
The coverage condition and statement-to-model interpretation remain explicit.
In particular, successful compilation alone does not prove that a skipped checker supplied this implication.

### Actual Swift initializer decoding

`verifyIntInitialOutput` combines a complete function-template check with `verifyOrderedIntInitialExpression`.
Both consume the actual emitted declaration.
For this pilot, every initializer is an Int value expression or a hidden control-location literal.
There are no parameters, selected initial invariant or membership initializers.
These conditions make the complete template builder eligible.
Unexpected membership helpers cannot influence its expected output: the final helper count must be zero.
The expected Int expression is built from resolved IR, without calling the production expression renderer.

The expression decoder has a separate three-case `Step` representation.
Its expected sequence uses zero-based indices; the formal node plan uses the same indices plus one.
It requires one matching `let name: Int` binding.
For an addition, it checks each temporary declaration, then its value, in compiled postorder.
A decoded leaf must retain the exact integer or mapped slot name.
A decoded addition must call the qualified checked-add helper with the expected ordered earlier temporaries.
It then requires the return of the final temporary and the closing expression tokens.
The whole template check excludes additional statements and trailing expression changes.
The local continuation-token check alone is not a complete function check.

The complete Int initial-function check retains exact token text and prefix/binary operator classification.
Five actual negative literal controls retained equal text-token sequences while changing those classifications.
They passed the original check, with correct generated positives and mutation guards passing.
The all-kind comparison rejected valid fixtures before tests: expected `binaryOperator("<")` versus actual `leftAngle`.
The owner now allows an angle delimiter paired with an operator only when their text matches, retaining the minus distinction.
All other token kinds, counts and existing expression checks remain intact. The guarded focused run passed 55 tests in five existing suites.
The attempted blanket parser-error guards rejected configured corpus members before tests executed; they are removed.
The declaration factory, integer emitter and checker template remain unchanged from `6f7702cc`.
This token comparison does not establish general recovery, printing, grammar or symbol binding. Those obligations remain explicit below.

The separate action-output owner now checks the parsed first statement for recognized scalar Int captures and writes.
Its existing division baseline accepted malformed unary-minus syntax despite a parser-error-marked capture declaration; correct output and mutation guards passed.
The guard reuses the existing direct/arithmetic Int recognizers and preserves the earlier value and continuation checks. The guarded repair passed 88 tests in seven existing suites; this is local regression evidence.
Unsupported value shapes, whole-function grammar and parser-library soundness remain separate obligations.

Induction over these declarations preserves each completed subtree value.
Swift `try` stops the expression at the first reached throwing declaration.
Thus a failed left subtree prevents evaluation of the right subtree and parent.
`_NativeMachineOperations.add` calls `addingReportingOverflow` with the ordered operands.
Its `checked` helper returns the reported value or throws the addition overflow with those same operands.
Generated callers reach it through the module function `_nativeIntAdd`, whose body binds the member in library scope instead of caller extension scope.
Under documented Swift Int behavior, this is the source expression's value-or-failure rule.
This argument assumes correct slot values, helper symbol binding, and interpretation of the accepted Swift tokens.
It does not prove the surrounding initializer's complete branch-failure collection.

The remaining source and output interpretation boundaries are precise:

| Boundary | Existing owner | Remaining obligation |
| --- | --- | --- |
| Authored syntax to witness | `OrderedIntSourceSyntaxCheck.components`, `integer`, `value`, `render` | SwiftSyntax input, precedence, type/operator binding, other literal routes, names and labels. [Numeric decoding](LanguageProofPlan.md#raw-integer-literal-code-case-result-7-november-2026) has a manual proof under its stated syntax and binding premises. |
| Witness to real model | `verifyRewrite`, `checkingBuilderOutput`, `_checkingOrderedIntSource`, `matchesOrderedIntSource` | Emitted witness and actual builder identities |
| Source and resolved trees to node arrays | Both `orderedIntPlan` overloads | Reviewed Swift statements implement the checked synchronized record history |
| Actual Swift tokens to expression steps | `verifyOrderedIntInitialExpression` | Accepted token grammar and scoped temporary interpretation |
| Complete initial function | `intInitialOutputSource`, `verifyIntInitialOutput` | Template meaning, field identities and selected-initial filtering |
| Runtime calls and observations | `_nativeIntAdd`, `_NativeMachineOperations.add`, `checked`, `visitInitialBranch` | Module/scope interpretation, other helper bindings and complete observation connection |

These are bounded source arguments under named interpretations, not a mechanically checked Swift translator.
The current formal proof is unchanged; no new traversal model or decoder is added.
Actual TLA+CFG decoding, complete initial states and failures, hidden control and selected checking still need their own connections.

### TLA initialization and configuration boundaries

`verifyRenderedInitialConjunction` checks the complete actual `Init` declaration, including its predicate count.
For this pilot, its required entries cover every literal, dependent Int value, hidden control value and Int-state filter.
The Int predicate and failure checks build their addition structure separately from `CompiledTLARenderer`.
Their postorder guards select a failed addition only after every earlier reached addition succeeds.
Prior initializer bindings wrap each failure relation with their value and definedness conditions.
The large-integer formatter uses signed base-billion chunks; its TLA arithmetic must retain the original integer.
These arguments still require the stated TLA identifier, literal and operator interpretations.
Equal declaration text alone does not establish those interpretations.

`validateInitializationDependencies` also supplies a concrete prefix fact for this slice.
Its read analysis gives empty reads for literals, singleton reads for state variables, and child-read unions for additions.
It rejects reads outside the initialized ID set, duplicate targets and omitted layout variables.
On successful Int prefixes, `CompiledEvaluator` returns integer literals, earlier integer slots or checked integer sums.
`CompiledRuntime.initialOutcomes` extends its value dictionary only after evaluation succeeds.
Induction therefore preserves raw integer slots on successful prefixes of this covered slice.
Its completed state uses the same runtime identity and layout, in layout-variable order.
This argument does not establish a general type invariant for every accepted initializer or action.

The normal configuration defaults to `SPECIFICATION Spec`, not separate `INIT` and `NEXT` directives.
The emitted `Spec` body contains `Init`, stuttering-closed `Next`, and the selected fairness conditions.
`verifyCheckingConfiguration` checks deadlock and selected invariant/property lines.
It does not independently check the behavior-selector lines or the `Spec` body.
Those connections still depend on the named `TLCConfiguration.render` and module-emission source paths.
The dedicated initial-failure probe has a stronger structural check: its entire module and configuration must match.
That probe has no initial states and checks the failure aggregate through an assumption.
Its result is not a complete graph or a general checking-outcome proof.

The failure observation remains the stopping boundary for the pilot.
The TLA aggregate reports whether an initial failure exists.
Its deterministic selected record carries site, kind, operands and the preceding binding prefix.
The prefix uses source-visible names in UTF-8 key order, including hidden control, and excludes the failing target.
The existing output checker constructs this expected prefix independently from the compiled initializations.
The v4 evidence consumer takes its expected prefix from the actual native failure projection.
Its generated theorem checks the complete record; the existing hosted proof job also rejects an erased prefix.
This does not retain every branch's preceding partial bindings in TLA.
The `SingleAssignment` site/payload theorems describe only the site, kind and operand projection.
They do not establish the new prefix field or mechanically connect it to every accepted initializer.
The native and compiled collectors now retain every callback event with a typed site and immutable captured prefix.
Its formal prefix projection is lazy, so evidence conversion does not introduce errors into application initialization.
The existing evidence consumer now serializes these contexts; the selected first-failure properties derive from the event array.
The constructor and generated consumers migrate together to `InitialEvaluationOutcomes(states:failures:)`.
The local checks passed for ordered branch events, lazy projection, changed prefix values and the actual evidence artifact.
An external client also compiled and ran its generated typed surface.
Manual constructors must now supply failure events instead of a selected first failure.
Existing repository and generated callers use the new constructor.
These source changes still require hosted admission.
It is not a proof of complete source events or TLA event correspondence.

### Coverage and complete observations

`verifyInitialIntExpression` returns normally for unsupported source plans as well as matching supported plans.
Normal completion therefore does not certify coverage.
The next connection must distinguish certified coverage from unsupported or open coverage without rejecting accepted forms.
This coverage argument adds no evaluator, status interface or test seam.

Complete initialization includes every allowed full initial state and every reached branch failure.
The existing formal failure event retains the partial bindings before failure, the initializer site and the payload.
At published `de7f1c1c`, `InitialEvaluationOutcomes` retains only a selected failure and initializer ordinal.
The event-collection repair passed its focused execution checks and existing rejecting controls.
The complete Int checker retains whole-function token equality and its separate expression decoder.
Its expected template uses complete lexical lines to avoid recursive parser stack exhaustion.
The existing fallible-domain case reproduced the stack crash and passed after this repair.
The complete internal observation must precede any public first-failure selection.

The feasibility gate also requires actual Swift and TLA+CFG correspondence, labeled assignment and hidden-control composition.
Default deadlock and selected checking outcomes follow those connections.
`CheckingSelectionComposition` still assumes equal initial states, edges, failures and predicates.
These assumptions remain open. Tests, fixtures and TLC comparisons remain regression evidence.

## Earlier domain and initialization follow-up

Status: candidate follow-up to failed `bac1d6cd`, based on admitted `2f0098a`.
Both automatic hosted runs at `bac1d6cd` failed; their retained evidence is fully reconciled.
Ordinary CI found stale initialization expectations and one unproved assignment obligation.
Full validation also lacked required comparisons after hour-clock provider abandonment and a prisoners artifact-action failure.
Those provider causes remain unknown. This follow-up is not admitted.
No complete accepted-program rule is claimed.

The prior local batch proved 26 ordered rows and 3,527 obligations; that pass did not replace hosted failure.
The measured follow-up passed 599 tests across all 55 selected suites.
Its focused assignment proof proved 108 obligations with the same theorem statements and premises.
All 158 snapshots, both runners and the qualified tool/input hashes matched that check.
The complete pinned `--nofp` batch proved 26 ordered rows and 3,530 obligations.
The seven affected legacy modules proved 2,450 obligations, including all 2,074 in `SingleAssignment`.
The expected hosted inventory is 101 modules and 8,020 obligations.
That total combines the current rule batch and seven legacy runs with exact unchanged logs for the other 68 legacy modules.
It is not a fresh local run of all 75 legacy modules or hosted admission.

The existing five-owner baseline executed 46 tests and captured seven complete module mismatches.
Together with the hosted OrderedCopy pair, all eight affected outputs were measured before migration.
Only their `Init` declarations changed; every action and failure definition remains exact.
The ten fixed integer bindings satisfy the added type predicates, so these regression initial states are unchanged.
The refinement owner now checks each complete specialized `Init`, including value 3 and its type predicate.
The ordinary receipt retains its prior 256 paths and adds seven canonical regression owners, yielding 263 entries.
No production source, authored model, DSL form, theorem premise, tool pin or checking limit changes.
No new fixture is added.

## Current domain queries and initialization connection

`FiniteSetMembershipRule` separates mathematical domains from generated predicates that avoid enumeration.
Its range and eager-union rules preserve every member and the selected child failure payload.
Its `integerSet` rule supplies mathematical `Int` and an always-true membership predicate.
Finite postorder histories compose these constructors under explicit operand and leaf agreement.
The `integerSet` constructor has no child or supplied leaf-agreement premise.
`OrderedIntAssignmentComposition` connects their query results to the complete labeled assignment observation.

The existing lowerer and actual Swift/TLA+ owners retain their positive and rejecting controls.
Independent checks cover supported source operands, emitted range predicates, and the selected failure operands.
The initialization connection and declared-type filters appear in [InitializationFamily.md](InitializationFamily.md).
Source extraction, unsupported constructors, concrete traversal, and checker/kernel soundness remain open.
These local results do not establish hosted admission or universal preservation.

## Finite integer-domain equality

The source rule compares a finite integer domain with the complete mathematical interval.
The generated rule handles an empty domain first.
For a nonempty domain, it checks the last endpoint from the count and requires every key within the interval.
The proof uses the pinned standard-library finite-set theorems without expanding recursive cardinality definitions.
An internal endpoint overflow makes the query false; it does not create a model evaluation failure.
The parent rule preserves operand order and each genuine child failure payload.
The assignment connection supplies the resulting Boolean value or failure to the complete labeled observation.

The baseline ran the three existing equality cases with production code unchanged.
It recorded nine accepted corruptions across source, actual Swift, and actual TLA+ checks.
It also recorded four incorrect runtime outcomes across the native and compiled paths.
Wide equality raised an enumeration-capability error instead of returning false.
Range-first evaluation hid the genuine domain division failure behind that capability error.
The repaired cases pass, including all nine rejecting controls and both operand orders.
The interval is never materialized by this query.
The global enumeration guard remains unchanged.

The native output check covers integer-keyed dictionary state reads and the supported scalar or arithmetic bounds.
Arbitrary function-child outputs remain outside that check.
Resolution correspondence, Boolean-query initialization outputs, and checking-specific output links remain unproved.
Finite dictionary key/count projection, source extraction, type correspondence, and checker/kernel soundness remain explicit boundaries.
This rule does not complete the general equality or domain constructors.

## Original assignment connection

The original assignment connection used admitted `c582b814` as its base.
The results in this section describe that earlier stage.

That pinned `--nofp` batch proved all twenty ordered rows and 1,554 obligations.
All 153 proof snapshots and both runner hashes matched the checked inputs.
The combined safety-wrapper check passed 183 tests across all 22 current
regression owners, including both overlapping-target arguments. Static checks
passed family isolation and all five pinned-download controls. These results
are local diagnostics; they do not replace new hosted admission.

This transports the assignment/expression connection from `37e19b06` and
`16244a79`, preserving the current Boolean, sequence, definition, renderer,
native-helper and pinned-tool repairs. Later lexical/capture work is separate.

`PendingWriteOutcomeRule` defines source write constraints separately from the
generated compatible-write merge. `PendingFrameOutcomeRule` reuses that rule
with the prior state's framed value. The complete-state materialization and
frame observations keep their previous meanings.

`AssignmentActionRule` evaluates its child before checking an inherited write.
A child failure retains its payload and has no successor. Conflicting successful
writes disable the assignment without creating an evaluation failure. Its source
observation constrains the target, every inherited write and every remaining
state field; the generated observation materializes the compatible update.

`AssignmentTreeOutcomeComposition` supplies assignment and frame leaves to the
existing finite action-tree rule. Other leaf/condition agreement and the
remaining conjunction-left shape premises stay explicit.
`OrderedIntAssignmentComposition` supplies typed assignment child outcomes from
the independent literal/read/checked-add expression histories. It assumes the
expression plan, Int projection, value/failure domains and `NoFailure` separation.
The shared prefix-induction lemma replaces the expression-local induction proof;
it does not change expression evaluation or arithmetic guard semantics.

The actual lowerer and both output links remain in their canonical owners:
`OrderedAssignmentLoweringTests`, `NativeExecutionBoundaryTests` and
`ConjunctionFailureSelectionTests`. The existing nested-arithmetic Swift mutation
already checks operand order and is reused. The conjunction owner retains its
original nonconflicting case and adds an overlapping-target arm. Its new actual
Swift mutation returns early at the second fallible write when an update is
already pending. Existing TLA failure-selection mutations remain in that owner.
No production Swift code, test seam, model or fixture is added.

These checks do not prove parser/macro/builder extraction, normalization,
postorder-plan correspondence, capture/type/layout identities, checker soundness,
native operation/merge kernels, initialization, program-counter control or
selected checking outcomes. Those SwiftTLA-owned boundaries remain open or
separately tested. The theorem preserves one selected failure, not every branch's
failure set. No accepted DSL form is restricted. Fixtures remain regressions.

The ordinary rule-before-composition batch owns this extension. It adds no
`proof_family` value or diagnostic-dispatch route. The current Boolean/sequence
rules and original family revisions stay unchanged. Admission requires new
ordinary CI and full unfiltered validation on one frozen integrated revision.
