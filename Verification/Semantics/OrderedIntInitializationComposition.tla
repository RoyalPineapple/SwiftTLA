-------------------- MODULE OrderedIntInitializationComposition --------------------
EXTENDS InitializationComposition, Integers

CONSTANTS IntKeys, SwiftIntMin, SwiftIntMax
Expressions == INSTANCE OrderedIntExpressionRule WITH Keys <- IntKeys

IntInitializationDomains ==
    /\ SwiftIntMin \in Int /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= -2000000000 /\ 2000000000 <= SwiftIntMax
    /\ IntKeys \in SUBSET Keys
    /\ SwiftIntMin..SwiftIntMax \subseteq Values
    /\ Expressions!ArithmeticFailures \subseteq FailureValues
    /\ NoFailure \notin Expressions!ArithmeticFailures

PartialIntProjection(prior) ==
    [key \in (DOMAIN prior) \cap IntKeys |-> prior[key]]

SourceIntInitializerOutcome(result) ==
    IF result.ok THEN SourceFixed(result.value) ELSE SourceFailed(result.failure)
GeneratedIntInitializerOutcome(result) ==
    IF result.ok THEN GeneratedFixed(result.value) ELSE GeneratedFailed(result.failure)

THEOREM IntExpressionOutcomesSupplyInitializerOutcomes ==
    ASSUME IntInitializationDomains, NEW result \in Expressions!ExpressionOutcomes
    PROVE /\ SourceIntInitializerOutcome(result) = GeneratedIntInitializerOutcome(result)
          /\ SourceIntInitializerOutcome(result) \in InitializerOutcomes
    PROOF
    <1>1. CASE result.ok
        <2>1. result.value \in Values
            BY <1>1, SMT DEF Expressions!ExpressionOutcomes, IntInitializationDomains
        <2>. QED BY <1>1, <2>1, FixedInitializerRetainsItsOnlyCandidate, SMT
            DEF SourceIntInitializerOutcome, GeneratedIntInitializerOutcome
    <1>2. CASE ~result.ok
        <2>1. result.failure \in FailureValues
            BY <1>2, SMT DEF Expressions!ExpressionOutcomes, IntInitializationDomains
        <2>. QED BY <1>2, <2>1, FailedInitializerRetainsItsCompletePayload, SMT
            DEF SourceIntInitializerOutcome, GeneratedIntInitializerOutcome
    <1>. QED BY <1>1, <1>2, SMT DEF Expressions!ExpressionOutcomes

THEOREM OrderedIntExpressionsSupplyPartialInitializationLeaves ==
    ASSUME IntInitializationDomains, NEW prior \in PartialBindings,
           NEW target \in IntKeys \ (DOMAIN prior),
           NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW source, NEW generated,
           Expressions!PartialExpressionPlan(count, kinds, literals, reads, left, right,
               (DOMAIN prior) \cap IntKeys, PartialIntProjection(prior)),
           Expressions!SourceExpressionHistory(count, kinds, literals, reads, left, right,
               PartialIntProjection(prior), source),
           Expressions!GeneratedExpressionHistory(count, kinds, literals, reads, left, right,
               PartialIntProjection(prior), generated)
    PROVE /\ SourceIntInitializerOutcome(source[count]) = GeneratedIntInitializerOutcome(generated[count])
          /\ SourceIntInitializerOutcome(source[count]) \in InitializerOutcomes
          /\ SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(source[count]))
                = GeneratedInitialLeaf(prior, target, GeneratedIntInitializerOutcome(generated[count]))
    PROOF
    <1>1. source[count] = generated[count]
          /\ source[count] \in Expressions!ExpressionOutcomes
        BY Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
            DEF Expressions!PartialExpressionPlan, Expressions!ExpressionPlan, Expressions!OutcomeAgrees,
                IntInitializationDomains
    <1>2. SourceIntInitializerOutcome(source[count]) = GeneratedIntInitializerOutcome(generated[count])
          /\ SourceIntInitializerOutcome(source[count]) \in InitializerOutcomes
        BY <1>1, IntExpressionOutcomesSupplyInitializerOutcomes, SMT
    <1>3. DOMAIN prior \subseteq Keys /\ prior \in [DOMAIN prior -> Values]
        BY PartialBindingsHaveSourceTypes
    <1>4. target \in Keys \ (DOMAIN prior)
        BY SMT DEF IntInitializationDomains
    <1>5. SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(source[count]))
            = GeneratedInitialLeaf(prior, target, SourceIntInitializerOutcome(source[count]))
        BY <1>2, <1>3, <1>4, InitializerLeafRetainsCompleteStatesAndFailures
    <1>. QED BY <1>2, <1>5, SMT

IntInitializerChildren(plan, prior, source, generated) ==
    /\ Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
           plan.reads, plan.left, plan.right, (DOMAIN prior) \cap IntKeys, PartialIntProjection(prior))
    /\ Expressions!SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
           plan.reads, plan.left, plan.right, PartialIntProjection(prior), source)
    /\ Expressions!GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
           plan.reads, plan.left, plan.right, PartialIntProjection(prior), generated)

THEOREM IntInitializerChildrenSupplyOutcomeAgreement ==
    ASSUME IntInitializationDomains, NEW plan, NEW prior, NEW source, NEW generated,
           IntInitializerChildren(plan, prior, source, generated)
    PROVE SourceIntInitializerOutcome(source[plan.count])
        = GeneratedIntInitializerOutcome(generated[plan.count])
    PROOF
    <1>1. source[plan.count] = generated[plan.count]
          /\ source[plan.count] \in Expressions!ExpressionOutcomes
        BY Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
            DEF IntInitializerChildren, Expressions!PartialExpressionPlan,
                Expressions!ExpressionPlan, Expressions!OutcomeAgrees, IntInitializationDomains
    <1>. QED BY <1>1, IntExpressionOutcomesSupplyInitializerOutcomes, SMT

THEOREM OrderedIntInitializerChildrenComposeAllReachableStatesAndFailures ==
    ASSUME IntInitializationDomains,
           NEW count, NEW order, NEW sourceEvaluate, NEW generatedEvaluate,
           NEW source, NEW generated, NEW plans, NEW sourceExpressions, NEW generatedExpressions,
           NEW intValuePositions \in SUBSET (1..count),
           InitializationOrder(count, order),
           InitializerEvaluators(count, sourceEvaluate),
           InitializerEvaluators(count, generatedEvaluate),
           InitializationHistory(FALSE, count, order, sourceEvaluate, source),
           InitializationHistory(TRUE, count, order, generatedEvaluate, generated),
           \A index \in 1..count :
               \A prior \in source[index - 1].states :
                   IF index \in intValuePositions
                   THEN /\ order[index] \in IntKeys
                        /\ IntInitializerChildren(plans[index], prior,
                               sourceExpressions[index][prior], generatedExpressions[index][prior])
                        /\ sourceEvaluate[index][prior] =
                               SourceIntInitializerOutcome(sourceExpressions[index][prior][plans[index].count])
                        /\ generatedEvaluate[index][prior] =
                               GeneratedIntInitializerOutcome(generatedExpressions[index][prior][plans[index].count])
                   ELSE sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
    PROVE /\ \A index \in 0..count : source[index] = generated[index]
          /\ \A sourceChecks, generatedChecks :
                 (sourceChecks \in [PartialBindings -> SelectionOutcomes]
                  /\ generatedChecks \in [PartialBindings -> SelectionOutcomes]
                  /\ \A prior \in source[count].states : sourceChecks[prior] = generatedChecks[prior])
                 => /\ SourceTerminal(source[count], sourceChecks)
                         = GeneratedTerminal(generated[count], generatedChecks)
                    /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
    PROOF
    <1>1. \A index \in 1..count :
              \A prior \in source[index - 1].states :
                  sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
        BY IntInitializerChildrenSupplyOutcomeAgreement, SMT
    <1>2. \A index \in 0..count : source[index] = generated[index]
        BY <1>1, InitializationHistoriesNeedOnlyReachableChildAgreement
    <1>3. source[count].states \subseteq [Keys -> Values]
        BY SourceHistoriesBindEveryPrefixKey, SMT DEF InitializationOrder
    <1>4. \A sourceChecks, generatedChecks :
              (sourceChecks \in [PartialBindings -> SelectionOutcomes]
               /\ generatedChecks \in [PartialBindings -> SelectionOutcomes]
               /\ \A prior \in source[count].states : sourceChecks[prior] = generatedChecks[prior])
              => SourceTerminal(source[count], sourceChecks)
                    = GeneratedTerminal(generated[count], generatedChecks)
        BY <1>2, TerminalSelectionRetainsEveryStateAndFailure, SMT
            DEF InitializationHistory, InitializationOrder
    <1>. QED BY <1>2, <1>3, <1>4, SMT DEF SourceTerminal, SourceSelectedStates

THEOREM ChangingAReadChangesTheFixedInitializerCandidate ==
    ASSUME NEW first \in Values, NEW second \in Values, first # second
    PROVE SourceIntInitializerOutcome(Expressions!Success(first))
        # GeneratedIntInitializerOutcome(Expressions!Success(second))
    BY SMT DEF SourceIntInitializerOutcome, GeneratedIntInitializerOutcome,
        SourceFixed, GeneratedFixed, Expressions!Success

THEOREM ReversingOverflowOperandsChangesTheInitializerFailure ==
    ASSUME NEW prior, NEW target, NEW left, NEW right, left # right
    PROVE SourceInitialFailures(prior, target,
              SourceIntInitializerOutcome(Expressions!SourceOverflow(left, right)))
        # GeneratedInitialFailures(prior, target,
              GeneratedIntInitializerOutcome(Expressions!GeneratedOverflow(right, left)))
    BY InitialSentinels, SMT DEF InitialSentinels, SourceInitialFailures,
        GeneratedInitialFailures, SourceIntInitializerOutcome, GeneratedIntInitializerOutcome,
        SourceFailed, GeneratedFailed, Expressions!SourceOverflow, Expressions!GeneratedOverflow

=============================================================================
