# Boolean expression family

This lane starts at admitted commit `d0419d84501e7043b1f67a184740d81ceb2ee3c6`.
The selected constructors are existing Boolean `not`, `and`, `or`, and `ifThenElse` expressions.
This lane adds no authoring syntax or model fixtures.

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

## Remaining premises and limits

- Source child scheduling must associate each operand with the correct source occurrence and lexical environment.
- Leaf semantic agreement must retain the value and complete failure payload for every context.
- Arithmetic leaf semantics, including modulo, remain separate obligations despite the independent output syntax check.
- Native helper semantics and the Swift compiler remain trusted implementation boundaries outside these TLA rules.
- The expression theorem does not establish whole-action successor sets, framing, invocation labels, or deadlock behavior.
- Unsupported expression leaves do not gain an independent output claim from this lane.

## Evidence state

The proof batch is `Verification/Semantics/boolean-expression.batch`.
Local proof and focused Swift diagnostics are pending a serialized validation slot.
Hosted checks remain the admission authority for an exact commit.
This document makes no universal compiler fidelity or release-readiness claim.
