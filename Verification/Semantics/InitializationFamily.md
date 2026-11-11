# Initialization outcomes and composition

Historical typed-initialization checkpoint: follow-up to failed `bac1d6cd`, based on admitted `2f0098a`.
The failed hosted attempt and measured repair are recorded in [OrderedIntAssignmentFamily.md](OrderedIntAssignmentFamily.md).
The local checks at that checkpoint passed 599 tests across all 55 selected suites.
Eight stored outputs now retain the measured typed `Init` predicates; their other definitions remain exact.
The canonical refinement owner checks the complete specialized initial relation.
The initialization rules and production compiler were unchanged by that follow-up.
Its pinned `--nofp` batch proved all 26 rows and 3,530 obligations.
The seven affected legacy modules separately proved 2,450 obligations.
All 158 snapshots and both runner inputs matched the current proof inputs.
These local passes do not establish hosted admission.
These are conditional rules. Complete accepted-program preservation remains open.

## Current mathematical integer domains

`FiniteSetMembershipRule` defines mathematical `Int` independently from the generated membership predicate.
The predicate accepts every integer without enumeration.
An explicit `integerSet` node composes through the existing finite postorder histories.
This constructor does not require supplied leaf agreement.

`OrderedIntInitializationComposition` connects this constructor to the complete logical initial relation after declared-type filtering.
The relation includes every allowed Swift integer and no semantic failure from this constructor.
The existing typed relation rules also retain failure events from other initializer children.
Concrete enumeration, frontier traversal, callbacks, and complete failure storage still need separate correspondence arguments.

A baseline ran four existing cases with production code unchanged.
It found nine accepted checker corruptions and two capability errors in the model-failure channel.
The same cases passed after the repairs.
The existing source and resolved checks now retain the childless constructor, its type, and its empty read set.
The independent Swift output check rejects changed enumeration, membership, and early-return code.
The TLA+ owner rejects replacement of the mathematical domain with an empty domain.

Native `initialOutcomes` now throws `nonEnumerableIntegerDomain` as `NativeMachineEvaluationError`.
The private compiled runtime retains its original `EvalError` channel.
Selected initial-state membership remains available without enumeration.
TLA+ initial predicates retain declared Swift `Int` bounds for state values and failure prefixes.
Other capability errors still need separate constructor baselines.

Source extraction, type correspondence, scheduler extraction, and checker/kernel soundness remain open.
The range-equality action/query rule and measured capability repairs appear in [OrderedIntAssignmentFamily.md](OrderedIntAssignmentFamily.md).
No Boolean equality initialization output link or rejecting control is established by those action checks.
Fixtures remain regressions.

## Earlier dependency checkpoints

Dependency and readiness work used admitted `ba4c9bbf` as its base.
Both automatic hosted gates passed at that base, with complete retained-evidence reconciliation.
An earlier local batch passed 25 ordered rows and 3,019 obligations.
These earlier results do not establish hosted admission for the current changes.

The earlier `3a0dda1b` checkpoint passed 25 local rows and 2,091 obligations.
That result is historical evidence.

## Independent source rules

### Deterministic Int compiler theorem: source contract

The current delivery target is an implementation-linked theorem for the
literal/read/checked-add initialization family. The complete theorem is open.
The plan and output-check theorems below do not supply its implementation links.

A program has a finite ordered list of fresh Int declarations. An initializer
can contain Int literals, reads of earlier declarations and checked additions,
with arbitrary finite nesting. The source placements are scoped root declarations
and the shared-declaration prefix of one registered sequential Algorithm.
The implemented independent source-check instance recognizes closures containing
these declarations and direct `Do` expressions. Other control forms and property
declaration contexts retain their acceptance; their mandatory source-check
coverage remains open.
For this instance, Int and the SwiftTLA constructors have their standard,
unshadowed bindings. Parameters, membership initialization, initial selections,
constraints, procedures and process-local state remain separate proof instances.
Other accepted DSL forms keep their acceptance and remain open.

The source grammar distinguishes ordinary Swift values from formal expressions.
An integer token, `Int.min`, `Int.max`, or a parenthesized ordinary value is a
Swift value. Ordinary additions evaluate before the builder constructs an
initializer. Their normal result is one literal. A read of a shared-variable
handle is formal; `Expr(q)` lifts an ordinary value into a formal expression.
An addition with a formal operand is checked model arithmetic. It must retain
its addition node even when both mathematical operands are literals.
An ordinary Swift overflow is not a reached model-initialization failure.

Define the source expression result before consulting compiler output. For an
available prefix `rho`, use the following rules, with the native Int bounds:

```
eval(literal(n), rho) = success(n)
eval(read(i), rho)    = success(rho[user(i)])
eval(add(l, r), rho):
    left = eval(l, rho)
    if left failed: return left
    right = eval(r, rho)
    if right failed: return right
    if Int.min <= left.value + right.value <= Int.max:
        return success(left.value + right.value)
    return overflow(addition, [left.value, right.value])
```

These are independent mathematical rules. `SourceAdd` and `SourceCombine` in
`OrderedIntExpressionRule` express their checked-add cases. The left-failure
branch does not evaluate the right child. Evaluation stops at the first failed
primitive operation; a total ghost history is not an executed-node trace.
For a finite source tree, structural induction constructs this result before
any emitted plan is consulted. Literals and available reads return immediately;
an addition applies the induction hypothesis to each reached child, then checks
the bounded sum. Induction over the finite declaration list constructs the
source initialization result. This is the source existence argument, not a
claim that every arbitrary record satisfying a history equation is a syntax tree.

Use logical keys `user(i)` for source declarations and a separate control-owner
key for hidden control. Root initialization starts with the empty binding.
For a sequential Algorithm, `AlgorithmLowering` prepends a program counter only
when the source control envelope needs one. Its seed is the first source step's
location. An Algorithm with no steps or a control-free loop has no such seed.
The source-to-layout encoding of this choice still requires derivation in the
complete initialization theorem.

At declaration `i`, evaluate its expression under the current successful prefix.
On success, bind `user(i)` and continue. On failure, append exactly one record
containing declaration `i`, the failure kind, ordered operands and that immutable
prefix. Leave `user(i)` absent and stop initialization. Thus a successful source
run has one complete state and no failures. A failed run has no complete state
and a singleton ordered failure list. This rule includes hidden control in the
prefix; its encoding cannot be hidden in an "other evaluators agree" premise.

For `a := 7; b := a; c := b + 1`, the user bindings are `7, 7, 8`.
For `a := Int.max; b := a + 1`, the event belongs to `b`, has operands
`[Int.max, 1]`, retains `a`, and omits `b`. Source declaration identity must be
derived from the actual layout-to-source mapping; a compiled variable ordinal
is not assumed to be that identity.

The required conclusion is equality of this source result, decoded actual Swift
initialization, and decoded actual TLA/CFG initialization. It includes complete
states, failure lists, first-failure selection and skipped-child behavior.
The physical visitor must derive the expression plan and its ordered children.
The physical output and helper arguments must derive the child outcomes consumed
by `OrderedIntInitializerChildrenComposeAllReachableStatesAndFailures`.
For this deterministic instance, singleton failures can bridge ordered lists to
the parent's failure sets, once uniqueness and physical event retention are proved.
The complete implementation-linked parent instance remains open; regression runs supply
no mathematical credit for them.

### Current implementation and mathematical consumer

The current source witness checks the supported root and registered-Algorithm
initializer routes independently. The lowerer no longer gates their structural
check on an Algorithm program counter. Resolution checks every resolved Int
initializer through the existing owner. The shared ordinary-scalar decoder now
recognizes unshadowed integer bounds within ordinary arithmetic. Explicit
`Expr` operands and state reads keep their formal checked-add route.
The macro first calls the existing `parsed.compile()` gate, which raises retained
parser diagnostics before lowering. It then checks source correspondence before
resolving typed inputs and returning generated metadata. Every successful return
therefore crosses both gates. This order preserves the original declaration
diagnostic when parsing failed; an incomplete parsed model is not compared as
though it were a successful translation. The f329 ordinary run reproduced that
diagnostic-precedence regression in the existing raw-formal-state owner.
The repaired gate passes 86 tests in four source/lowering/output suites. A
separate current run passes 60 connected support-name, atomic-witness, failure
and external-client tests in five suites; both demo owners pass seven tests.
All captured producer bytes remain exact during those runs. The new mathematical
bodies remain unverified.
The earlier source-coverage run passed 233 tests in 22 suites, including the external
generated-code client. These are regression receipts, not hosted admission or
a completed compiler theorem.

The new candidate `SourceSyntaxHistory` defines expression outcomes on source
syntax identities before an emitted plan exists.
`MatchedPostorderNodesRetainIndependentSourceSyntaxMeaning` transports those
outcomes through source-matched node payloads and ordered child identities.
`VisitedSourceSyntaxSuppliesReadyInitializerChildren` derives the partial plan
and the existing initializer child contract from those facts and available
typed prefix reads. It does not accept plan validity as a premise.

`VisitedSourceSyntaxInvokesTheCompleteInitializationParent` invokes
`OrderedIntInitializerChildrenComposeAllReachableStatesAndFailures` with those
derived children. It takes synchronized visit histories and derives their final
node payloads, ordered children and selected source root through the existing
construction theorems. Non-expression rows use concrete source/generated fixed-seed
constructors, so their agreement is derived rather than supplied.
The working revision replaces its supplied total generated-expression history
with `ReachedCheckedPostorderExecution`: values exist only for completed
operations, and the next operation either fails or the final value is returned.
`CompletedSyntaxVisitIdentifiesTheFirstReachedFailure` couples the first failure
in emitted postorder with the source-root failure. Folding children retains the
first failed child in left/right order, including when a later subtree has a
different potential failure. `CompletedSyntaxVisitRetainsTheReachedCheckedOutcome`
then derives the source outcome from checked operations on already stored operands.
It supplies no evaluator-agreement premise. The total generated history needed
by the older child interface is now constructed as ghost proof data, rather than
received as a description of executed output.

The working observation consumer uses
`SingletonInitialObservationsRetainOrderMultiplicityAndFirstFailure` to recover
ordered histories from equal set projections. Its length bounds are derived by
`SingleBranchInitializationDerivesItsObservationBounds` from one live branch,
state replacement on success, one failure append on error, and no later step
after that error. Bounds are no longer supplied separately.
`SingleBranchObservationsSupplyTheirSetInitializationHistory` also derives the
endpoint set projections; the consumer no longer receives them as assumptions.
Instantiating the operational histories with actual decoded outputs remains an
implementation obligation. A singleton set alone cannot establish these bounds.
The working parent now also constructs a shared operational history. It derives
the deterministic candidate-or-failure property from its expression children and
fixed seeds, then invokes
`DeterministicReachableInitializersConstructTheirOrderedObservations`.
The finite-prefix proof replaces the one live state on success, appends the
immutable prefix and site on failure, and keeps every later observation unchanged.
Reachable child agreement makes that same history a generated history. Thus the
parent's ordered-observation conclusion no longer depends on histories existing
only inside the antecedent of an implication. This new proof body is unverified.
The next working change also removes the supplied Int-range invariant for every
reachable prefix. Induction starts at the empty binding. A successful expression
row obtains its bounded value from the reached-operation theorem; a fixed row
uses its constructor's scalar type fact. Source extension preserves every earlier
Int binding. The parent then uses the derived projection type for its child rules.
Its remaining fixed-row premise says that an Int key has an Int seed; actual
control keys are outside the Int-key set. The physical layout/type association
and this new proof body still require verification.
Pinned `fdc680d3` CI leaves one of 1,688 reached-expression obligations and
12 of 1,165 single-branch history obligations unproved. The earlier unbound
witness now elaborates, but the initialization parent stops in the pinned
Zenon formatter with a stack overflow. Its log identifies no source obligation;
no parent theorem result is inferred. The source-to-postorder meaning lemma is
not among the reported expression failures; its physical compiler interpretation
remains open.
The next body-only repair applies the append rule directly to its constructor
arguments, hides local observation definitions until their leaves need them,
and supplies set extensionality at the failed projection equalities. Explicit
natural-number induction constructs every finite observation prefix. The parent
keeps the integer-domain fact local to SMT applications of instantiated expression
theorems. It no longer exposes that large numeral to default logical steps.
This targets the formatter's recursive numeral expansion; the exact crashing
obligation remains unidentified. Statements, premises, definitions, tool pins,
backends, resources and budgets remain unchanged. These new bodies and the
complete compiler-initialization theorem are unverified. A failed proof attempt
does not establish theorem falsity or compiler agreement.

The source/control trace also exposed a real hidden-seed rendering gap.
Existing validation admits ASCII control identifiers, including names beginning
with the formal string-codec marker. The old control renderer quoted such names
directly, while the actual failure-prefix checker required the protected literal.
The existing source-to-output owner reproduced that rejection after a valid
ordinary-label baseline. The shared renderer now uses the existing TLA string
encoder. No name restriction or output-check weakening is introduced. Its focused
existing owner now passes, including the ordinary-label baseline and accepted
marker name. This is regression evidence, not proof credit for the control association.

The native initializer generator now assembles its nested scopes with the existing
SwiftSyntax builders, instead of reparsing one deeply nested function string.
Complete prefix statements are parsed separately; a reverse fold wraps each suffix
in the same selection or branch scope. Existing output checks still validate the
whole function, initializer expressions, failure recovery, and final assembly.
The four focused output-owner suites pass on that producer. A separate initializer
owner exposed recursive membership type checking; membership now uses the existing
compiler worklist with domain-first checking, value-first refinement, and the same
final Boolean type check. That exact owner passes. The final producer also passes
the combined 106 tests in 13 suites and all seven demo-caller tests in two suites.
These runs retain their complete logs and exact source inputs; they do not prove
the new mathematical bodies or establish hosted admission. The syntax-builder
fold and physical scope/helper/field interpretation remain owned correspondence
obligations.

The physical visitor has a manual loop-simulation argument for this fragment.
A leaf appends its payload and new index. Expansion pushes the parent, right and
left onto the LIFO work array. Completion consumes the last two root indices in
left/right order. Ghost source prefixes and origins identify these transitions
with the existing synchronized model; they require no runtime observer.
Assign weight one to leaves and expanded parents, and weight
`weight(left) + weight(right) + 2` to an unexpanded addition. Each iteration
decreases total pending weight by one, establishing finite completion.
The source-view/read-key association and full mechanical Swift interpretation
remain separate boundaries; the manual loop argument does not assume a valid
emitted plan.

The physical visitor/source-tree mapping, existence of independent syntax
meanings, actual Swift/TLA reached-operation equations, physical prefix-type association,
control-seed encoding, and the at-most-one bounds for actual output remain
owned obligations of the final theorem. The new consumer states those limits
explicitly; it does not discharge them by assuming evaluator agreement or
claiming that a source/output checker is sound.

The constructor rules define fixed, domain and failed outcomes separately from generated adapters.
An empty successful domain has no candidates and no failure.
A failed domain has no candidates and retains its complete payload.
Source extension requires a fresh state identity and retains every preceding binding.
The generated rule constructs that extended map explicitly.
Their equality preserves complete partial states and branch failure events, including the preceding binding, source identity and payload.

The composition uses separate source and generated histories.
Each layer contains every successful extension and failed branch; later layers retain earlier failures.
The theorem covers arbitrary finite variable counts, including zero, and proves that both histories exist.
Its premises include a distinct key order covering the state identities and typed child outcome agreement on every valid prefix.
The source constraint relation reads each initializer under its preceding keys.
Its complete conjunction equals the final source prefix state set.
Selected-invariant evaluation retains true states, removes false states and adds failures without an initializer site.
Selected child correspondence remains a premise.

The mathematical value universe and candidate domains need not be finite.
Native enumeration capability and termination require separate arguments.
A separate storage rule preserves the first failure's site and payload.
Its negative theorem shows that retaining the same first record does not prove preservation of all later events.
The public native result now stores the complete list of reached failure events, with a lazy projection of each preceding prefix.
Its first-failure properties select the first list entry. They do not replace that list.

### Scalar literal normalization and lowerer coverage

This code-case result starts with an existing declaration constructor, not raw Swift syntax.
Let `n` be any stored `Int` payload, including either bound of that Swift execution, and let `i` index `compileModule`'s variable array.
Suppose that declaration was constructed with `.value(.int(n))` or `.expression(.value(.int(n)))`.
For the normally returning `lower(spec: self)` call made by `compileModule`, its scalar check is mandatory.
Its local initialization entry retains `n` at `VariableID(ordinal: i)`.
No authored Algorithm or program-counter premise is needed for this result.

The proof uses documented Swift enum matching, value copying, array enumeration, `zip`, and dictionary replacement.
Its physical owners are [declaration construction](../../Sources/SwiftTLA/TLASpec.swift),
[builder assembly](../../Sources/SwiftTLA/TLASpec+Building.swift),
[algorithm lowering](../../Sources/SwiftTLA/AlgorithmLowering.swift),
[module compilation](../../Sources/SwiftTLA/SpecCompilation.swift),
[layout construction](../../Sources/SwiftTLA/CompiledLayout.swift),
[lowering](../../Sources/SwiftTLA/CompiledLowerer.swift) and
[the scalar check](../../Sources/SwiftTLA/StraightLineAssignmentCheck.swift).

1. `VariableInitialization.normalized` converts only `.expression(.value(v))` to `.value(v)`.
   Every other constructor returns unchanged. Applying it twice therefore has the same result as applying it once.
   For `v = .int(n)`, it copies `n`; it performs no integer arithmetic, state access or model evaluation.
2. Both `VarDecl` and `NamedVar` store `initialization.normalized` in a `let` property.
   The formal-core typed-expression `Variable` overload passes through `VarDecl`.
   `TLASpec` builder assembly passes a `VarDecl` through `NamedVar`.
   The reviewed shared-variable paths in `AlgorithmLowerer` also construct `NamedVar` from the shared initializer.
   Thus, at each of these storage boundaries, either stated input becomes `.value(.int(n))`.
   This derives local wrapper coverage; raw parser selection and other placement routes remain separate.
3. `compileModule` constructs `CompiledLayout(source: self)`, then passes that layout and the same `self` to `CompiledLowerer`.
   The layout enumerates the variable array, assigning ordinal `i` and retaining that entry's declaration name.
   The lowerer checks equal variable counts before its `zip` loop. No variable can disappear through zip truncation on normal return.
   Its iteration for entry `i` therefore pairs that declaration with `VariableID(ordinal: i)`.
4. For the normalized initializer, `checkIntInitializer` takes its first branch and becomes `true`.
   The authored-Algorithm/program-counter branch cannot suppress this call.
   The lowerer calls `verifyInitialIntExpression` before inserting the lowered initialization into its dictionary.
   That check recognizes this source literal unconditionally and compares its singleton literal plan against the lowered value plan.
   On normal return, the lowered entry has the same integer payload and no children, by the scalar extraction result in the working plan.
   This stage does not establish its resolved type.
5. The lowerer inserts this checked value at the paired ID. Enumeration makes the IDs distinct, so another iteration cannot overwrite that slot.
   This establishes the local source-declaration/ID association and payload at insertion.
   It does not establish later scheduling, resolver identity transport, source-visible names or runtime prefix freshness.

The removed owned assumptions are that these constructor wrappers might leave the scalar in an unchecked expression case,
and that the lowerer might skip the literal check when authored control is absent.
This supplies the normalized scalar argument and mandatory invocation used by the existing scalar code-case result.
When the later resolved variable type is `.int`, the separate resolver argument can then use its proper-literal branch.
That resolved-type fact and transport to the resolver are still obligations; they are not supplied by normalization.

For the existing `IntExpressionOutcomesSupplyInitializerOutcomes` consumer, instantiate the integer-bound constants with the same bounds as `n`'s Swift execution.
Then `n` belongs to their interval, and the already derived literal result is `Expressions!Success(n)`.
Its stated `IntInitializationDomains` premise supplies the value-domain fact needed by `FixedInitializerRetainsItsOnlyCandidate`.
The parent then receives the singleton candidate `{n}` with `NoFailure`.
`InitializerLeafRetainsCompleteStatesAndFailures` still requires the source target, a typed prior map and a fresh key.
This proof does not discharge those parent premises or complete initializer state/failure histories.

The result is a manual implementation-correspondence proof for these code cases, not a mechanically checked Swift translation.
The reviewed normalization and lowerer bodies are unchanged. No new Swift tests or TLAPS obligations were run for that documentation checkpoint.
Macro/source fidelity, type and helper binding, output/checker soundness, full-width TLC capacity and all complete six-link rows remain open.

### Compiled expression occurrence identity

`CompiledExpression` equality denotes an occurrence, not structural equality of its operation, type and children.
The former UUID token required a separate uniqueness assumption. No actual collision was observed.
The implementation now uses a private, empty, final `Sendable` class instance as its token.
The expression remains a value struct; the token has no children or mutable state.
This matches the existing identity/hash pattern for `CheckedOperatorCall`.

The local invariant follows from documented Swift [reference and identity semantics](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/classesandstructures/)
and [ObjectIdentifier lifetime semantics](https://developer.apple.com/documentation/swift/objectidentifier):

1. Each normally returning expression initializer creates a fresh token instance.
   Distinct live constructions therefore compare unequal with `===`, even when all expression payloads agree.
2. Copying an expression copies its reference to that token. Equality and `hasSameOccurrence` therefore agree and preserve occurrence identity across copies.
   The operation, type, children and token are immutable after initialization.
3. Equal expressions hash the same `ObjectIdentifier`. Hash collisions between unequal tokens cannot make them equal.
   Dictionary and Set operations still compare the expressions' token identities.
4. Actual resolver keys store a `CompiledExpression`, and emitter caches, visited sets and the renderer's candidate cache also store expressions as keys or members.
   Those values retain their tokens throughout membership. Object-address reuse after deallocation cannot alias a token still retained by a key, a member or the expression being compared.
5. The token owns no expression or child token. It cannot create a recursive token-ownership chain or reference cycle.
   Compiler-checked `Sendable` conformance requires no unchecked escape or synchronization state.

This removes the probabilistic uniqueness premise for live `CompiledExpression` keys.
In particular, a resolver cache hit cannot arise solely because two distinct expression occurrences received the same token.
It supplies the occurrence-separation fact needed by the literal resolver argument; it does not prove that the cache key contains every semantic context.
Resolver traversal, type preservation, capture ownership and the meaning of cached results remain separate obligations.
Other declaration identities are outside this change. No cross-process or serialized expression identity is claimed.
This is a manual code-case proof under trusted Swift behavior, not a new TLAPS theorem or a mechanically checked compiler proof.

### Typed scalar literal transport through resolution

Consider a proper `.value(.integer(n))` initializer with no expression children at variable `v`.
Suppose its `CompiledTypeInputs.variableTypes[v]` is `.int`, and its compiled input uses the pilot's literal/read/addition and sequential control routes.
In particular, there are no operator/callback calls, process-local projections or procedure scopes in this code-case instance.
If `CompiledProgram(inputs:)` returns normally, the checked and resolved initializer at `v` is a proper literal with payload `n`, type `.int` and no children.
Its final variable type is `.int`. The result preserves the variable ID, not the expression token across newly constructed compiler stages.

The physical owners are [type inputs](../../Sources/SwiftTLA/CompiledTypeInputs.swift),
[checking](../../Sources/SwiftTLA/CompiledTypeChecker.swift), [type merging](../../Sources/SwiftTLA/CompiledValueType.swift),
[resolution](../../Sources/SwiftTLA/ProgramResolver.swift), [behavior transport](../../Sources/SwiftTLA/CompiledBehavior.swift)
and [initializer transport](../../Sources/SwiftTLA/CompiledExpressions.swift).

1. The checker copies the input type map. `merge(.int, t)` returns `.int` when `t` is `.int` or `.unknown`; every other case throws.
   Its initializer, assignment and nonprojecting state-read updates all use that merge.
   Projecting state reads leave the map unchanged. Authored sequential checking restores the saved map on exit.
   The excluded call/process routes are the other scope updates. Induction over the actual returning updates therefore preserves `variables[v] == .int`.
2. For the literal initializer, `checkOperand` takes its direct `inferResolved` path.
   `literal(.integer(n), expected: .int)` skips union, finite and named cases, chooses `.int` and merges equal types.
   The returned `CheckedType` has `.int` for both types, no call and its default empty children.
   `checkedOccurrence` copies the literal operation and uses those children. Equal result/computation types prevent a conversion wrapper.
3. The initializer array retains `v` and the value-initializer tag.
   In the finishing pass, its result type equals the invariant final `.int`, and its computation type is resolved.
   The pass therefore returns this expression unchanged. The checked program retains the map and initializer.
4. `ProgramResolver` starts with an empty expression cache. For this literal occurrence and function context, a first visit schedules its expanded task with no children and no call.
   That task copies the literal operation, `.int` type and empty children into the cache.
   The only alternative cache insertion is the local-declaration case, which cannot apply to this literal.
   By the occurrence-separation result, a different occurrence cannot populate this key.
   Induction over insertions therefore also proves that any cache hit for this literal key has exactly that payload, type and child list.
   The literal uses no capture lookup, so this case needs no assumed agreement between capture environments.
5. `CompiledBehavior.map` retains each initializer's variable ID; `CompiledVariableInitialization.map` retains its tag.
   Resolution forwards the checked variable-type map and layout. Its final proper-literal Int guard invokes the existing independent resolved check even without authored control.

This removes the checked/resolved payload and type-transport assumptions for the stated compiled pilot case.
Together with the preceding normalization result, it supplies the proper typed literal consumed by the existing scalar evaluator argument and `IntExpressionOutcomesSupplyInitializerOutcomes`.
The source connection for an unannotated scoped shared literal is derived below.
Other placements, annotations and alias/nominal routes retain their source-type obligations.
General calls/processes, cache-context completeness for nonliterals, backend interpretation, complete initializer histories and all six-link rows remain open.
This argument changes no checker, evaluator or theorem body. It is a manual implementation proof, with local regressions kept separate from mathematical proof and hosted admission.

### Registered Algorithm shared literal source use

This is the source-use instance for a single registered `let algorithm = Algorithm(scoped: { scope in ... })`.
Inside that body, take a single unannotated immutable declaration `let x = scope.sharedVar(initial: literal)`.
There is no explicit `_name` override, competing binding for `algorithm`, or duplicate state root in this instance.
The literal is one of the signed/radix/parenthesized standard-Int forms in the existing raw-integer argument in the language plan.
The AST/token provenance, standard Int/operator binding and equal host/target bounds remain its explicit premises.
All other accepted placements, overrides, annotations and binding situations remain in the language domain with their own obligations.

The independent meaning names the shared state `x` and gives its initializer `Success(n)` with no model reads or failures.
The following code-case argument derives the parser's use of that child, rather than assuming that decoding and target selection succeeded:

1. `parseSpecClosure` visits the immutable Algorithm binding through `parseLocalDeclaration`.
   The actual constructor branch passes its source identifier as `boundName` to `parseAlgorithm` and stores the returned Algorithm under that key.
   The later registration reference retrieves that stored value and appends it to `sourceAlgorithms`.
   The final nonempty source-algorithm array selects the `.source` phase.
2. `algorithmBuilderClosure` selects the `scoped:` closure. `closureParameterNames` extracts its declared `scope` parameter.
   In the body loop, the declaration has one identifier binding and a member call whose base matches that parameter.
   `AlgorithmSourceConstruct.isState(.shared, in: declarationScope)` therefore succeeds, and `parseAlgorithmVariableDeclaration` takes the shared-state branch.
   With no `_name` argument, `declaredName` is exactly the source identifier `x`.
3. The `initial:` argument is passed to `decodeTypedFacadeValue` without a nominal expected type.
   The existing raw-integer argument supplies `.value(.int(n))` for this syntax, including parentheses.
   Thus the value branch is taken; the `in:` domain alternative cannot replace it.
   It constructs `AlgorithmStateModel(root: x, initialization: .expression(.value(.int(n))), ...)`.
   The existing source-type argument supplies the primitive Int metadata, independently of an occupied short type name.
4. The returned `.shared` component is appended to `algorithmComponents`; the visible handle is bound to `.variable(x)`.
   That scope extension happens after decoding the initializer, so it cannot introduce a read or rewrite this literal.
   `AlgorithmModel` stores those components. `resolvingAtomicSteps` leaves `.shared` components unchanged in its default case.
5. `TLASpec.compile()` first calls `loweredSourceModel`. Its `.source` branch lowers the stored Algorithm and appends its lowered variables.
   Both the ordinary Algorithm lowerer and its sequential specialization copy the shared root, initializer and primitive metadata into `NamedVar`.
   Its normalizing constructor gives `.value(.int(n))`; the earlier same-source layout/lowerer argument then identifies its actual ordinal ID.
   Compiler-created control fields may precede it. The runtime target/prefix argument uses the actual order and does not assume that `x` has ordinal zero.
6. In the macro path, `TLASpecVerifier.parseAndVerify` uses that same parsed specification for compilation and the same source resolver for `CompiledTypeInputs`.
   The previously derived checking/resolution cases therefore supply `.value(.integer(n))`, `.int`, empty children and the retained target ID.
   These are the literal row and target/prefix facts consumed by `LiteralIntInitializerEvaluators` and its complete-initialization parent.

The source-use premise removed here is that this registered shared declaration somehow produces the required literal at the required root.
General source binding and faithful SwiftSyntax interpretation are still owned; this argument does not establish their universal correctness.
The existing `AlgorithmBuilderParsingTests.parsedAndBuiltLiteralInitializersShareIdentity` now reuses its independent value table through both direct and registered-Algorithm placements.
It checks actual successful initial outcomes and the value at `x`'s formal projection, rather than merely comparing two compiler identities.
The first executed diagnostic failed during compilation, before the registered variant's initial outcomes were evaluated.
The lowerer treated zero processes and zero procedures as requiring a program counter, although the sequential-step case is dispatched separately.
That manufactured an empty control field and an always-enabled `Terminating` action for declaration-only source.
The existing normalization check rejected its frame. No literal-value mismatch or successful kernel execution was established.
The repair makes the zero-process decision depend on the presence of procedures; all nonempty-process decisions and sequential lowering remain unchanged.
The owner also requires that declaration-only source has exactly its one state variable and no actions.
This is a source/control boundary repair, not a relaxation of the normalizer or an accepted-language restriction.
The guarded repair passed 167 tests in the four existing builder/parser, renderer and sequential-control suites.
The literal owner exercised all eighteen independent values in both placements, requiring one state variable, no actions, one initial state, no failures and the expected projected value.
All 1,201 captured inputs were unchanged during execution. The complete 106806-byte log has SHA256 `61c154cfe891b33d60e4d4191fc067f009bdaef6c8b169fdb29818d6e5c5e6ec`.
This is regression evidence, separate from the code-case proof and hosted mathematical checking.

### Inferred scalar source types and native type binding

For the pilot's unannotated scoped shared integer initializer, suppose decoding returns a proper integer literal with payload `n`
and parsing/compilation return normally. The parser supplies the `.int` input premise of the preceding transport argument,
including a model that declares its own `Int`.
The registered-Algorithm source-use argument above discharges the decoding premise for its stated syntax route.

The owners are [source inference](../../Sources/SwiftTLAPlugin/SpecParser+SpecBuilder.swift),
[scoped declarations](../../Sources/SwiftTLAPlugin/SpecParser+Algorithm.swift),
[source types](../../Sources/SwiftTLAPlugin/SourceTypes.swift), [the macro entry point](../../Sources/SwiftTLAPlugin/ModelMacro.swift),
[algorithm lowering](../../Sources/SwiftTLA/AlgorithmLowering.swift), [layout](../../Sources/SwiftTLA/CompiledLayout.swift)
and [type inputs](../../Sources/SwiftTLA/CompiledTypeInputs.swift).

1. `initialValueTypeName` recognizes the literal and normalizes `Swift.Int` with resolved type `.int`.
   If the canonical short name resolves to `.int`, normalization uses it. Otherwise it retains the qualified spelling.
   The corresponding Boolean and string branches use their own primitive types. Authored nominal type names are unchanged.
2. `parseAlgorithmVariableDeclaration` resolves that spelling and normalizes the state metadata with the same resolver.
   An unoccupied canonical name resolves to `.int`; an occupied name retains the explicit `.int` witness.
   These type operations leave the integer payload and initialization expression unchanged.
3. `AlgorithmLowerer` copies the spelling and resolved witness into `NamedVar`.
   `CompiledLayout` copies both into the variable at its ordinal ID.
   `CompiledTypeInputs` prefers the explicit witness; otherwise it resolves the retained spelling.
   `TLASpecVerifier` uses the parser's resolver for that input construction. Both branches therefore give `variableTypes[v] == .int`.
4. The earlier lowerer and resolver results now yield a resolved proper literal `n` with no children for this source route.
   This discharges the input primitive-type premise for the scalar evaluator and `IntExpressionOutcomesSupplyInitializerOutcomes`.
   Source declaration selection, other annotated/lexical placements and complete histories remain separate.
   The runtime ID-target/prior-domain facts are derived in the target/prefix argument below; printed-name projection remains separate.

Native scalar annotations now use `SwiftTLA.TLAValue.IntegerLiteralType`, `BooleanLiteralType` and `StringLiteralType`.
The library's existing public literal conformances bind these associated types to standard `Int`, `Bool` and `String`.
Under that library namespace binding, documented Swift associated-type identity makes those annotations independent of model declarations
named `Int`, `Bool`, `String` or `Swift`. The emitter's `.named` branch retains the authored nominal type.
Primitive state fields, control raw values, arithmetic temporaries, predicates and validation signatures use the fixed bindings.
The independent output checks require their complete token sequences; they do not accept arbitrary type spellings.
This removes the unoccupied scalar-name premise for those emitted annotations. General helper/module namespace binding remains owned.

The current support-name probe extends the existing occupied-name model with aliases
for `InitialEvaluationOutcomes`, `InitialEvaluationFailure`, `TLAStateProjection`
and `TLAValue`. On unchanged `f329c36b` production, compilation binds the generated
outcome and projection signatures to those aliases and fails. No test executes;
this is a compiler binding failure, not a runtime rejection or proof receipt.
The working repair qualifies these four types through `SwiftTLA` in generated
initialization, projection, validation and export code. Existing independent
templates and corruption controls require the qualified spellings, including the
same exact callback/capture grammar. The occupied-name owner and external typed
client now pass on that producer. The combined run executes 158 tests: 157 pass
and one stored Swift witness comparison fails because its support names are
stale. After exactly seven witness qualifications, all 23 tests in that owner
pass. This is not a claimed passing rerun of all 158 tests. The alias baseline
and repaired execution are regression evidence. No accepted source form is
removed; library module binding and other helper/operator associations remain owned.

The source baseline executed the existing owner and reported three wrong nominal-domain resolutions.
The native baseline failed generated-code compilation before any test executed; it is not a runtime rejection receipt.
A source-only repair exposed a stack-guard SIGBUS in the existing recursive CASE type path.
That path now uses the existing explicit worklist: condition before value, prior value type forwarded to the next value,
optional otherwise last, then the same final operand contexts and original child occurrences.
It removes the recursive `inferCases` path without changing accepted expressions or stack/resource limits.

The source/checker repair first passed 196 tests in nine suites. The later native diagnostic executed 324 tests and failed on three
old-format atomic-copy expectations in two tests; the source, occupied-name machine, dictionary-key and external-client owners passed.
Only five test files changed afterward. Their follow-up passed 46 tests in five suites on the same production bytes.
Retained witnesses expand only unshadowed standard scalar identifier notation; actual output is not normalized.
The anchored initializer pattern retains every capture/append guard, and constructor negatives use a correct-output positive baseline.
All 1,201 captured inputs matched each run's own manifest. No complete rerun of the 324-test filter is claimed.

This is a manual code-case argument under documented Swift semantics, not a new TLAPS result or a mechanically checked compiler translation.
Complete literal, initialization, source/output/helper/checker/kernel and whole-language rows remain open.

### Native and mathematical TLA integer literal meaning

This result starts with the proper resolved `.value(.integer(n))` leaf derived above, at standard `.int` type.
The emitter and target use the same `Int` width. The mathematical source outcome is `Expressions!Success(n)`:
the literal reads no binding, performs no state write and reaches no model failure.
The result below derives the emitted value. Actual namespace/operator binding, parsing and checker execution retain their separate obligations.

The owners are [native emission](../../Sources/SwiftTLAPlugin/NativeSwiftEmitter.swift),
[native initial declarations](../../Sources/SwiftTLAPlugin/NativeSwiftEmitter+Machine.swift),
[formal value transport](../../Sources/SwiftTLA/CompiledValue.swift),
[formal expression emission](../../Sources/SwiftTLA/CompiledTLARenderer.swift),
[integer formatting](../../Sources/SwiftTLA/TLAValue.swift) and
[independent decimal grouping](../../Sources/SwiftTLA/StraightLineRenderedActionCheck.swift).
The arithmetic interface is documented Swift [decimal conversion](https://developer.apple.com/documentation/swift/string/init%28_%3Aradix%3Auppercase%3A%29)
and [signed remainder and unary negation](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/BasicOperators.md).

**Native leaf.** The initializer expression has no resolved function calls.
`expressionValues` starts empty. Its only entry writes are in `recursiveBody`'s
`.resume` branch, which saves the dictionary and restores it with `defer`, also
restoring it before emitting the next body. Every other branch preserves the
entry dictionary. Induction over completed emitter calls therefore preserves
the initially empty cache through earlier action/function emission, including
throwing exits. A pilot literal cannot be replaced by a cached name. This cache
fact does not require unrelated parts of the model to contain no functions.
`expression` reaches `expressionBody`, whose value branch calls `literal` with the stored value and `.int` type.
The union, finite and nominal branches cannot intercept `.int`.
For `n != Int.min`, the emitted text is the standard decimal representation of `n`.
A negative value in this branch has representable positive magnitude, so the corresponding standard unary-minus expression is defined and equals `n`.
For `Int.min`, the emitter instead uses the fixed primitive type's `.min` member; it does not form or negate an unrepresentable positive `Int`.
The preceding associated-type argument identifies that primitive type under the stated library namespace binding.
Neither leaf spelling invokes a model helper, reads state or adds a model failure.
The initial-declaration owner places it in the typed immutable binding for that variable; this value argument does not prove the surrounding state construction.

**TLA renderer.** `CompiledTLARenderer.state` begins with one expression task and no output parts.
The proper value branch appends `CompiledValue.rendered(using:).description` without scheduling a child or consulting state names.
For this value, transport returns `.int(n)`, and `TLAValue.description` calls `_integerForm(n)`.
Let `R = 1000000000`. The interpretation here uses mathematical integer numerals, multiplication, addition and subtraction.

1. For `-R <= n <= R`, formatting returns the signed decimal text of `n`.
   Its natural numeral has magnitude at most `R`, including zero. Under the stated mathematical interpretation it denotes `n`.
2. Otherwise set `q = n / R` and `r = n % R` using Swift's signed operations.
   Their contract gives `n = q * R + r`, `abs(r) < R`, and a nonzero remainder with the sign of `n`.
   Here that equation is mathematical; the formatter never evaluates `q * R` in host Swift.
   The actual divisor is positive and greater than one, so neither division-by-zero nor minimum-divided-by-minus-one applies.
   Both `q` and `r` are representable, and `abs(q) < abs(n)`.
3. Induction on the mathematical magnitude therefore terminates at the base case.
   If `r < 0`, the actual output is `(format(q) * R - magnitude(r))`, denoting `q * R + r = n`.
   Otherwise the actual plus branch denotes `q * R + r = n` too.
   In particular, a negative multiple of `R` uses `+ 0`, which has the same value as `- 0`.
   The formatter takes only the remainder's unsigned magnitude; it never computes signed `abs(Int.min)`.
4. Reverse those actual recursion steps. Let `negative` be `n < 0`, let `unsigned[0]` be the magnitude of the terminating quotient,
   and let each `chunks[i]` be the corresponding remainder magnitude. Each chunk is in `0..(R-1)`.
   The unsigned steps satisfy `UnsignedChunk`; the interpreted output steps satisfy `RenderedChunk`, including the zero-remainder equivalence.
   The base satisfies `SignedMagnitude`. These are the actual premises of
   [SignedLiteralComposition](SignedIntegerLiteralRule.tla), with final unsigned value equal to `n.magnitude`.
   Thus the existing theorem consumes the renderer's derived history; no arbitrary matching output history is assumed for this leaf.

**Independent checker.** `checkedIntegerLiteral` does not call `_integerForm`.
It starts from decimal `n.magnitude`, grouping the digits from the right in blocks of nine.
Each full nine-digit block parses to a value below `R`, so its conversion to `Int` is representable and its force unwrap is defined.
The first group normally has one through nine digits. There is exactly one additional stopping case:
when it has one digit and the decimal prefix is `1000000000`, the first two groups together equal `R`.
The renderer stops at that value, so the checker merges those groups into its ten-digit leading chunk.
Every other candidate leading ten-digit group is greater than `R`; groups starting with two or more digits cannot create this stopping case.
The remaining full nine-digit groups are precisely the successive quotient/remainder digits of the same magnitude.
The checker prefixes the sign once, then chooses minus for each nonzero negative chunk and plus otherwise.
Induction through those groups therefore yields the same canonical text and the same signed value as the renderer.
This derives the numerical/grouping assumption for this checker function; it does not establish the soundness of every output-check caller.

**Existing parent instance.** Set the expression bounds to the same target `Int` bounds and take `result = Expressions!Success(n)`.
Representability supplies `result` in `Expressions!ExpressionOutcomes`; neither source nor generated literal needs a child history or state read.
Under the existing `IntInitializationDomains`, `IntExpressionOutcomesSupplyInitializerOutcomes` gives equal initializer outcomes,
with candidate set `{n}` and `NoFailure`. For `prior` in `PartialBindings` and `target` in `IntKeys` outside `DOMAIN prior`,
`PartialBindingsHaveSourceTypes` supplies its typed domain, and `InitializerLeafRetainsCompleteStatesAndFailures` gives the same singleton extension
and empty failure set. No arbitrary source/generated evaluator-agreement premise is needed for this literal instance.
The runtime ID-target/prior-domain link is derived below. Printed-name projection, complete backend histories, control and checking remain open.

This is a manual implementation-correspondence argument for the stated value routes, using existing mathematical results.
It adds no theorem, evaluator, fixture or local proof execution. The value argument was reviewed against exact `3ee2c933` bytes.
Its formatter bodies are unchanged by the source-rewrite guard repair below.
The prior diagnostic's source/native owners and the corrected five-suite follow-up remain separate regression receipts; no tests were rerun for this argument.
TLA standard-module/operator interpretation and the actual checker kernels remain owned boundaries.
The tools' [standard Integers module](https://github.com/tlaplus/tlaplus/blob/master/tlatools/org.lamport.tlatools/src/tla2sany/StandardModules/Integers.tla)
explicitly delegates arithmetic to tool implementations; that reference is not a binding for the pinned binary.
Small numeral tokens do not prove that pinned TLC can evaluate a full-width `Int` expression or a selected check involving it.
L4, the complete six-link literal row and whole-language preservation remain open.

### Literal initializer targets, prefixes and composition

This step connects the existing literal result to state assembly; it does not infer a complete accepted-language proof from it.
The source route is the preceding unannotated scoped shared Int initializer after its decoded payload has been established.
Raw syntax provenance, other placements and actual generated-language interpretation retain their stated obligations.

**Before.** The literal parent instance above still assumed that the reached target was outside the prior domain.
It also left the association between the resolved literal, its variable ID and its reached prior map unspecified.
Those facts can be derived for the compiled runtime rather than supplied as a new agreement premise.

**Actual key order.** Let `order[j]` be the variable ID at zero-based offset `j` of the resolved `behavior.initializations`.
Use ordinal IDs as mathematical keys; no printed-name conversion is needed for this argument.
`CompiledLayout` constructs distinct IDs by enumerating its variable array.
The lowerer's `orderedInitializations` starts with exactly that ID set, appends only a remaining ID and then removes it.
Every normal return therefore lists every layout ID exactly once.
Checking appends each initializer with its original ID, and both finishing passes retain that ID and array order.
`CompiledBehavior.map` also retains the ID and order while mapping the initializer expression.
Finally, `ProgramResolver.resolve` calls `validateInitializationDependencies` before returning the resolved program.
Its first pass rejects repeated targets; its final set equality rejects any omitted layout ID.
Thus a normally returned resolved program supplies `InitializationOrder(count, order)` with mathematical index `j + 1`.
This is a code-case argument using documented Swift arrays, sets, enum matching and value copying, not a checked Swift translation.

**Reached prior domain.** In `CompiledRuntime.initialOutcomes`, every pending pair `(j, values)` has
`DOMAIN values = {order[0], ..., order[j - 1]}`. Prove this by induction over pending insertions:

1. The only seed is `(0, [:])`, with empty domain.
2. The value case copies `values`, writes only `order[j]`, and inserts only `(j + 1, copy)`.
   If expression evaluation throws, that insertion is not reached. It cannot create a successful partial binding.
3. Each member-of alternative likewise copies the prior map, writes only that target, and inserts the next index.
   An empty domain inserts no successor. A failing branch records a failure without inserting a partial successor.
4. Popping an existing pair preserves its invariant. Neither the final-state branch nor the failure callback inserts another pair.

Distinct order IDs now give target freshness at every reached initializer, including one following branching initialization.
This derives the ID-domain invariant; general value typing and source/generated branch agreement remain separate.
It also proves that the literal's immutable `values` input is precisely the reached prefix, rather than a later reassignment.

**Literal extension.** For the proper resolved `.value(.integer(n))` with no children, the previously derived type/payload result applies.
`CompiledEvaluator.evaluate` returns the stored value immediately. It does not inspect any variable or call a model helper.
The runtime therefore inserts exactly one successor, whose mathematical value projection is
`GeneratedExtension(prior, target, n)`. Every old key/value remains unchanged, and only the fresh target is added.
No model failure callback is invoked by this literal evaluation. Prior failures remain in the existing failure array.
This supplies the fixed candidate `{n}` and `NoFailure` row for every reached prefix without an evaluator-equality hypothesis.
The native emitter's immutable literal binding and the TLA renderer's ID-indexed equality use the same resolved entry.
Their numerical leaf argument is above; lexical scope, projection, library binding and actual TLA/kernel interpretation remain owned.

**Consumer.** `LiteralIntInitializerEvaluators` in [OrderedIntInitializationComposition](OrderedIntInitializationComposition.tla)
constructs those literal rows explicitly for source and generated evaluation.
`LiteralIntInitializersComposeCompleteStatesAndFailures` calls the existing `IntExpressionOutcomesSupplyInitializerOutcomes`
for their typed agreement, then supplies that derived fact to `InitializationHistoriesRetainAllStatesAndFailures`
and the typed-prefix/terminal-selection constituents of `CompleteInitialStatesAndFailureEventsCompose`.
Its agreement premise ranges only over nonliteral positions. No expression plan, supplied matching literal history,
or arbitrary literal evaluator-agreement premise remains in that parent instance.
The result includes existence of both histories, equality of every prefix, accumulated failure sets and selected terminal states.
It covers arbitrary finite counts, including zero, and arbitrary sets of literal positions.
Other constructors and selected checks still require their own correspondence; failure sets do not establish ordered failure-event histories.

The published `dbd268d9` pinned execution failed one of 242 obligations in this module, at the final quantified parent invocation.
The literal outcome, typing and child-agreement steps preceding that failed invocation passed.
The published `11e39453` pinned execution proved prefix equality but left one of 251 obligations unproved at the selected-terminal equality/typing invocation (line 126).
The second body refinement exposes the terminal prefix type, selected-check agreement and same-prefix terminal equality separately, then uses the checked prefix equality.
Its statement, premises, earlier proof steps and every pre-existing theorem remain unchanged.
The published `b33d8979` pinned Linux execution proved all 277 module obligations, including this complete literal instance.
Its retained module SHA256 is `1b0012122ce1bb163b91fac420db47f9649ea4123f074b8fea17376c175ab324`.
Run `42415865783`, job `128533696399` and artifact `13592907798` bind the successful result to the actual source snapshots and runners.
The small artifact SHA256 is `3f57a9345c872b0a9cc0132431589c773ee822f11996f7982b615d13697b7fc7`; all entries passed integrity checks.
The actual tool-cache identity, versions and binary-hash receipts are retained. This is not a cold build or binary reproduction.
The implementation connection is a manual code-case argument.
Neither this argument nor a later TLAPS pass establishes parser, emitted-language, checker-kernel or whole-language soundness.

### Emitted literal initializer row and typed relation consumer

This argument starts with the proper resolved literal supplied above: target ID `v`, payload `n`, result type `.int` and no children.
Use the parameter-free, call-free route and the public unselected `initialOutcomes` call, with no selected initial invariant.
The source target is fresh in the reached prefix by the runtime target/prefix argument.
Other accepted configurations, calls, selections and initializer constructors remain separate obligations.
The numerical leaf argument is reused; this step derives its surrounding binding, state assembly and logical initial constraint.

The method is a code-case proof using documented Swift value, binding, closure, array and dictionary semantics.
Faithful SwiftSyntax construction/printing, the stated library/type bindings and TLA syntax/operator interpretation remain explicit owned conditions.
It does not assume that the emitted initializer agrees with the source evaluator.

**Native target and value.** Project a reached lexical prefix by reading the actual slot for each initialized ID.
Project a completed Snapshot by reading the actual generated field route at that same ID.
Both are proof relations on existing values, not new runtime observers or definitions through the initializer evaluator.
The owners are [the emitter name table](../../Sources/SwiftTLAPlugin/NativeSwiftEmitter.swift),
[API field selection](../../Sources/SwiftTLAPlugin/GeneratedMachineAPI.swift),
[state/initializer emission](../../Sources/SwiftTLAPlugin/NativeSwiftEmitter+Machine.swift) and
[the formal projection](../../Sources/SwiftTLAPlugin/NativeSwiftEmitter+Projection.swift).

1. `variableNames` enumerates the complete layout and stores `_value_<sanitized source name>_<ordinal>` under each retained ID.
   The decimal ordinal is the suffix after the final underscore. Equal slot strings therefore imply equal ordinals and equal IDs.
   Sanitizing two source names to the same text cannot merge their slots. This derives slot separation for this parameter-free route.
   It does not prove general collision freedom against parameters, callbacks or arbitrary surrounding declarations.
2. `initialStateSource`, called by `initialDeclarations`, enumerates the actual initializer array and selects both type and slot with that entry's ID.
   Its value case emits `let slot: nativeIntType = literal(n)` and resets the evaluating-site marker afterward.
   The existing numerical argument supplies exactly `n`, including the primitive `.min` spelling at the lower bound.
   The immutable binding extends the lexical prefix once and leaves every preceding binding unchanged.
3. For a visible field, its enclosing selection condition starts with `_selectedInitial == nil`.
   The public `initialOutcomes` call supplies no selected state, so that condition is true by documented Swift short-circuiting.
   It cannot filter this candidate or evaluate the second field-comparison operand.
4. `executionState` supplies each public constructor argument from the slot at that public field's ID.
   `GeneratedMachineAPI.variables` filters source-origin layout entries and retains their IDs and order.
   The generated `State` initializer takes `_value<ordinal>` parameters and assigns each one to the same ID's field.
   Hidden Snapshot fields use their layout ID's slot directly. Thus neither public nor hidden state assembly retargets the literal.
5. The lexical-prefix projection now has `v |-> n`, with every prior ID/value unchanged: exactly `GeneratedExtension(prior, v, n)`.
   The constructor's pointwise copies make the completed Snapshot projection agree with that final lexical projection.
   `formalProjectionDeclarations` uses the same layout ID's field route and formal name; its `.int` case emits `TLAValue.int(value)`.
   This supplies integer value transport at that projection entry. General formal-name namespace interpretation and projection soundness remain owned.
6. `visitInitialBranch` invokes its `visit` closure once inside `do`. A normally returning literal binding reaches no catch or failure callback.
   A wholly literal initializer sequence reaches the single Snapshot append, with no model failure and no branch enumeration.
   `initialOutcomes` maps each Snapshot through the private initializer that copies it into `_execution`; it forwards the same failure array.
   For mixed sequences this proves only the reached literal child step; branch enumeration, other failures and selected checks keep their own premises.

**TLA leaf constraint.** Let the TLA valuation's field for `v` be `layout.variables[v.ordinal].formalName` under the retained ID/name projection.
In [the actual module emitter](../../Sources/SwiftTLA/SpecCompilation.swift), the initializer dictionary is keyed by ID.
The layout loop retrieves that ID's initializer and forms `field = renderer.state(expression)`.
The numerical argument gives the mathematical value `n` on the right.
The literal has no fallible sites or children: `orderedFallibleSites` rejects its empty site list, `choiceDefined` finds no choice,
and `arithmeticSites` finds no arithmetic operation. `evaluationDefined` therefore returns `nil` and no definedness wrapper changes this equality.
The same absence of sites gives no `expressionEvaluationFailures` record for this literal.

When present for this field's metadata, the emitted Int state predicate is `IF small(field) THEN TRUE ELSE field in targetBounds`.
At `field = n`, this predicate is true: either `small(n)` is true, or the remaining branch holds by `n`'s representability.
This argument needs only the literal candidate, not a claim that the fast bound test is sound for every possible value of every constructor.
If that metadata emits no additional type predicate, the equality still has the same fixed candidate; general declared-type guard coverage is not established here.
Consequently, for any fixed typed prior and fresh target, the literal equality plus its type predicate allows exactly the extension with `v |-> n`.
It contributes no initial failure. This derives the same `{n}`/`NoFailure` child row as the native binding.

**Verified mathematical consumer.** Take `allowed[v] = SwiftIntMin..SwiftIntMax` and both literal child rows from these derived candidates.
`FixedInitializerRetainsItsOnlyCandidate` and `InitializerLeafRetainsCompleteStatesAndFailures` identify that row and its fresh extension.
`TypedInitializerOutcome` retains `{n}` because `n` is in `allowed[v]`; its failure component is still `NoFailure`.
Thus the literal position supplies the typed child-equality premise of `TypedInitialRelationsRetainAllStatesAndFailureEvents`,
whose `SourceTypedConstraintPrefix` conjunct is precisely membership in the allowed type and in that child's candidates.
The real `Init` emitter joins its per-variable predicates and type predicates by conjunction, independently of their printing order.
The existing typed-relation theorem consumes the derived literal row when other positions supply their own correspondence.
Its pinned `dbd268d9` proof receipt and unchanged current module are retained separately from the new literal-composition theorem's failed final invocation.
This typed parent does not fill that failed invocation or discharge the other constructors' premises.

The removed assumption is opaque native/TLA literal-initializer agreement: the actual binding/assembly and logical predicate now derive the row.
The result is conditional on the named syntax, namespace, library and TLA interpretation boundaries; no complete six-link row is closed.
Current full-width TLC execution, selected checking, generic output-checker soundness, complete mixed initializer event histories and whole-language preservation remain open.
No new evaluator, observer, renderer oracle, theorem, fixture or test execution is introduced by this argument.

### Root-state read initializer child

Take the scoped source route with an already declared Int shared handle `r` and a distinct target declared with `scope.sharedVar(initial: r)`.
Use the parameter-free, call-free, nonprojecting root-state route; the source/type/bounds and syntax interpretation conditions remain those above.
The independent read meaning is `Success(prior[r])` when that Int binding is available. It reads exactly `r`, writes no expression state and reaches no model failure.
The initializer, separately, binds its fresh target to that result.
The prior Int value/type is an environment premise supplied by preceding initializer child rules, not an assumed read-evaluator result.

**Source and ID.** The Algorithm parser extends `TypedFacadeScope` after the preceding shared declaration with `.variable(state.root)` and that declaration's shape.
Its `value(for:)` and `shape(for:)` use the last matching source binding.
For this unshadowed shared handle, `decodeTypedFacadeValue` therefore returns the actual shared root reference; it does not decode a parameter or constant.
`typedFacadeValueType` supplies its Int shape to the target's initializer metadata, and `normalizedStateType` retains the primitive type spelling or explicit witness.
This supplies the same `.int` type input used by the earlier literal/type transport argument.

The lowerer's `.variable` case calls `value(named:scope:at:)`.
With no parameter or local binder in this route, its binder branch does not intercept the name.
Its layout lookup finds the unique declaration and produces `.stateVariable(rID)` before considering constants or operators.
Layout ownership and unique declaration names follow from the same-source construction and normal-return uniqueness guard already used above.
Thus the source read root supplies the actual ID; agreement of an arbitrary name map is not a new premise.

**Typed resolution.** Checking the read against `.int` sees the referenced variable's persistent `.int` type.
`canProjectRead(.int, to: .int)` returns true directly, and the checked type and computation type are both `.int` with no children.
No conversion or projection wrapper is needed. The finishing pass retains that expression and target ID.
At the resolver root, function context and captures are empty. Its expanded task copies the state-variable operation, ID, type and empty children.
The occurrence-identity invariant ensures a cache hit for that immutable site has those same fields.
The cache stores the read expression, not its value in any particular initial state; it cannot freeze the first branch's read value.

**Available reached binding.** For the proper read leaf, `initializationReadEffect` has no child effects and inserts exactly `rID` into `effect.variables`.
The mandatory resolved-program dependency validation requires that set to be a subset of the structurally initialized IDs before the target is inserted.
The runtime prefix-domain induction above identifies those IDs with every reached pending pair's actual value-map domain.
Consequently `rID` is present on every successful prefix reaching this read, including prefixes produced by different domain alternatives.
The missing-variable branch is excluded by this derived invariant; it is not silently ignored or reclassified as a successful model outcome.

**Actual value and outputs.** `CompiledRuntime` constructs the evaluator from that pending pair's immutable `values`.
The evaluator's state-variable operation calls `variableValue(rID)`, which returns precisely that dictionary entry.
For prior Int payload `m`, the actual result is therefore `.integer(m)` with no read-specific model failure.
The target value case copies the prior map and updates only the fresh target, as in the literal argument.

The native initializer emits the same ID's slot: `initialStateSource` calls expression emission with an empty state prefix,
and the state-variable branch calls `stateValue(rID, prefix: "")`, which selects `variable(rID)`.
The previously derived slot/constructor/projection relation supplies `m` at that slot in each reached lexical prefix.
No resolved function emission populates the native expression-value cache in this route.
The read thus copies the current branch's value, and the existing initializer assembly retains it at the target ID.

The actual TLA state-variable branch selects `stateNames[rID]` or the same layout ID's formal name.
The ordinary `Init` call supplies no name override, so the emitted condition is `targetName = readName`.
No choice, child or arithmetic site is present, giving no definedness wrapper or read failure record.
For a fixed available prior with value `m` at `rID`, this equality has exactly candidate `{m}` at the fresh target.
The optional Int bound predicate holds at `m` by the environment's target-Int typing, just as for the literal candidate.
Under the stated name and TLA interpretation conditions this derives the same native and TLA child row, rather than assuming their agreement.

**Parent use.** The read has a concrete one-node instance of the checked `ExpressionNodeRule`, rather than an assumed pair of matching evaluator histories.
Take `count = 1`, `kinds[1] = "read"`, `reads[1] = rID`, unused `literals[1] = 0`, and unused `left[1] = right[1] = 0`.
Project the prior onto its available Int keys `bound`, obtaining `bindings` with `rID` in `bound` and `bindings[rID] = m`.
`CompletingPartialBindingsRetainsEveryBoundValue` supplies the total state `CompleteIntBindings(bound, bindings)`, retaining `m` at `rID`.
These choices satisfy `ExpressionPlan`: the integer-domain assumptions put zero in range, and the read kind imposes no child-index constraint.
Choose both zero-prefix histories to map index zero to `Success(0)`; their required equality and range facts follow directly.
At index one the read branch supplies `Success(m)` without consulting either history or an unused child.
`FixedInitializerRetainsItsOnlyCandidate` and `InitializerLeafRetainsCompleteStatesAndFailures` then give its fixed typed initializer row and exact fresh extension.
That row supplies the read position of the existing checked `TypedInitialRelationsRetainAllStatesAndFailureEvents`.
Other initializer children still supply their own premises; no complete read/capture family or whole-program theorem follows.

The existing initialization module now contains the checked formal instance
`ReadyReadInitializersComposeCompleteStatesAndFailures` for arbitrary finite schedules and read positions.
Its evaluator rows use `SourceFixed(prior[key])` and the independently filtered `GeneratedFixed(prior[key])`.
The earlier-key premise and the exact prefix domain supply availability; the prior's type supplies membership in `Values`.
Thus read agreement is derived rather than supplied, before applying the existing complete-history and selected-terminal rules.
Off-prefix fallback entries only make the evaluator tables total; readiness must exclude them from every scheduled prefix.
Non-read children and selected checks still supply agreement.
The exact `a9815a06` module passed all 368 obligations in the pinned Linux run at `3c3cd1ab`.
Its complete source, proof log and tool receipts are retained under
`.git/swifttla-proof-evidence/ready-read-initialization-composition-2026-11-08/hosted-3c3cd1/` in the primary checkout.
This checks the constructed formal instance and its parent use; it does not mechanize the source-to-ID argument
and retains the existing set-valued observation limit.

The existing parser/value owner now checks a dependent copied state through both source placements.
Its domain-dependency sibling checks complete `(limit, choice)` pairs across different limits, rather than only the projection onto choice.
The focused parser suite passed all 63 tests, including typed-program execution of the copied values and all three correlated branch pairs.
The literal-only compilation-identity check remains at its original boundary: a copied array may retain an explicit resolved-type witness where the runtime builder retains its Swift spelling, and those metadata representations contribute differently to identity.
Those parser tests are regression evidence for the manual code-case argument.
The pinned result above separately checks the formal read instance; it does not mechanize that code-case argument.
Captured parameters, local/procedure/process reads, arbitrary shadowing, all source placements, syntax/library/name/projection interpretation,
checker kernels and complete mixed failure histories remain open. E READ and all six-link rows remain open.

### Checked-addition initializer child

Take the same available typed Int prefix and a formal addition whose two children are literal/read/add expressions.
Closed raw Swift arithmetic that the parser folds belongs to the literal case instead.
Use the established child contracts for their actual results or first reached failures, with no expression writes, calls or captures.
These are compositional child hypotheses; agreement of the parent evaluators is not a premise.
Syntax, overload selection, name/type interpretation and output-helper binding retain their named open conditions.

The lowerer's `.add(lhs, rhs)` calls `scheduleBinary`, preserving left/right positions.
Its common scheduler pushes the build continuation, then children in reverse onto a LIFO stack; successful child results are taken from the suffix in their original order.
The Int type-checking case gives both children Int operand contexts and an Int result.
For this route, resolution retains the operation, ordered children and Int types, as enforced by the existing source/resolved initializer checks.
The full visitor-to-`ExpressionPlan` correspondence remains a separate obligation; this node case does not assume it has been proved.

**Actual evaluation.** `.add.evaluatesRightOperandFirst` is false.
The compiled evaluator schedules its finish task below the reversed operands, so the left child completes before the right child and the parent operation.
Any throw leaves that evaluation before a later task executes.
At finish, `.add.apply` removes the right result and then the left result, and calls `_NativeMachineOperations.add(lhs, rhs)` in that order.
`nativeOperation` translates its overflow to the formal evaluator error without changing operation or operands.
The native arithmetic emitter uses the same left-first order to produce sequential throwing `let` bindings, followed by the parent helper call.
For this call-free initializer route the expression cache supplies no branch-specific precomputed value.
A throwing child exits the emitted closure before its following bindings and parent operation run.

The helper calls `lhs.addingReportingOverflow(rhs)` and returns its partial value only when the overflow flag is false.
Otherwise `checked` throws exactly `integerOverflow(.addition, operands: [lhs, rhs])`.
Under documented target Swift Int semantics this is the bounded-integer `SourceAdd` result, including signed underflow; no wrapped value is admitted as a success.
Together with the child contracts, both actual evaluation paths therefore have three cases:
left failure is propagated without evaluating right; successful left followed by right failure propagates that failure; two successes call checked addition once.
For the first case the mathematical unused second outcome may be `Success(0)`; no executed right-child history is required.
The checked `CombinedAdditionRule` consumes these child range facts and proves the same result as `GeneratedCombine`.

**TLA expression row.** Pure literal/read/add trees take the `arithmeticSites` fallback:
`orderedFallibleSites` returns nil because this fragment has no special failure,
choice or lazy branch. The fallback visits children in stored order, appending
each addition after its children. It therefore lists left sites, right sites,
then the parent addition site. `expressionEvaluationFailures` passes preceding
site guards to `preceded`; `arithmeticDefined` uses that same list for definedness.
The parent site carries `<<lhs, rhs>>` and the small-operands/exact signed bound guard of `GeneratedAddDefined`.
`GeneratedAddGuardMatchesSource` proves that guard equivalent to representability for the two in-range child values.
Earlier-site guards gate later failures, preserving the first reached expression failure under the stated TLA name/operator interpretation conditions.
This supplies the expression result/guard/payload row. Complete TLA initializer branch events and their before-prefix correspondence are still open.

For a successful result, the existing fixed initializer rule supplies the single fresh typed extension.
For a failed result, the existing failed initializer and leaf rules supply no state and the reached failure at the unchanged prior prefix.
The actual compiled/native initial recovery and immutable prefix argument supplies that prefix; the expression introduces no extra event or write.
This node case can be used recursively with the literal/read children, while all syntax/visitor/output interpretation and complete-program obligations remain explicit.

The existing parser-context owner checks eight independently specified rows at direct and registered-Algorithm placements through actual typed compilation.
It checks successful values, operand order, underflow, left-before-right nested failure precedence, exact failure count/site and the full before-prefix.
All 63 tests in the focused parser suite passed. These executions are regression evidence, not a new mathematical proof or hosted admission result.

### Source rewrite token classification

`SpecExpressionMacro.expansion` calls `OrderedIntSourceSyntaxCheck.verifyRewrite` after the existing identity rewriter and before builder-witness emission.
For its recognized registered Algorithm/scoped-state/ordered-Do route, the check removes only the permitted added identity arguments,
then compares the statement, scoped body, outer call and registration tokens.
The private shared comparison previously retained text alone.

The existing rewrite owner executed a valid signed source and its correct identity-expanded output first.
It then changed the single `initial: -1` occurrence to `initial: - 1`.
The changed-input, parser-recovery, equal-token-text and unequal-token-kind requirements all passed.
On unchanged `3ee2c933` production, the guard accepted that output: one executed test reported one expected-rejection issue.
This is a measured guard failure, not a successfully compiled wrong program or a runtime mismatch.

The two-line repair compares `TokenKind` arrays through the same private helper at all four sites.
In the pinned SwiftSyntax dependency, identifier, literal and operator spellings are associated values of that enum;
fixed punctuation and keyword cases retain their distinct kinds. Equality therefore retains spelling and operator classification.
The measured prefix-to-binary-minus change now fails the existing guard. Trivia remains outside this token contract.
The repair introduces no alternate parser, checker, accepted source form or output normalization.

The guarded follow-up passed 156 tests across six existing suites, including the correct signed rewrite, the rejected corruption,
domain/identity/order controls, parser/type owners and generated initialization output checks.
All 1,201 captured inputs stayed exact. Its whole log is 114,323 bytes,
SHA256 `54f806ee9545c31840e6246127a6407de624554c78b69b32c2b74c78c5299aa0`.
The retained input and dependency receipts bind the actual enum source and current implementation inputs.
This repairs the lexical-classification premise for the recognized rewrite path; full parser recovery, AST/scope/binding interpretation,
unrecognized accepted routes and complete source-to-output correspondence remain open.

### Grouped closed integer source values

The existing independent source collector handled a minus directly on an integer token, but skipped minus on a grouped closed value.
That made all three callers skip their witness for an otherwise recognized algorithm: parsed-model verification,
identity-rewrite verification and the real runtime builder comparison.
The unchanged-production baseline at `14e956e8` passed the existing correct-builder owner with `-(-(1 + 2))` and its independently expected value three.
The existing corrupt-builder owner then accepted `-(-0x1)` after its producer replaced the authored value one with two.
Two executed tests reported one intended rejection issue. This is missed guard coverage, not an observed default-builder runtime mismatch.

The seven-line repair recurses through the existing collector on the strict prefix operand and requires an already closed Int value.
Checked subtraction from zero supplies its negation. An overflow returns no witness; it does not certify a value or invent a model-failure event.
The earlier signed-token case still handles the minimum integer directly.
The change reaches the three existing callers through their shared collector, with no alternate parser, evaluator or checker family.
Nonconstant prefix expressions, lexical/operator binding and general accepted-route coverage remain open.

The guarded follow-up passed 156 tests across six existing suites after a 1299.74-second build.
All 1,201 captured inputs stayed exact. The whole log is 114,323 bytes,
SHA256 `1afb1bff87b4b8e8dda06e0a377314b7c3ee124f50d3ebf69d39051291f65e25`.
The existing positive checks retain fixed runtime state expectations and source-parser agreement, followed by native and TLA output generation.
This restores the missing recognition case used by the source-to-initializer checks.
It does not discharge their general source correspondence, complete failure-history or parent-composition premises.
No new formal proof, hosted admission or complete six-link row follows from these receipts.

### Closed integer unary plus

The existing raw Swift integer route accepts unary plus as an identity operation on a closed Int operand.
On unchanged `4e7b1a5f` production, the real builder produced the independently expected value three for
`+(-(-(1 + 2)))`, but source decoding rejected it. The independent collector also skipped `+(-(-0x1))`,
allowing the existing intentionally changed builder to replace authored one with two.
The executed two-test baseline reported both failures; neither was a setup or compilation failure.

The existing decoder now admits plus only through its closed Swift integer syntax guard.
The shared source collector returns the already established closed Int operand unchanged.
It still uses checked subtraction for minus and supplies no witness for unsupported or overflowing operands.
These branches reach the existing parser, rewrite and real-builder consumers without a new evaluator or accepted-language restriction.
Nonconstant and nominal operator binding, other placements, parser fidelity and complete source correspondence remain open.

The final guarded combined run passed 210 tests in 13 suites, including the external consumer owner.
All 1,201 captured inputs stayed exact; whole-log SHA256 is
`b8decb1acccfd249dec3cb0cb830138a9f4b427d2800e5f3f52b59d7d085e09c`.
The later native-guard-only run changed no producer or previously selected owner bytes.
These are scoped regression receipts, not a complete E LIT row, initialization proof or hosted admission.

## Ordered observation contract

The existing set results omit order and multiplicity.
`InitialObservation` now records finite state and failure histories, each with its count.
`InitialSetProjection` supplies the earlier state and failure sets. `InitialFirstFailure` supplies the earlier first-record view.
The history carrier permits repeated events. It does not assume that a particular compiler route produces repetitions.
Two negative obligations distinguish a dropped repeated occurrence and a swap of later events from equal set/first projections.
The new indexed-append obligations connect an independent extension postcondition to the existing `HistoryAppend` construction.
The first pinned hosted run at `4612a657` left one reordered-history obligation unproved, at line 96 of 720 module obligations.
Its proof body now separates finite indices, event positions, set projections, typing and the unequal second entries.
The statement and premises are unchanged. The pinned Linux proof job at `905a224d` discharged all 750 module obligations.
Its retained snapshot SHA256 is `82ba7762fced358533e7a09e383620d0a7ce8af81610bd5b3e9fc0feb1d081d7`, matching the current module bytes.
This establishes the logical history obligations, including the repaired reorder case. Actual compiler/event correspondence and current admission remain open.

This contract describes finite returned observations, including their prefix forms.
Complete state domains, source traversal order, error classification, event projections and generated TLA observations remain separate obligations.
Infinite logical domains remain accepted. A capability error does not establish a completed initial observation.

The shared branch handler now propagates native collection count limits through both error channels.
This distinguishes representational limits from completed model failures without changing collection bounds.
It also propagates call-depth and missing-context errors. Logical recursive-domain errors use the existing function-domain model-failure channel.
The focused routing run passed 87 tests across twelve existing suites, including both error channels and valid recursion/context controls.
Sampling, action/checking kernels and general classification correspondence remain open.

## Current implementation links

The whole native initial-function check now includes parameter-free assumption-only models with no variables.
Their initial relation contains one empty binding. An empty state list would lose that binding.
The existing output owner exercises the accepted source variant and checks its actual compiled outcome and generated function.
With unchanged production, removing the function's only state append was accepted and reported one test issue.
The repair removes the check's nonempty-variable guard. Correct generation is unchanged.
The guarded repair run passed all 56 tests in six existing suites on 1,201 unchanged captured inputs.

The local zero-initializer argument uses documented Swift control flow, arrays and the generated zero-field State/Snapshot constructors.
Its entry has no parameters, variables, initializers or selected initial invariant.

1. `CompiledRuntime.initialOutcomes` starts with the single pending item `(0, [:])`.
   Its first pop takes the terminal branch because the initializer count is zero.
   Mapping the empty layout produces an empty value array. `CompiledState` validates the equal zero counts and retains the runtime identity.
   The branch appends that state once and returns without adding pending work.
   No evaluator or invariant runs. The recovery callback is not invoked, and the failure array stays empty.
2. The emitted initial function declares empty state/failure arrays and executes one outer recovery call.
   Its body appends exactly one `Snapshot(state: State())`. No binding, membership loop or selected-state filter precedes that append.
   The reviewed handler returns normally without a callback. The function returns one state and no failure events.
   The complete template check now covers this declaration instead of returning early.
3. Projecting the empty value array or generated zero-field state yields the empty binding.
   Thus the local histories have one empty state and zero failures, with the empty first-failure view.
   Their set projection is exactly `InitialSeed`, the existing `InitializationHistory` entry at index zero.

This removes the concrete worklist/append premise for that local base case without assuming a matching child evaluator.
It does not prove general source parsing, token and symbol interpretation, selected filtering, TLA initialization or checking kernels.
Those links remain open. No new formal theorem or pinned proof execution is claimed by this manual code-case argument.

`StraightLineAssignmentCheck` compares supported Int initializers with actual lowering and resolution.
It checks initializer kind, constructor, ordered children, literals, state identities and existing binder identities.
`ProgramResolver` retains source types before resolution, keeping nominal values distinct from raw integer encodings.

`OrderedIntSourceSyntaxCheck` compares supported parsed source, macro rewrite and actual runtime builder output.
Its domain forms include literal Int ranges and conditional sets with symbolic leaf equality.
Literal/read members and supported checked additions retain their operand and member order.
Every recognized addition subtree must contain an already-bound formal Int read.
The recognizer now evaluates successful literal-only integer arithmetic with Swift precedence and left associativity.
It uses independent checked standard-library operations for the raw value.
Symbolic additions retain their ordered children and existing identity checks.
Integer bound members remain outside this lexical witness; their parser decoding uses scope and type metadata.
The existing scoped-name helper supplies that distinction; its bytes enter the ordinary proof receipt.
The independent signed-radix decoder remains separate from the parser's literal-type inference.
Other source forms remain outside this witness, including non-assignment `Do` controls.
Full Swift declaration and overload resolution, aliases, factories and extraction are not proved by this lexical recognizer.

The existing `verifyIntInitialOutput` checks supported total and fallible Int domains as complete generated functions.
It constructs independent candidate values, selected membership, ascending loops, branch wrappers, initializer ordinals and complete-state assembly.
Arithmetic members use the existing independent checked-Int walker.
Membership helper names are captured only after namespace and uniqueness checks; their bodies, calls and scopes must match.
The scalar Int and control checks remain mandatory for their supported forms.

The TLA+ predicate check distinguishes fixed values from domain membership.
Independent value and definedness predicates enter the complete `Init` conjunction check.
Canonical set text order remains separate from source evaluation order.
Independent failure checks retain ordered addition operands, lazy branch guards and successful prefix bindings.
Fixed prefixes use bindings; domain prefixes use existential choices.
Nondeterministic prefixes do not claim a selected failure record.
The producer now visits membership domains and retains their definedness before emitting successful initial states.
Domains without failures no longer consume unused fresh binder names.

## TLA initial failure-event sets

The deterministic selected record already retains a before-prefix and is consumed by schema v4 evidence.
It cannot describe both failed branches of a nondeterministic initializer prefix.
The existing renderer now also emits `__SwiftTLAInitialFailureEvents`, with a fresh suffix when necessary, for its guarded Int observation route.
The existing coverage policy recognizes declared Int literals, reads, checked-add value initializers, optional program-counter initialization and supported Int domains.
Domain evaluation may itself contain checked additions and lazy conditional branches.
It handles both unresolved declared types and resolved types; parameters, selected initial invariants and other failure constructors remain outside this event-set capability.
Enumeration capacity and other operational failures remain separate from these model-failure records.
Other accepted programs retain their existing behavior and coverage limits.

Each reached addition site contributes a singleton record containing its initializer ordinal, kind, ordered operands and complete prior bindings, or an empty set when its predicate does not hold.
Earlier fixed values bind their existing fresh prefix names. Earlier domains form a union over their candidates.
Prefix type and definedness conditions guard these sets, so a failure at an earlier initializer prevents records from later initializers on that prefix.
The final union includes every supported site. The emitted declaration is checked for presence and uniqueness.
The existing independent addition checker validates the event expressions against the compiled expression and all prior bindings/domains.
Its explicit optional event input distinguishes checking this observation from the older predicate/selected-record checks; production supplies it whenever the supported event-set capability is required.

The unchanged-producer baseline executed one existing owner: its runtime retained the expected successful sibling and both site-1 overflow events, while the TLA event-set definition was absent.
The first repair passed the new branch/prefix/site controls but exposed a core-versus-resolved bundle mismatch because coverage required resolved types.
The shared eligibility correction retains the old selected-record requirement and emits the same event set before and after resolution for known declared Int/control shapes.
The final diagnostic passed all 40 tests in five existing suites, including the original full bundle-equality guard and the actual evidence consumer.
No model/fixture type, evaluator, checker family, compatibility spelling, pin, budget, timeout or corpus case was added.

The domain extension reuses the existing lazy membership owner. Its unchanged-producer baseline retained the valid sibling and native event, but emitted no event set.
The emitter now receives the typed initializer identity for both value and domain evaluation. Non-failing domains retain their previous helper-name allocation.
An additional public-export equality check exposed a real unresolved-type failure after successful compilation and test execution.
The shared ordered arithmetic collector now accepts unresolved Int expressions, as its existing arithmetic fallback already did, while retaining lazy evaluation order.
The final guarded run passed 103 tests in six suites on all 1,201 unchanged captured inputs.
The complete 94,666-byte log has SHA256 `4b3b09741dec89537ba01b9bcf5923d198940e4eed68e2921202789b9a0f29e1`.
The existing owner checks complete preceding bindings and actual sites, rejects changed site/prefix/branch/missing-event output, and compares both full TLA export paths.
No event-set ordering or generic source-to-output theorem follows from these regressions.

Schema v5 of the existing deterministic evidence consumer prepares `CompleteFailureEvents` against the actual emitted operator and the complete native singleton event set for that existing case.
The existing pinned job also prepares an occurrence-checked, changed-input empty-set corruption, separate from its operand and before-prefix corruptions.
These generated proof checks require their own execution evidence. Preparation and regression results do not establish their mathematical conclusions.
Even a later successful case check does not prove generic source/output correspondence.
Event order and multiplicity, the serialized-record/partial-binding relation, unsupported initializer/failure constructors, selected invariants and whole accepted-program preservation remain open.

## Prior initialization evidence at admitted `1fb1dde9`

The canonical owners are `OrderedAssignmentLoweringTests`, `DependentInitializationOutputProofTests` and `InitialBranchFailureTests`.
Separate unchanged-checker baselines exposed source/resolution corruptions, skipped source witnesses and whole-output escapes.
These deliberate corruptions show checker gaps; they do not show wrong unchanged production lowering.
Accepted-program execution separately exposed three missing TLA+ failure relations: a lazy membership domain, a plain fallible set and a value after a range.
The measured producer repair preserved their valid sibling states, payloads and initializer sites.

Six actual-output controls then exposed three Swift and three TLA+ checker gaps.
The repaired checks reject those six, plus actual `Init` definedness and branch-value corruptions.
The output repair passed 77 focused tests and 488 tests in all 51 related owners.
Both existing canonical TLA+ modules remain exact without fixture changes.
A further source-only baseline executed four existing tests and exposed five corruptions across builder, rewrite and parser boundaries.
Swapped overflowing members changed the observed payload from `[1, Int.max]` to `[Int.max, 1]`.
Complete-state, failure-payload, native/TLA+ artifact and raw Swift `1 + 2` positives passed in that baseline.

The final source extension passed 77 focused tests and 488 tests in all 51 related owners.
The five measured source corruptions now reject; total-domain, raw Swift arithmetic and all existing output controls still pass.
All 78 frozen implementation inputs remained exact through both runs.

The existing 24-row pinned `--nofp` batch proved 1,901 obligations.
All 157 retained TLA+ snapshots and both runner hashes remain exact after the source-only repairs.
This byte confirmation is not a new tool bootstrap or binary reproduction.
The admitted ordinary proof receipt contains 227 actual input entries.
The admitted hosted run proved 100 modules and 6,408 obligations.
Those prior results do not replace the separate admission of the source-elaboration repair at `3a0dda1b`.
Regression, fixture and inventory counts provide no language-proof credit.

## Source-elaboration repair at admitted `3a0dda1b`

An executed accepted-program baseline found four source/builder issues.
Raw Swift division and remainder were translated as formal operations.
A nested raw child changed the valid initial-state set.
A raw scalar `1 + 2` initializer also failed the existing source witness.
The baseline records distinguish these defects from deliberately corrupted output controls.

The parser now evaluates successful closed integer syntax as a Swift `Int` value before DSL construction.
Explicit formal result annotations retain the formal root operation.
Known raw subexpressions inside formal operands retain Swift evaluation.
This is not global folding of formal ASTs.
An executed typed-step-local baseline found a further mismatch.
The actual runtime retained formal `5 / -2 = -3`; generated Swift returned `-2`.
`parseFormalLet` now forwards the same result annotation as the other known declaration routes.
The final signed owner observed `-3` for the formal local and `-2` for the raw `Int` local.
Full overload, declaration, alias, factory and closure-result correspondence remains open.

A separate executed baseline produced four valid builder initial states using `Int.min`.
The unchanged parser rejected that initializer.
The current bound-member decoder requires the existing type resolver to identify primitive `Int`.
It also checks known lexical, constant and module shadows.
The qualification owner distinguishes standard bounds from an enum named `Int` with its own `min` and `max` cases.
External type and module binding remains an owned premise.

The native emitter removes a redundant arithmetic closure only for two total Int literal operands of division or modulo.
It still calls the qualified checked native helper, retaining formal floor division and modulo failures.
The action-output checker independently requires that exact helper and ordered literal operands.
Its controls alter an operand, operand order, operation and qualification.
All other arithmetic keeps the prior temporary-value and evaluation-order path.

The same signed owners retain raw division, formal division and `integerDivided` results separately.
They also check zero divisors, division overflow, negative modulo divisors and complete snapshots after failure.
These are actual source/runtime/native regressions, not constructor-proof credit.
The general divide/modulo source, output, child-composition and kernel proofs remain incomplete.

The complete Int initializer checker retains the same expected template and strict token comparison.
Its private template builder returns before parsing, reducing the caller stack frame.
The formerly crashing initialization owner passed in both the focused and complete related runs.
The expected template bytes remain exact. These results do not prove unbounded nesting capacity.

That source-only repair preserved all 157 theorem files and both runner inputs against admitted objects and actual retained snapshots.
This is byte preservation, not a new proof execution, tool bootstrap or binary reproduction.
The final focused run passed 44 tests in four suites on unchanged production bytes.
The parser contract separately passed one test after its expected raw initializer shape was corrected.
That contract retains both raw and explicit formal expressions against independent real builder compilations.
The final related run passed 567 tests in all 59 selected suites.
All 1,127 frozen tracked inputs remained exact through that run.
The new ordinary proof receipt contains 243 actual input entries, including the parser and type-metadata dependencies.
It retains all 227 earlier entries. A receipt records bytes; it does not prove those dependencies sound.
The source-elaboration candidate is admitted at `3a0dda1b` within the existing hosted regression and proof boundary.
The universal accepted-program preservation objective remains open.

## Source forms covered by this repair

This is a partial acceptance/link inventory. No row is a complete accepted-program certificate.

| Source form | Lowered form and current link | Remaining boundary |
| --- | --- | --- |
| Successful closed Swift integer `+`, `-`, `*`, `/`, `%`, negation and parentheses | A literal Int value; parser fold and independent lexical witness preserve Swift precedence and left associativity | Actual Swift binding, contextual result classification, parser/witness correctness and raw failure behavior |
| Explicit formal `Expr<Int>` arithmetic | The formal operator remains; literal divide/modulo roots keep the checked qualified native helper | General operator source/output rules, arbitrary child composition and native/helper/checker soundness |
| Primitive Int `min` and `max` members | Scope/type metadata identifies Int, then a literal reaches normal lowering and output paths | Complete metadata collection and external type/module binding; this form remains outside the lexical source witness |
| Raw and formal typed locals in `Do` | The result annotation reaches the existing lexical binding decoder; runtime/native comparisons distinguish both results | General lexical extraction, capture/layout correspondence and arbitrary accepted local values |

`OrderedIntExpressionRule` composes literal, read and checked-addition nodes under its stated plan and projection premises.
The division/modulo regressions do not extend that theorem to those constructors.
The wider accepted-constructor inventory remains incomplete.

## Partial-prefix expression connection

`ExpressionReadKeys` identifies every read node in the finite literal/read/add plan.
The source and generated node rules depend only on those bindings and their earlier child outcomes.
Read agreement therefore preserves every history outcome, including ordered overflow operands and the first child failure.
The proof applies to both source histories and generated histories.

`PartialExpressionPlan` requires those read keys in the current partial binding.
Its completion supplies zero only for absent keys, without changing any bound value.
The partial histories exist, retain typed outcomes, and agree with every total completion that preserves the bound values.
The completion value is therefore unobservable through these expression rules.
No runtime or source-language rule requires absent keys to contain zero.
The mathematical plan still requires well-founded child positions and the existing literal/read/add forms.
Source extraction and correspondence to actual layout identities remain premises.

`OrderedIntInitializationComposition` projects only initialized Int keys from a partial binding.
Independent source and generated adapters convert expression success into a fixed candidate and failure into its complete payload.
The leaf theorem preserves the preceding binding, target identity, complete candidate states and failure event.
The mathematical negative controls distinguish changed read values and reversed overflow operands.
These controls do not replace actual-output mutation regressions.

The history theorem derives initializer agreement from expression plans and histories on every reachable source prefix.
It derives that agreement at designated Int value positions, with child agreement premises at all other positions.
The composition therefore permits other initializer constructors, including nondeterministic domains.
It does not require expression typing on unreachable assignments that give an Int key a non-Int value.
The generic reachable-prefix theorem then composes all successful states and accumulated failure events across arbitrary finite initializer counts, including zero.
Selected checks still require outcome agreement on the completed reachable states.
Under that premise, terminal selection retains exactly the same complete states and failure events.
These are set histories, not a proof of the concrete depth-first traversal or the first stored failure.
Other initializers retain their separate constructor rules and child obligations.

The admitted partial-prefix change preserved the existing production source and output checks and their rejecting controls.
It does not prove dependency extraction, source-key association, source-to-plan extraction or output-checker soundness.
The existing host tool and solver correctness premises remain explicit.

The admitted partial-prefix revision's local `--nofp` batch passed 418 expression obligations, 275 initialization obligations and 70 obligations in its connection module.
All 158 retained TLA+ snapshots and both runner hashes match the checked bytes.
All 24 prior batch rows remain in order, before the new connection module.
Static checks, the five download controls, family isolation and whitespace checks passed.
Production, test, fixture, toolchain and workflow bytes remain unchanged from admitted `3a0dda1b`.
No new local Swift test, legacy proof batch, tool bootstrap or binary reproduction is claimed.
At admitted `ba4c9bbf`, ordinary hosted validation executed all 101 modules and proved 6,598 obligations.
That admission does not cover the local read-dependency follow-on below.

## Read dependencies and stable initialization order

The read-dependency follow-on starts from admitted `ba4c9bbf`.
Its initial mathematical stage extended only the existing proof owners.
The current follow-on also extends the existing resolved validator and its canonical dependency-order regression.
That candidate repair is awaiting local Swift validation.
The constructor inventory remains literal/read/checked-add for these expression rules.
Other initializer and expression constructors retain their own child obligations.

`ExpressionReadHistory` defines syntactic read effects independently of evaluation outcomes.
Literal nodes contribute no reads, read nodes contribute their key, and addition joins both child effects.
A finite typed history of these effects exists for every existing expression plan.
This effect includes both children even when evaluation would fail in the first child.
It describes conservative initialization dependencies, not evaluation order or a failure trace.

A topologically numbered plan can contain nodes outside its root subtree.
`ExpressionIndexStack` describes the existing postorder builder's push and binary-fold operations.
The final stack contains only the root.
`ConstructedPlanPreservesAllReads` proves that this construction retains exactly all numbered read keys at the root.
The construction and source-key association are explicit premises.
The conclusion does not cover arbitrary DAGs with unused nodes.

`ReadWalkStep` pops pending nodes, collects state reads, and pushes addition's left child followed by its right child.
This matches the right-first scheduling in unresolved `CompiledExpression.stateRequirements` for this constructor slice.
Each step preserves collected reads joined with pending subtree effects.
A completed formal walk therefore returns exactly the constructed plan's source reads.
The resolved validator uses a separate postorder effect stack and function-effect fixed point.
Its general call, binder and demand rules are not covered by this walk theorem.
No Swift or TLA+ evaluation-order claim follows from dependency-walk order.

Completion is now constructed within the proof.
`ExpressionWorkHistory` gives each leaf one unit and each addition one plus both children's work.
This positive finite history exists for every expression plan.
`StackWorkHistory` sums the pending nodes' work.
A nonempty stack has positive work, and every step constructs a well-typed successor with exactly one less unit.
Natural-number induction constructs a finite completion from the initial root stack.
No completed walk, supplied fuel trace or extra termination premise is required by that existence theorem.
Successors are deterministic.
Two walks agree on every common prefix.
A completed walk bounds the length of every other segment from the same initial stack.
These are mathematical termination results for the stated small-step rule, not a performance or allocation guarantee.

`GeneratedReadDependencies` obtains its result from a completed formal walk.
The proof establishes both existence and exact agreement with the independent source read set.
Its choice of completion cannot change that result.
The initializer connections therefore no longer require callers to supply read-effect or completed-walk histories.
They still require plan construction, source/layout identity correspondence and typed Int prefix bindings.
The readiness connection then supplies the existing partial expression histories and initializer outcome agreement.

The source readiness rule requires every dependency to be bound.
The generated rule requires dependencies to be disjoint from remaining declarations.
These predicates agree when remaining keys complement the bound prefix.
A nonempty ready set has a unique first declaration position.
Successful source and generated schedules therefore have the same prefixes and order.
Removing a ready key binds exactly that key.
Execution position is not identified with a variable's layout ordinal.

`RankedDependenciesConstructACompleteStableOrder` constructs the complete schedule under a decreasing dependency rank.
It extends ready prefixes, maintains the remaining-key count, and derives the output permutation when no keys remain.
It also constructs the exact one-key removal history, including the zero-declaration case.
It does not assume `InitializationOrder` for its output.
Conversely, a successful source schedule supplies a decreasing rank by inverse execution position.
Rank is therefore not a new source-language guard.
Correspondence with actual accepted-source dependencies and concrete cycle diagnostics still requires proof.

The mixed Int connection derives dependency-map agreement from constructed expression plans and the total dependency algorithm.
Other targets retain explicit dependency agreement premises.
It then constructs a common source/generated stable schedule and binds every read before evaluation.
No completed walk or complete output schedule is supplied to this combined construction theorem.
The declaration list and its identity mapping remain input premises.
The existing runtime/native initial-state and failure composition still needs concrete loop correspondence.

Mathematical negative controls distinguish omitted reads and skipped earlier ready declarations.
Existing changed-read and reversed-overflow-operand controls remain.
These controls are not new actual-output mutation results.
The existing source, Swift-output and TLA+-output rejecting controls remain unchanged.

The first constructive stage passed 25 local `--nofp` rows and 2,995 obligations.
Its expression, initialization and connection owners proved 913, 592 and 162 obligations respectively.
The current integrated batch includes the read-certificate lemma and four range rules.
It passed all 25 ordered rows and 3,019 obligations.
Its expression, initialization and connection owners proved 934, 595 and 162 obligations respectively.

All 158 retained TLA+ snapshots and both runners matched the current proof inputs.
Seventeen library file hashes matched observations during and after the current batch.
They also matched the earlier recorded library inputs.
These local proofs are diagnostic evidence only.
Hosted admission uses the exact frozen revision.

Four range rules separate logical membership from enumeration width.
The bounds-guard model agrees with an independent integer-width budget.
A reversed range has no logical members and passes that guard.
Logical membership uses only the lower and upper bounds.
Zero belongs to the full Int range, although its enumeration guard fails.
These rules do not prove the concrete generated membership or capability adapter.

The next owned boundary is extraction of plans, identities and formal steps from the actual compiler loops.
Source-to-plan extraction, layout/target association, concrete cycle diagnostics, operator/capture effects and output-checker soundness remain unproved.
The host tool, solver and kernel trust limits remain unchanged.

## Resolved order-checking baseline and candidate

The existing canonical dependency-order owner now mutates only the initialization order of real compiled programs.
The first unchanged-production baseline executed one test and accepted both intended order corruptions.
The expanded baseline executed the same owner and accepted exactly four corruptions.
It covers independent ready ties, a later ready limit, a newly ready read/add initializer, and first-failure selection.
The correct source variation fails with addition operands `[3, Int.max]` at the first target.
Swapping two ready initializers changes the corrupted program's failure to `[4, Int.max]` at the second target.
All positives passed.
These validator blind spots concern deliberately corrupted plans.
The baselines did not show wrong unmutated production lowering.
No new named model, fixture, production hook or checker API was added.

The candidate extends the existing `validateInitializationDependencies` path.
It retains all availability, complete-state, duplicate-target and total-coverage diagnostics before the new order check.
The existing postorder effect pass assigns structural read-set certificates to typed Int and control leaves.
Its compound cases cover addition, equality, integer ranges, Int set literals and conditional Int domains.
Each compound case requires child certificates, exact types and the required arity.
A second pass rejects an initializer that skips an earlier ready declaration with such a read set.
Unknown constructor families retain their existing checks and explicit dependency premises.
The new certificate lemma identifies when those checks establish the full first-ready rule.
It requires coverage of every remaining earlier declaration.
A partial certificate does not establish universal ordering.

The scalar/addition candidate passed the unchanged canonical owner, including its four rejecting controls and positives.
All 13 frozen inputs matched after its 1,220.09-second cold build.
A subsequent mutation-only extension in the same owner accepted exactly three domain-order corruptions: `readyRange`, `readyMembers` and `readyConditional`.
All domain positives produced three complete states with derived values 2, 3 and 4.
That baseline kept the scalar candidate unchanged and introduced no new fixture or production seam.
The domain certificate extension followed those three actual escapes.
The focused owner passed all seven rejecting controls and its state and failure positives.
All 14 frozen inputs matched after its 1,279.36-second cold build.
The related run passed 205 tests across all 22 selected suites.
All 35 recorded inputs matched at that run's completion.
These runs include the existing recursive-demand, cycle, initializer, output, lexical, native, Dining and deep-binding controls.

The ordinary proof-input receipt now includes this existing validator and canonical test owner.
This is a resolved-program check.
Standalone compiled-specification runtime/rendering uses a separate unresolved route.
The candidate does not certify that route or supply the missing source/layout and compiler-step correspondence.
The formal expression construction still covers literal, read and addition nodes.
Equality, range, set-literal and conditional domain read/evaluation correspondence remains an explicit obligation.
The generic domain initializer theorem starts from supplied members and does not discharge that obligation.
The existing direct Swift/TLA+ output mutation controls remain unchanged.
The new validator controls do not replace those output links or provide language-proof credit.
No new hosted admission, bootstrap or binary reproduction is claimed.

## Remaining owned obligations

- Complete the accepted-constructor inventory by source spelling, typing, placement and backend capability.
  Public declaration and AST inventories alone do not establish acceptance or preservation.
- Extend source extraction and binding correspondence through every accepted expression and algorithm control form.
- Connect the proved finite read walk and complete stable scheduler to actual extraction and returned schedules.
  Verify the accepted cycle-diagnostic boundary and the separate resolved effect/fixed-point route.
  Preserve source-key and layout identity correspondence.
  Execution position need not equal layout ordinal.
- Supply independent value, definedness and payload rules for each initializer child constructor, including range capability failures.
- Relate the concrete LIFO frontier and generated loops to every source branch and callback event.
  Keep finite branching, enumeration and termination assumptions explicit.
- Prove the concrete error/site encoding, native helpers and output-checker soundness.
  Include checking registers and other observation state where needed.
- Distinguish selected-state, sampled and non-enumerable capability outcomes from exhaustive initialization.

The ordinary `action-composition.batch` owns the constructor before its composition.
No new family selector or manual admission dispatch is added.
A final reviewed revision needs two new automatic hosted runs and complete retained-evidence reconciliation.
The universal preservation objective remains open.
