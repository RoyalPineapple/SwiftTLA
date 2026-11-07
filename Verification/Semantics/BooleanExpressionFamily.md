# Boolean expression family

This lane starts at admitted commit `d0419d84501e7043b1f67a184740d81ceb2ee3c6`.
The selected constructors are existing Boolean `not`, `and`, `or`, and `ifThenElse` expressions.
This lane adds no authoring syntax or model fixtures.
The normalized-source link is a dependent follow-on to family revision `a1c999d82387192c0f3eb6f2a26cdbcc55aefc48`.
It does not establish a new independently admitted family.

## Semantic contract

`BooleanExpressionConstructorRules.tla` defines separate source, native Swift, and TLA rules.
Each rule retains the selected child failure without changing its payload.
`FailureValues` can contain complete records with the failure site, kind, and operands.
`NoFailure` is outside that set.

Each outcome contains definedness, a Boolean value, and the selected failure.
A failed outcome has the canonical value `FALSE`.
The constructor rules skip failures from operands that the source does not evaluate.
The rules retain the first failure from operands that the source evaluates.

`ConditionProjection` maps an expression outcome into `ActionOutcomeInterface.ConditionOutcome` through a module instance.
The projection retains the entire selected failure.
The shared outcome module remains unchanged.

## Finite composition

`BooleanExpressionComposition.tla` uses semantic functions from arbitrary contexts to expression outcomes.
The context can contain the complete source state and lexical environment.
Each node refers only to earlier child nodes.
The source, native Swift, and TLA histories have separate definitions and separate existence obligations.

`IndexedHistoryRules` supplies finite history existence and agreement.
The parent rules derive agreement from earlier child agreement and the constructor rules.
The theorem does not assume equal parent results or restrict the tree depth.
Leaf agreement remains an explicit premise for each context.

## Implementation links

| Boundary | Production owner | Evidence owner |
| --- | --- | --- |
| Source constructor and ordered children | `CompiledLowerer.scheduleBooleanBranch` and `BooleanBranchLoweringContract` | `BooleanBranchLoweringContractTests` and existing source compilation in `ShortCircuitFailureProofTests` |
| Normalized source to untyped compiled constructors, operands, and identities | `StraightLineAssignmentCheck.verifyCompiled`, called by `CompiledLowerer` | `ShortCircuitFailureProofTests.normalizedBooleanOperands` |
| Actual native Swift output | `NativeSwiftEmitter+Boolean` and `verifyGeneratedActionWriteOutput` | Existing native mutations in `ShortCircuitFailureProofTests` |
| Actual TLA value and definedness | `StraightLineRenderedActionCheck.verify` | `ShortCircuitFailureProofTests.renderedBooleanOutcomes` |
| Actual TLA failure predicates, order, and operands | `StraightLineRenderedActionCheck.verifyEvaluationSelection` | `ShortCircuitFailureProofTests.renderedBooleanOutcomes` |

The TLA checker derives expressions and failure guards from compiled constructors and identities.
It does not call the renderer for the selected Boolean fragment.
It accepts scalar variables, binders, literals, equality, and modulo as leaves for this fragment.
The checker retains modulo operand order and derives its zero-divisor and negative-divisor sites independently.
Unsupported leaf forms retain the existing acceptance path and remain explicit premises.

The tests use existing conjunction, disjunction, nested guard, and assignment fixtures.
The mutations change branch selection, Boolean operators, negation, definedness, failure predicates, failure operands, and the aggregate failure selection.
The existing native tests reject changed helper calls, conditions, and leaf operations.
The focused filters are `ShortCircuitFailureProofTests|BooleanBranchLoweringContractTests`.

## Normalized-source correspondence

The existing mandatory source checker compares the normalized source action with its untyped compiled action.
Its paired traversal checks the four Boolean constructors, their arity, and their ordered operands.
The traversal uses existing source-name mappings to check state-variable IDs and current fresh binder associations.
It does not derive its expected operands from the lowerer's scheduled child array.

The existing finite scalar binding and fresh-definition gates remain unchanged.
Unsupported expressions and action scopes retain their existing acceptance path and remain explicit premises.
This follow-on adds no model, checker hook, proof module, or binding mechanism.

The regression uses the actual normalized source and compiled output of three existing fixtures.
It changes one expression occurrence while preserving action wrappers, targets, and unaffected operands.
The controls omit operands or constructors, change operators, reverse operands, swap conditional arms, and replace state or capture reads.
Each rejection must use the source-correspondence diagnostic, not an unrelated frame error.

## Remaining premises and limits

- Source normalization and capture substitution must preserve the original source semantics.
- Boolean type resolution must preserve the checked untyped expression structure and identities.
- Layout name-to-ID tables and unsupported source scopes remain separate obligations.
- The source link does not establish general shadowing, process-local, `Each`, or `LET` correspondence.
- Leaf semantic agreement must retain the value and complete failure payload for every context.
- Arithmetic leaf semantics, including modulo, remain separate obligations despite the independent output syntax check.
- Native helper semantics and the Swift compiler remain trusted implementation boundaries outside these TLA rules.
- The expression theorem does not establish whole-action successor sets, framing, invocation labels, or deadlock behavior.
- Unsupported expression leaves do not gain an independent output claim from this lane.

## Evidence state

The proof batch is `Verification/Semantics/boolean-expression.batch`.
[Hosted diagnostic 41211433970](https://github.com/RoyalPineapple/SwiftTLA/actions/runs/41211433970)
ran revision `6eceaf567fe20f43897eb5c6877234c84135ab65` and failed.
The implementation job stopped because the optional getter inferred an optional string accumulator.
The proof job failed at the combined history-existence conclusion.

[Hosted diagnostic 41215348460](https://github.com/RoyalPineapple/SwiftTLA/actions/runs/41215348460)
ran revision `555a832d0cac5a00561c5de8489b5d919118641f` and failed at the source-history witness.
Its implementation job passed the 10 focused family tests.

The current proof body isolates each step-function type fact and expands only `IndexedHistory` at each history-existence step.
A complete local `--nofp` batch passed with proof manager `941f894` and Z3 `4.15.4`.
The retained proof-source hashes match the local inputs.
This proof-body change does not change theorem statements, premises, shared definitions, or tool limits.

The admitted checker rejected the new test's valid actual output at `tla.action.scalarAssignments`.
That baseline demonstrates missing output support, not rejection of each subsequent mutation.
After exact checker restoration, all 36 focused and related local tests passed.
The related owners are `ConjunctionFailureSelectionTests` and `OrderedAssignmentLoweringTests`.
[Hosted family diagnostic 41221018586](https://github.com/RoyalPineapple/SwiftTLA/actions/runs/41221018586)
passed both required jobs at `a1c999d82387192c0f3eb6f2a26cdbcc55aefc48`.
The coordinator reconciled its retained tools, input hashes, and artifacts.

The normalized-source regression first ran against the unchanged admitted source checker.
Its one executed test reported exactly 25 accepted mutation controls, with no compilation or fixture failures.
After the constructor-matching extension, the unchanged focused test passed.
All 79 tests across the seven related owners also passed locally.
Those owners are `ShortCircuitFailureProofTests`, `BooleanBranchLoweringContractTests`, `OrderedAssignmentLoweringTests`,
`AlternativeTraversalTests`, `ActionFrameConditionTests`, `NativeExecutionBoundaryTests`, and `TypedActionParameterTests`.
The retained baseline and fixed logs are in `/tmp/swifttla-boolean-source-link.tDcB8a`.
The dependent source-link family at `20b20c3102e5490a5df8764d146f3a67c15aff7c` passed focused hosted run `41229944661` with retained source, proof, tool and mutation evidence reconciled.
That diagnostic does not admit this integrated revision.

Integration transports this family's reviewed changes onto admitted prerequisite `ecf3a762533134872baf1feea2e2622f84d537e2`.
It retains the unconditional definition-root payload gate and its canonical lexical regression, native helper qualification, and pinned Isabelle download repair.
The ordinary proof batch checks the Boolean constructor rules before the composition module.
The ordinary proof receipt includes the source checker and the existing regression owner.
Hosted checks remain the admission authority for an exact commit.
This document makes no universal compiler fidelity or release-readiness claim.
