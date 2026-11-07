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
The input type premise still needs its source connection: type inputs use the layout's explicit resolved type or resolve its generated Swift spelling.
The source resolver's primitive `Int` branch returns `.int`; alias/nominal precedence, layout metadata and actual Swift name binding remain owned source obligations.
General calls/processes, cache-context completeness for nonliterals, backend interpretation, complete initializer histories and all six-link rows remain open.
This argument changes no checker, evaluator or theorem body. It is a manual implementation proof, with local regressions kept separate from mathematical proof and hosted admission.

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
