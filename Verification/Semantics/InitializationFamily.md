# Initialization outcomes and composition

Status: unpublished source-elaboration repair on admitted base `1fb1dde9`.
Local checks passed: 44 focused tests, one parser contract, and 567 tests across all 59 related suites.
Fresh hosted admission remains pending. The prior hosted admission is historical evidence.
`InitializationOutcomeRules` passed 38 obligations; `InitializationComposition` passed 247.
These are conditional rules. Complete accepted-program preservation remains open.

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
The public native result stores the first failure, not the complete event set.

## Current implementation links

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
That result does not admit the current source-elaboration repair.
Regression, fixture and inventory counts provide no language-proof credit.

## Current source-elaboration repair

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

All 157 current theorem files and both runner inputs match admitted frozen objects and actual retained snapshots.
This is byte preservation, not a new proof execution, tool bootstrap or binary reproduction.
The final focused run passed 44 tests in four suites on unchanged production bytes.
The parser contract separately passed one test after its expected raw initializer shape was corrected.
That contract retains both raw and explicit formal expressions against independent real builder compilations.
The final related run passed 567 tests in all 59 selected suites.
All 1,127 frozen tracked inputs remained exact through that run.
The new ordinary proof receipt contains 243 actual input entries, including the parser and type-metadata dependencies.
It retains all 227 earlier entries. A receipt records bytes; it does not prove those dependencies sound.
The candidate still requires fresh ordinary and full hosted admission.
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
The current division/modulo regressions do not extend that theorem to those constructors.
Initialization composition still requires child outcome agreement on every valid prefix.
The wider accepted-constructor inventory remains incomplete.

## Remaining owned obligations

- Complete the accepted-constructor inventory by source spelling, typing, placement and backend capability.
  Public declaration and AST inventories alone do not establish acceptance or preservation.
- Extend source extraction and binding correspondence through every accepted expression and algorithm control form.
- Derive stable dependency order from source reads and relate it to actual lowering and layout identities.
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
