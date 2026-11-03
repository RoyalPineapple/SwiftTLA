# Initialization outcomes and composition

Status: unpublished work on admitted base `0b7b6180`.
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
Literal-only Swift arithmetic stays outside that recognizer, preserving Swift evaluation before DSL construction.
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

## Executed evidence

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
The ordinary proof receipt currently contains 227 actual input entries.
Expected hosted totals are 100 modules and 6,408 obligations, derived from the current batch and unchanged legacy sources and admitted logs.
They are not a new local legacy execution or current hosted result.
Regression, fixture and inventory counts provide no language-proof credit.

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
