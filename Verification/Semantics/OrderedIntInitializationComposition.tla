-------------------- MODULE OrderedIntInitializationComposition --------------------
EXTENDS InitializationComposition, Integers

CONSTANTS IntKeys, SwiftIntMin, SwiftIntMax
Expressions == INSTANCE OrderedIntExpressionRule WITH Keys <- IntKeys
Membership == INSTANCE FiniteSetMembershipRule

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

\* Literal rows are constructed here; only other constructors supply child outcomes.
LiteralIntInitializerEvaluators(generated, count, positions, literals, other) ==
    [index \in 1..count |-> [prior \in PartialBindings |->
        IF index \in positions
        THEN IF generated
             THEN GeneratedIntInitializerOutcome(Expressions!Success(literals[index]))
             ELSE SourceIntInitializerOutcome(Expressions!Success(literals[index]))
        ELSE other[index][prior]]]

THEOREM LiteralIntInitializersComposeCompleteStatesAndFailures ==
    ASSUME IntInitializationDomains, NEW count, NEW order,
           InitializationOrder(count, order),
           NEW positions \in SUBSET (1..count),
           NEW literals \in [positions -> SwiftIntMin..SwiftIntMax],
           NEW sourceOther \in [(1..count) \ positions -> [PartialBindings -> InitializerOutcomes]],
           NEW generatedOther \in [(1..count) \ positions -> [PartialBindings -> InitializerOutcomes]],
           \A index \in (1..count) \ positions :
               \A prior \in [PrefixKeys(order, index - 1) -> Values] :
                   sourceOther[index][prior] = generatedOther[index][prior],
           NEW sourceChecks \in [PartialBindings -> SelectionOutcomes],
           NEW generatedChecks \in [PartialBindings -> SelectionOutcomes],
           \A state \in [Keys -> Values] : sourceChecks[state] = generatedChecks[state]
    PROVE LET sourceEvaluate == LiteralIntInitializerEvaluators(FALSE, count, positions, literals, sourceOther)
              generatedEvaluate == LiteralIntInitializerEvaluators(TRUE, count, positions, literals, generatedOther)
          IN /\ \E source : InitializationHistory(FALSE, count, order, sourceEvaluate, source)
             /\ \E generated : InitializationHistory(TRUE, count, order, generatedEvaluate, generated)
             /\ \A source, generated :
                 (InitializationHistory(FALSE, count, order, sourceEvaluate, source)
                  /\ InitializationHistory(TRUE, count, order, generatedEvaluate, generated))
                 => /\ \A index \in 0..count : source[index] = generated[index]
                    /\ SourceTerminal(source[count], sourceChecks)
                        = GeneratedTerminal(generated[count], generatedChecks)
                    /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
    PROOF
    <1>. DEFINE sourceEvaluate == LiteralIntInitializerEvaluators(FALSE, count, positions, literals, sourceOther)
                generatedEvaluate == LiteralIntInitializerEvaluators(TRUE, count, positions, literals, generatedOther)
    <1>1. \A index \in positions :
        /\ Expressions!Success(literals[index]) \in Expressions!ExpressionOutcomes
        /\ SourceIntInitializerOutcome(Expressions!Success(literals[index]))
            = GeneratedIntInitializerOutcome(Expressions!Success(literals[index]))
        /\ SourceIntInitializerOutcome(Expressions!Success(literals[index])) \in InitializerOutcomes
        <2>. SUFFICES ASSUME NEW index \in positions
                     PROVE /\ Expressions!Success(literals[index]) \in Expressions!ExpressionOutcomes
                           /\ SourceIntInitializerOutcome(Expressions!Success(literals[index]))
                               = GeneratedIntInitializerOutcome(Expressions!Success(literals[index]))
                           /\ SourceIntInitializerOutcome(Expressions!Success(literals[index])) \in InitializerOutcomes
            BY SMT
        <2>1. Expressions!Success(literals[index]) \in Expressions!ExpressionOutcomes
            BY SMT DEF Expressions!Success, Expressions!ExpressionOutcomes
        <2>. QED BY <2>1, IntExpressionOutcomesSupplyInitializerOutcomes, SMT
    <1>2. InitializerEvaluators(count, sourceEvaluate)
          /\ InitializerEvaluators(count, generatedEvaluate)
        BY <1>1, SMT DEF sourceEvaluate, generatedEvaluate,
            LiteralIntInitializerEvaluators, InitializerEvaluators
    <1>3. \A index \in 1..count :
        [PrefixKeys(order, index - 1) -> Values] \subseteq PartialBindings
        BY SMT DEF PartialBindings, PrefixKeys, InitializationOrder
    <1>4. \A index \in 1..count :
        \A prior \in [PrefixKeys(order, index - 1) -> Values] :
            sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
        BY <1>1, <1>3, SMT DEF sourceEvaluate, generatedEvaluate,
            LiteralIntInitializerEvaluators
    <1>5. /\ \E source : InitializationHistory(FALSE, count, order, sourceEvaluate, source)
          /\ \E generated : InitializationHistory(TRUE, count, order, generatedEvaluate, generated)
        BY <1>2, InitializationHistoriesExist, SMT
    <1>6. \A source, generated :
        (InitializationHistory(FALSE, count, order, sourceEvaluate, source)
         /\ InitializationHistory(TRUE, count, order, generatedEvaluate, generated))
        => /\ \A index \in 0..count : source[index] = generated[index]
           /\ SourceTerminal(source[count], sourceChecks)
                = GeneratedTerminal(generated[count], generatedChecks)
           /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
        <2>. SUFFICES ASSUME NEW source, NEW generated,
                      InitializationHistory(FALSE, count, order, sourceEvaluate, source),
                      InitializationHistory(TRUE, count, order, generatedEvaluate, generated)
                     PROVE /\ \A index \in 0..count : source[index] = generated[index]
                           /\ SourceTerminal(source[count], sourceChecks)
                               = GeneratedTerminal(generated[count], generatedChecks)
                           /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
            BY SMT
        <2>1. \A index \in 0..count : source[index] = generated[index]
            BY <1>2, <1>4, InitializationHistoriesRetainAllStatesAndFailures, SMT
        <2>2. count \in Nat /\ PrefixKeys(order, count) = Keys
            BY SMT DEF InitializationOrder
        <2>3. source[count] \in InitializationResults
            BY <2>2, SMT DEF InitializationHistory
        <2>4. \A index \in 0..count :
            source[index].states \subseteq [PrefixKeys(order, index) -> Values]
            BY <1>2, SourceHistoriesBindEveryPrefixKey, SMT
        <2>5. source[count].states \subseteq [Keys -> Values]
            BY <2>2, <2>4, SMT
        <2>6. \A state \in source[count].states :
            sourceChecks[state] = generatedChecks[state]
            BY <2>5, SMT
        <2>7. SourceTerminal(source[count], sourceChecks)
            = GeneratedTerminal(source[count], generatedChecks)
            BY <2>3, <2>6, TerminalSelectionRetainsEveryStateAndFailure, SMT
        <2>8. SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
            BY <2>5, SMT DEF SourceTerminal, SourceSelectedStates
        <2>9. generated[count] = source[count]
            BY <2>1, <2>2, SMT
        <2>. QED BY <2>1, <2>7, <2>8, <2>9, SMT
    <1>. QED BY <1>5, <1>6

\* Fallback entries only totalize unready reads; scheduled prefixes cannot use them.
ReadyReadInitializerEvaluators(generated, count, positions, readKeys, other) ==
    [index \in 1..count |-> [prior \in PartialBindings |->
        IF index \in positions
        THEN IF readKeys[index] \in DOMAIN prior
             THEN IF generated THEN GeneratedFixed(prior[readKeys[index]])
                  ELSE SourceFixed(prior[readKeys[index]])
             ELSE other[index][prior]
        ELSE other[index][prior]]]

THEOREM ReadyReadInitializersComposeCompleteStatesAndFailures ==
    ASSUME NEW count, NEW order, InitializationOrder(count, order),
           NEW positions \in SUBSET (1..count),
           NEW readKeys \in [positions -> Keys],
           \A index \in positions : readKeys[index] \in PrefixKeys(order, index - 1),
           NEW sourceOther \in [1..count -> [PartialBindings -> InitializerOutcomes]],
           NEW generatedOther \in [1..count -> [PartialBindings -> InitializerOutcomes]],
           \A index \in (1..count) \ positions :
               \A prior \in [PrefixKeys(order, index - 1) -> Values] :
                   sourceOther[index][prior] = generatedOther[index][prior],
           NEW sourceChecks \in [PartialBindings -> SelectionOutcomes],
           NEW generatedChecks \in [PartialBindings -> SelectionOutcomes],
           \A state \in [Keys -> Values] : sourceChecks[state] = generatedChecks[state]
    PROVE LET sourceEvaluate == ReadyReadInitializerEvaluators(FALSE, count, positions, readKeys, sourceOther)
              generatedEvaluate == ReadyReadInitializerEvaluators(TRUE, count, positions, readKeys, generatedOther)
          IN /\ \E source : InitializationHistory(FALSE, count, order, sourceEvaluate, source)
             /\ \E generated : InitializationHistory(TRUE, count, order, generatedEvaluate, generated)
             /\ \A source, generated :
                 (InitializationHistory(FALSE, count, order, sourceEvaluate, source)
                  /\ InitializationHistory(TRUE, count, order, generatedEvaluate, generated))
                 => /\ \A index \in 0..count : source[index] = generated[index]
                    /\ SourceTerminal(source[count], sourceChecks)
                        = GeneratedTerminal(generated[count], generatedChecks)
                    /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
    PROOF
    <1>. DEFINE sourceEvaluate == ReadyReadInitializerEvaluators(FALSE, count, positions, readKeys, sourceOther)
                generatedEvaluate == ReadyReadInitializerEvaluators(TRUE, count, positions, readKeys, generatedOther)
    <1>1. \A prior \in PartialBindings : \A key \in DOMAIN prior :
        /\ SourceFixed(prior[key]) = GeneratedFixed(prior[key])
        /\ SourceFixed(prior[key]) \in InitializerOutcomes
        <2>. SUFFICES ASSUME NEW prior \in PartialBindings, NEW key \in DOMAIN prior
                     PROVE /\ SourceFixed(prior[key]) = GeneratedFixed(prior[key])
                           /\ SourceFixed(prior[key]) \in InitializerOutcomes
            BY SMT
        <2>1. prior \in [DOMAIN prior -> Values]
            BY PartialBindingsHaveSourceTypes
        <2>2. prior[key] \in Values BY <2>1, SMT
        <2>. QED BY <2>2, FixedInitializerRetainsItsOnlyCandidate, SMT
    <1>2. InitializerEvaluators(count, sourceEvaluate)
          /\ InitializerEvaluators(count, generatedEvaluate)
        BY <1>1, SMT DEF sourceEvaluate, generatedEvaluate,
            ReadyReadInitializerEvaluators, InitializerEvaluators
    <1>3. \A index \in positions :
        \A prior \in [PrefixKeys(order, index - 1) -> Values] :
            /\ prior \in PartialBindings
            /\ readKeys[index] \in DOMAIN prior
        BY SMT DEF PartialBindings, PrefixKeys, InitializationOrder
    <1>4. \A index \in 1..count :
        \A prior \in [PrefixKeys(order, index - 1) -> Values] :
            sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                            NEW prior \in [PrefixKeys(order, index - 1) -> Values]
                     PROVE sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
            BY SMT
        <2>1. prior \in PartialBindings
            BY SMT DEF PartialBindings, PrefixKeys, InitializationOrder
        <2>2. CASE index \in positions
            BY <1>1, <1>3, <2>1, <2>2, SMT DEF sourceEvaluate, generatedEvaluate,
                ReadyReadInitializerEvaluators
        <2>3. CASE index \notin positions
            BY <2>1, <2>3, SMT DEF sourceEvaluate, generatedEvaluate,
                ReadyReadInitializerEvaluators
        <2>. QED BY <2>2, <2>3, SMT
    <1>5. /\ \E source : InitializationHistory(FALSE, count, order, sourceEvaluate, source)
          /\ \E generated : InitializationHistory(TRUE, count, order, generatedEvaluate, generated)
        BY <1>2, InitializationHistoriesExist, SMT
    <1>6. \A source, generated :
        (InitializationHistory(FALSE, count, order, sourceEvaluate, source)
         /\ InitializationHistory(TRUE, count, order, generatedEvaluate, generated))
        => /\ \A index \in 0..count : source[index] = generated[index]
           /\ SourceTerminal(source[count], sourceChecks)
                = GeneratedTerminal(generated[count], generatedChecks)
           /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
        <2>. SUFFICES ASSUME NEW source, NEW generated,
                      InitializationHistory(FALSE, count, order, sourceEvaluate, source),
                      InitializationHistory(TRUE, count, order, generatedEvaluate, generated)
                     PROVE /\ \A index \in 0..count : source[index] = generated[index]
                           /\ SourceTerminal(source[count], sourceChecks)
                                = GeneratedTerminal(generated[count], generatedChecks)
                           /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
            BY SMT
        <2>1. \A index \in 0..count : source[index] = generated[index]
            BY <1>2, <1>4, InitializationHistoriesRetainAllStatesAndFailures, SMT
        <2>2. count \in Nat /\ PrefixKeys(order, count) = Keys
            BY SMT DEF InitializationOrder
        <2>3. source[count] \in InitializationResults
            BY <2>2, SMT DEF InitializationHistory
        <2>4. \A index \in 0..count :
            source[index].states \subseteq [PrefixKeys(order, index) -> Values]
            BY <1>2, SourceHistoriesBindEveryPrefixKey, SMT
        <2>5. source[count].states \subseteq [Keys -> Values]
            BY <2>2, <2>4, SMT
        <2>6. \A state \in source[count].states :
            sourceChecks[state] = generatedChecks[state]
            BY <2>5, SMT
        <2>7. SourceTerminal(source[count], sourceChecks)
            = GeneratedTerminal(source[count], generatedChecks)
            BY <2>3, <2>6, TerminalSelectionRetainsEveryStateAndFailure, SMT
        <2>8. SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
            BY <2>5, SMT DEF SourceTerminal, SourceSelectedStates
        <2>9. generated[count] = source[count]
            BY <2>1, <2>2, SMT
        <2>. QED BY <2>1, <2>7, <2>8, <2>9, SMT
    <1>. QED BY <1>5, <1>6

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

THEOREM IntReadDependenciesSupplyReadyInitializerChildren ==
    ASSUME IntInitializationDomains, NEW plan, NEW prior \in PartialBindings,
           PartialIntProjection(prior) \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax],
           NEW state, NEW constructionHeights, NEW constructionStacks,
           Expressions!ExpressionPlan(plan.count, plan.kinds, plan.literals,
               plan.reads, plan.left, plan.right, state),
           Expressions!ExpressionIndexStack(plan.count, plan.kinds, plan.left,
               plan.right, constructionHeights, constructionStacks),
           (Expressions!GeneratedReadDependencies(plan.count, plan.kinds, plan.reads,
               plan.left, plan.right) \cap Keys) \cap (Keys \ (DOMAIN prior)) = {}
    PROVE \E source, generated :
        /\ IntInitializerChildren(plan, prior, source, generated)
        /\ SourceIntInitializerOutcome(source[plan.count])
            = GeneratedIntInitializerOutcome(generated[plan.count])
    PROOF
    <1>1. Expressions!GeneratedReadDependencies(plan.count, plan.kinds, plan.reads,
        plan.left, plan.right) = Expressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads)
        BY Expressions!ConstructedPlanReadDependenciesAreTotalAndExact, SMT
            DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>2. Expressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads) \subseteq IntKeys
        BY SMT DEF Expressions!ExpressionPlan, Expressions!ExpressionReadKeys
    <1>3. Expressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads)
        \subseteq (DOMAIN prior) \cap IntKeys
        BY <1>1, <1>2, SMT DEF IntInitializationDomains
    <1>4. (DOMAIN prior) \cap IntKeys \in SUBSET IntKeys BY SMT
    <1>5. Expressions!CompleteIntBindings((DOMAIN prior) \cap IntKeys, PartialIntProjection(prior))
        \in [IntKeys -> SwiftIntMin..SwiftIntMax]
        BY <1>4, Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
            DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>6. Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
        plan.reads, plan.left, plan.right, (DOMAIN prior) \cap IntKeys, PartialIntProjection(prior))
        BY <1>3, <1>4, <1>5, SMT DEF Expressions!PartialExpressionPlan, Expressions!ExpressionPlan
    <1>7. PICK source, generated :
        /\ Expressions!SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, PartialIntProjection(prior), source)
        /\ Expressions!GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, PartialIntProjection(prior), generated)
        /\ \A index \in 0..plan.count :
            /\ Expressions!OutcomeAgrees(source, generated, index)
            /\ source[index] \in Expressions!ExpressionOutcomes
            /\ generated[index] \in Expressions!ExpressionOutcomes
        BY <1>6, Expressions!PartialOrderedIntExpressionsPreserveValueAndFailure, SMT
            DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>8. IntInitializerChildren(plan, prior, source, generated)
        BY <1>6, <1>7 DEF IntInitializerChildren
    <1>9. SourceIntInitializerOutcome(source[plan.count])
        = GeneratedIntInitializerOutcome(generated[plan.count])
        BY <1>8, IntInitializerChildrenSupplyOutcomeAgreement, SMT
    <1>. QED BY <1>8, <1>9, SMT

THEOREM VisitedSourceSyntaxSuppliesReadyInitializerChildren ==
    ASSUME IntInitializationDomains, NEW prior \in PartialBindings,
           PartialIntProjection(prior) \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax],
           NEW view, NEW emitted, NEW meaning, NEW generated, NEW fallbackRead \in IntKeys,
           Expressions!NodeEmissionArrays(emitted), emitted.count > 0,
           Expressions!AllNodePayloadsMatchSource(view, emitted),
           Expressions!TypedVisitedSourceInputs(view, emitted),
           {emitted.origins[index] : index \in 1..emitted.count} \subseteq DOMAIN view.kinds,
           Expressions!SourceSyntaxHistory(view, PartialIntProjection(prior), meaning),
           LET plan == Expressions!ExtractedNodePlan(emitted, fallbackRead)
           IN /\ Expressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads)
                     \subseteq (DOMAIN prior) \cap IntKeys
              /\ Expressions!GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
                     plan.reads, plan.left, plan.right, PartialIntProjection(prior), generated)
    PROVE LET plan == Expressions!ExtractedNodePlan(emitted, fallbackRead)
              source == Expressions!EmittedSourceSyntaxHistory(emitted, meaning)
          IN /\ IntInitializerChildren(plan, prior, source, generated)
             /\ SourceIntInitializerOutcome(meaning[emitted.origins[emitted.count]])
                     = GeneratedIntInitializerOutcome(generated[plan.count])
    PROOF
    <1>. DEFINE plan == Expressions!ExtractedNodePlan(emitted, fallbackRead)
                source == Expressions!EmittedSourceSyntaxHistory(emitted, meaning)
                bound == (DOMAIN prior) \cap IntKeys
                state == Expressions!CompleteIntBindings(bound, PartialIntProjection(prior))
    <1>0. Expressions!IntegerDomain
        BY SMT DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>. USE <1>0
    <1>1. state \in [IntKeys -> SwiftIntMin..SwiftIntMax]
        BY Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
            DEF state, bound, IntInitializationDomains, Expressions!IntegerDomain
    <1>2. Expressions!ExpressionPlan(plan.count, plan.kinds, plan.literals,
        plan.reads, plan.left, plan.right, state)
        BY <1>1, Expressions!SourceMatchedNodesSupplyTheTypedExpressionPlan, SMT
            DEF plan, Expressions!ExtractedNodePlan
    <1>3. Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
        plan.reads, plan.left, plan.right, bound, PartialIntProjection(prior))
        BY <1>2, SMT DEF plan, state, bound, Expressions!PartialExpressionPlan
    <1>4. /\ Expressions!SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                 plan.reads, plan.left, plan.right, PartialIntProjection(prior), source)
          /\ source[plan.count] = meaning[emitted.origins[emitted.count]]
        BY Expressions!MatchedPostorderNodesRetainIndependentSourceSyntaxMeaning, SMT
            DEF source, plan, Expressions!ExtractedNodePlan
    <1>5. IntInitializerChildren(plan, prior, source, generated)
        BY <1>3, <1>4, SMT DEF IntInitializerChildren, bound, plan
    <1>6. SourceIntInitializerOutcome(source[plan.count])
            = GeneratedIntInitializerOutcome(generated[plan.count])
        BY <1>5, IntInitializerChildrenSupplyOutcomeAgreement
    <1>. QED BY <1>4, <1>5, <1>6, SMT

IntDependencyPlans(intValueTargets, plans, construction, sourceDependencies, generatedDependencies) ==
    \A target \in Keys :
        IF target \in intValueTargets THEN
            /\ Expressions!ExpressionPlan(plans[target].count, plans[target].kinds,
                plans[target].literals, plans[target].reads, plans[target].left,
                plans[target].right, construction[target].state)
            /\ Expressions!ExpressionIndexStack(plans[target].count, plans[target].kinds,
                plans[target].left, plans[target].right,
                construction[target].heights, construction[target].stacks)
            /\ sourceDependencies[target] = Expressions!ExpressionReadKeys(
                plans[target].count, plans[target].kinds, plans[target].reads)
            /\ generatedDependencies[target] = Expressions!GeneratedReadDependencies(
                plans[target].count, plans[target].kinds, plans[target].reads,
                plans[target].left, plans[target].right) \cap Keys
        ELSE sourceDependencies[target] = generatedDependencies[target]

THEOREM IntDependencyPlansSupplyDependencyAgreement ==
    ASSUME IntInitializationDomains, NEW intValueTargets \in SUBSET IntKeys,
           NEW plans, NEW construction,
           NEW sourceDependencies \in [Keys -> SUBSET Keys],
           NEW generatedDependencies \in [Keys -> SUBSET Keys],
           IntDependencyPlans(intValueTargets, plans, construction, sourceDependencies, generatedDependencies)
    PROVE sourceDependencies = generatedDependencies
    PROOF
    <1>1. \A target \in intValueTargets :
        Expressions!GeneratedReadDependencies(plans[target].count, plans[target].kinds,
            plans[target].reads, plans[target].left, plans[target].right)
        = Expressions!ExpressionReadKeys(plans[target].count, plans[target].kinds, plans[target].reads)
        <2>. SUFFICES ASSUME NEW target \in intValueTargets
                     PROVE Expressions!GeneratedReadDependencies(plans[target].count, plans[target].kinds,
                         plans[target].reads, plans[target].left, plans[target].right)
                         = Expressions!ExpressionReadKeys(plans[target].count, plans[target].kinds, plans[target].reads)
            BY SMT
        <2>1. target \in Keys BY SMT DEF IntInitializationDomains
        <2>. QED BY <2>1, Expressions!ConstructedPlanReadDependenciesAreTotalAndExact, SMT
            DEF IntDependencyPlans, IntInitializationDomains, Expressions!IntegerDomain
    <1>2. \A target \in Keys : sourceDependencies[target] = generatedDependencies[target]
        <2>. SUFFICES ASSUME NEW target \in Keys
                     PROVE sourceDependencies[target] = generatedDependencies[target]
            BY SMT
        <2>1. sourceDependencies[target] \subseteq Keys BY SMT
        <2>2. CASE target \in intValueTargets
            <3>1. generatedDependencies[target] = sourceDependencies[target] \cap Keys
                BY <1>1, <2>2, SMT DEF IntDependencyPlans
            <3>. QED BY <2>1, <3>1
        <2>3. CASE target \notin intValueTargets BY <2>3, SMT DEF IntDependencyPlans
        <2>. QED BY <2>2, <2>3, SMT
    <1>. QED BY <1>2, SMT

THEOREM IntReadDependenciesSupplyTheSameStableDependencySchedule ==
    ASSUME IntInitializationDomains, NEW count, NEW declarations,
           InitializationOrder(count, declarations),
           NEW intValueTargets \in SUBSET IntKeys, NEW plans, NEW construction,
           NEW sourceDependencies \in [Keys -> SUBSET Keys],
           NEW generatedDependencies \in [Keys -> SUBSET Keys],
           IntDependencyPlans(intValueTargets, plans, construction, sourceDependencies, generatedDependencies),
           NEW source, NEW generated,
           SourceDependencyOrder(count, declarations, sourceDependencies, source),
           GeneratedDependencyOrder(count, declarations, generatedDependencies, generated)
    PROVE /\ source = generated
          /\ \A step \in 1..count :
              sourceDependencies[source[step]] \subseteq PrefixKeys(source, step - 1)
    PROOF
    <1>1. sourceDependencies = generatedDependencies
        BY IntDependencyPlansSupplyDependencyAgreement, SMT
    <1>2. source = generated
        BY <1>1, StableDependencyOrdersHaveTheSamePrefixes, SMT
    <1>3. \A step \in 1..count :
        sourceDependencies[source[step]] \subseteq PrefixKeys(source, step - 1)
        BY DependencyOrderBindsEveryReadBeforeEvaluation, SMT
    <1>. QED BY <1>2, <1>3

THEOREM RankedIntDependenciesConstructAStableInitializationSchedule ==
    ASSUME IntInitializationDomains, NEW count, NEW declarations,
           InitializationOrder(count, declarations),
           NEW intValueTargets \in SUBSET IntKeys, NEW plans, NEW construction,
           NEW sourceDependencies \in [Keys -> SUBSET Keys],
           NEW generatedDependencies \in [Keys -> SUBSET Keys],
           IntDependencyPlans(intValueTargets, plans, construction, sourceDependencies, generatedDependencies),
           NEW rank \in [Keys -> Nat],
           \A key \in Keys : \A dependency \in sourceDependencies[key] : rank[dependency] < rank[key]
    PROVE \E order, remaining :
        /\ SourceDependencyOrder(count, declarations, sourceDependencies, order)
        /\ GeneratedDependencyOrder(count, declarations, generatedDependencies, order)
        /\ remaining \in [0..count -> SUBSET Keys]
        /\ remaining[0] = Keys /\ remaining[count] = {}
        /\ \A step \in 1..count :
            /\ order[step] \in remaining[step - 1]
            /\ remaining[step] = remaining[step - 1] \ {order[step]}
            /\ sourceDependencies[order[step]] \subseteq PrefixKeys(order, step - 1)
    PROOF
    <1>1. sourceDependencies = generatedDependencies
        BY IntDependencyPlansSupplyDependencyAgreement, SMT
    <1>2. PICK order, remaining :
        /\ SourceDependencyOrder(count, declarations, sourceDependencies, order)
        /\ GeneratedDependencyOrder(count, declarations, sourceDependencies, order)
        /\ remaining \in [0..count -> SUBSET Keys]
        /\ remaining[0] = Keys /\ remaining[count] = {}
        /\ \A step \in 1..count :
            /\ order[step] \in remaining[step - 1]
            /\ remaining[step] = remaining[step - 1] \ {order[step]}
        BY RankedDependenciesConstructACompleteStableOrder, SMT
    <1>3. \A step \in 1..count : sourceDependencies[order[step]] \subseteq PrefixKeys(order, step - 1)
        BY <1>2, DependencyOrderBindsEveryReadBeforeEvaluation, SMT
    <1>. QED BY <1>1, <1>2, <1>3, SMT

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

\* Syntax meanings supply the source history; control rows are concrete fixed seeds.
THEOREM VisitedSourceSyntaxInvokesTheCompleteInitializationParent ==
    ASSUME IntInitializationDomains,
           NEW count, NEW order, NEW sourceEvaluate, NEW generatedEvaluate,
           NEW source, NEW generated, NEW views, NEW roots, NEW visits,
           NEW meanings, NEW executions, NEW positions \in SUBSET (1..count),
           NEW seeds \in [(1..count) \ positions -> Values],
           \A index \in (1..count) \ positions :
               order[index] \in IntKeys => seeds[index] \in SwiftIntMin..SwiftIntMax,
           InitializationOrder(count, order),
           InitializerEvaluators(count, sourceEvaluate), InitializerEvaluators(count, generatedEvaluate),
           InitializationHistory(FALSE, count, order, sourceEvaluate, source),
           InitializationHistory(TRUE, count, order, generatedEvaluate, generated),
           \A index \in 1..count : \A prior \in source[index - 1].states :
               IF index \in positions THEN
                   LET visit == visits[index]
                       emitted == visit.emissions[visit.steps]
                       plan == Expressions!ExtractedNodePlan(emitted, order[index])
                   IN /\ order[index] \in IntKeys
                      /\ Expressions!SynchronizedNodeHistory(visit.steps, roots[index], views[index],
                             visit.heights, visit.pendings, visit.currents, visit.emissions)
                      /\ visit.heights[visit.steps] = 0
                      /\ \A step \in 1..visit.steps :
                             visit.pendings[step - 1][visit.heights[step - 1]].node
                                 \in DOMAIN views[index].kinds
                      /\ Expressions!TypedVisitedSourceInputs(views[index], emitted)
                      /\ {emitted.origins[node] : node \in 1..emitted.count}
                             \subseteq DOMAIN views[index].kinds
                      /\ Expressions!SourceSyntaxHistory(views[index], PartialIntProjection(prior),
                             meanings[index][prior])
                      /\ Expressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads)
                             \subseteq (DOMAIN prior) \cap IntKeys
                      /\ Expressions!ReachedCheckedPostorderExecution(plan, PartialIntProjection(prior),
                             executions[index][prior])
                      /\ sourceEvaluate[index][prior] =
                             SourceIntInitializerOutcome(meanings[index][prior][roots[index]])
                      /\ generatedEvaluate[index][prior] =
                             GeneratedIntInitializerOutcome(executions[index][prior].outcome)
               ELSE /\ sourceEvaluate[index][prior] = SourceFixed(seeds[index])
                    /\ generatedEvaluate[index][prior] = GeneratedFixed(seeds[index])
    PROVE /\ \A index \in 0..count : source[index] = generated[index]
          /\ \E observations :
              /\ SingleBranchInitialObservationHistory(count, order, sourceEvaluate, observations)
              /\ SingleBranchInitialObservationHistory(count, order, generatedEvaluate, observations)
          /\ \A sourceObservation, generatedObservation :
              ((\E observations : SingleBranchInitialObservationHistory(count, order, sourceEvaluate, observations)
                    /\ sourceObservation = observations[count])
               /\ (\E observations : SingleBranchInitialObservationHistory(count, order, generatedEvaluate, observations)
                    /\ generatedObservation = observations[count]))
              => /\ InitialObservation(sourceObservation.stateCount, sourceObservation.stateHistory,
                         sourceObservation.failureCount, sourceObservation.failureHistory)
                       = InitialObservation(generatedObservation.stateCount, generatedObservation.stateHistory,
                           generatedObservation.failureCount, generatedObservation.failureHistory)
                 /\ InitialFirstFailure(sourceObservation.failureCount, sourceObservation.failureHistory)
                       = InitialFirstFailure(generatedObservation.failureCount,
                           generatedObservation.failureHistory)
    PROOF
    <1>. DEFINE emissions == [index \in positions |-> visits[index].emissions[visits[index].steps]]
                plans == [index \in positions |->
                    Expressions!ExtractedNodePlan(emissions[index], order[index])]
                sourceExpressions == [index \in positions |-> [prior \in PartialBindings |->
                    Expressions!EmittedSourceSyntaxHistory(emissions[index], meanings[index][prior])]]
                generatedExpressions == [index \in positions |-> [prior \in PartialBindings |->
                    CHOOSE history : Expressions!GeneratedExpressionHistory(plans[index].count,
                        plans[index].kinds, plans[index].literals, plans[index].reads,
                        plans[index].left, plans[index].right, PartialIntProjection(prior), history)]]
    <1>0. Expressions!IntegerDomain
        BY SMT DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>. USE <1>0
    <1>. DEFINE typedPrefix(index) ==
        \A prior \in source[index].states :
            PartialIntProjection(prior) \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
    <1>0n. count \in Nat BY SMT DEF InitializationOrder
    <1>. USE <1>0n
    <1>0a. typedPrefix(0)
        BY SMT DEF typedPrefix, PartialIntProjection, InitializationHistory, InitialSeed
    <1>0b. \A index \in 1..count :
        ((\A earlier \in 0..(index - 1) : typedPrefix(earlier)) => typedPrefix(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A earlier \in 0..(index - 1) : typedPrefix(earlier),
                             NEW after \in source[index].states
                     PROVE PartialIntProjection(after)
                         \in [(DOMAIN after) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
            BY SMT DEF typedPrefix
        <2>0. index \in Nat /\ index >= 1 /\ typedPrefix(index - 1)
            BY SMT DEF InitializationOrder
        <2>1. PICK prior \in source[index - 1].states,
                   value \in sourceEvaluate[index][prior].candidates :
            SourceExtension(prior, order[index], value, after)
            BY SMT DEF InitializationHistory, InitializationAdvance, SourceAdvance,
                SourceInitialLeaf, SourceInitialStates
        <2>2. prior \in PartialBindings
              /\ PartialIntProjection(prior)
                     \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
            BY <2>0, <2>1, SMT DEF typedPrefix, InitializationHistory,
                InitializationResults, InitializationOrder
        <2>3. order[index] \in IntKeys => value \in SwiftIntMin..SwiftIntMax
            <3>1. CASE index \in positions
                <4>. DEFINE visit == visits[index]
                            emitted == visit.emissions[visit.steps]
                            plan == Expressions!ExtractedNodePlan(emitted, order[index])
                            execution == executions[index][prior]
                <4>1. meanings[index][prior][roots[index]] = execution.outcome
                    BY <2>1, <2>2, <3>1,
                        Expressions!CompletedSyntaxVisitRetainsTheReachedCheckedOutcome, SMT
                        DEF visit, emitted, plan, execution, IntInitializationDomains
                <4>2. emitted.count > 0 /\ plan.count = emitted.count
                    BY <2>1, <3>1, Expressions!SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot, SMT
                        DEF visit, emitted, plan, Expressions!ExtractedNodePlan
                <4>3. /\ execution.outcome.ok
                      /\ value = execution.outcome.value
                    BY <2>1, <3>1, <4>1, SMT
                        DEF SourceIntInitializerOutcome, SourceFixed, SourceFailed, execution
                <4>4. /\ execution.completed = plan.count
                      /\ execution.outcome = Expressions!Success(execution.values[plan.count])
                      /\ execution.values \in [1..plan.count -> SwiftIntMin..SwiftIntMax]
                    BY <2>1, <3>1, <4>3, SMT
                        DEF visit, emitted, plan, execution, Expressions!ReachedCheckedPostorderExecution
                <4>. QED BY <4>2, <4>3, <4>4, SMT DEF Expressions!Success
            <3>2. CASE index \notin positions
                BY <2>1, <3>2, SMT DEF SourceFixed
            <3>. QED BY <3>1, <3>2, SMT
        <2>. QED BY <2>1, <2>2, <2>3, SMT DEF PartialIntProjection, SourceExtension
    <1>0c. \A index \in 0..count : typedPrefix(index)
        BY <1>0n, <1>0a, <1>0b, FiniteIndexedPrefixProperty
    <1>0d. \A index \in 1..count : \A prior \in source[index - 1].states :
        PartialIntProjection(prior) \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
        BY <1>0c, SMT DEF typedPrefix, InitializationOrder
    <1>. USE <1>0d
    <1>1. \A index \in 1..count : \A prior \in source[index - 1].states :
        IF index \in positions
        THEN /\ order[index] \in IntKeys
             /\ IntInitializerChildren(plans[index], prior,
                    sourceExpressions[index][prior], generatedExpressions[index][prior])
             /\ sourceEvaluate[index][prior] =
                    SourceIntInitializerOutcome(sourceExpressions[index][prior][plans[index].count])
             /\ generatedEvaluate[index][prior] =
                    GeneratedIntInitializerOutcome(generatedExpressions[index][prior][plans[index].count])
        ELSE sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
        <2>. SUFFICES ASSUME NEW index \in 1..count, NEW prior \in source[index - 1].states
                     PROVE IF index \in positions
                         THEN /\ order[index] \in IntKeys
                              /\ IntInitializerChildren(plans[index], prior,
                                     sourceExpressions[index][prior], generatedExpressions[index][prior])
                              /\ sourceEvaluate[index][prior] = SourceIntInitializerOutcome(
                                     sourceExpressions[index][prior][plans[index].count])
                              /\ generatedEvaluate[index][prior] = GeneratedIntInitializerOutcome(
                                     generatedExpressions[index][prior][plans[index].count])
                         ELSE sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
            BY SMT
        <2>0. prior \in PartialBindings
            BY SMT DEF InitializationHistory, InitializationResults, InitializationOrder
        <2>1. CASE index \in positions
            <3>0a. Expressions!SynchronizedNodeHistory(visits[index].steps, roots[index], views[index],
                visits[index].heights, visits[index].pendings, visits[index].currents, visits[index].emissions)
                  /\ visits[index].heights[visits[index].steps] = 0
                BY <2>1, SMT
            <3>0b. \A step \in 0..visits[index].steps :
                /\ Expressions!NodeEmissionArrays(visits[index].emissions[step])
                /\ Expressions!AllNodePayloadsMatchSource(views[index], visits[index].emissions[step])
                BY <3>0a, Expressions!SynchronizedNodeHistoryPreservesEverySourcePayload, SMT
            <3>0. /\ Expressions!NodeEmissionArrays(emissions[index])
                  /\ emissions[index].count > 0
                  /\ emissions[index].origins[emissions[index].count] = roots[index]
                  /\ Expressions!AllNodePayloadsMatchSource(views[index], emissions[index])
                BY <2>1, <3>0a, <3>0b,
                    Expressions!SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot, SMT
                    DEF emissions, Expressions!SynchronizedNodeHistory, Expressions!PendingVisitHistory
            <3>1. Expressions!PartialExpressionPlan(plans[index].count, plans[index].kinds,
                plans[index].literals, plans[index].reads, plans[index].left, plans[index].right,
                (DOMAIN prior) \cap IntKeys, PartialIntProjection(prior))
                BY <2>1, <3>0, Expressions!SourceMatchedNodesSupplyTheTypedExpressionPlan,
                    Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
                    DEF plans, IntInitializationDomains, Expressions!IntegerDomain,
                        Expressions!PartialExpressionPlan
            <3>2. \E history : Expressions!GeneratedExpressionHistory(plans[index].count,
                plans[index].kinds, plans[index].literals, plans[index].reads,
                plans[index].left, plans[index].right, PartialIntProjection(prior), history)
                BY <3>1, Expressions!PartialOrderedIntExpressionsPreserveValueAndFailure, SMT
                    DEF IntInitializationDomains, Expressions!IntegerDomain
            <3>3. Expressions!GeneratedExpressionHistory(plans[index].count,
                plans[index].kinds, plans[index].literals, plans[index].reads,
                plans[index].left, plans[index].right, PartialIntProjection(prior),
                generatedExpressions[index][prior])
                BY <2>1, <2>0, <3>2, SMT DEF generatedExpressions
            <3>4. /\ IntInitializerChildren(plans[index], prior,
                         sourceExpressions[index][prior], generatedExpressions[index][prior])
                  /\ SourceIntInitializerOutcome(meanings[index][prior][roots[index]])
                         = GeneratedIntInitializerOutcome(generatedExpressions[index][prior][plans[index].count])
                BY <2>0, <2>1, <3>0, <3>3, VisitedSourceSyntaxSuppliesReadyInitializerChildren, SMT
                    DEF emissions, plans, sourceExpressions
            <3>5. meanings[index][prior][roots[index]] = executions[index][prior].outcome
                BY <2>1, Expressions!CompletedSyntaxVisitRetainsTheReachedCheckedOutcome, SMT
                    DEF IntInitializationDomains, Expressions!IntegerDomain
            <3>6. sourceExpressions[index][prior][plans[index].count] \in Expressions!ExpressionOutcomes
                BY <3>4, Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
                    DEF IntInitializerChildren, Expressions!PartialExpressionPlan,
                        Expressions!ExpressionPlan, IntInitializationDomains, Expressions!IntegerDomain
            <3>7. SourceIntInitializerOutcome(meanings[index][prior][roots[index]])
                    = GeneratedIntInitializerOutcome(executions[index][prior].outcome)
                BY <2>0, <2>1, <3>0, <3>5, <3>6, IntExpressionOutcomesSupplyInitializerOutcomes, SMT
                    DEF plans, sourceExpressions, Expressions!ExtractedNodePlan,
                        Expressions!EmittedSourceSyntaxHistory
            <3>. QED BY <2>0, <2>1, <3>0, <3>4, <3>7, SMT DEF emissions, plans, sourceExpressions,
                Expressions!ExtractedNodePlan, Expressions!EmittedSourceSyntaxHistory
        <2>2. CASE index \notin positions
            BY <2>2, FixedInitializerRetainsItsOnlyCandidate, SMT
        <2>. QED BY <2>1, <2>2, SMT
    <1>2. \A index \in 0..count : source[index] = generated[index]
        BY <1>1, OrderedIntInitializerChildrenComposeAllReachableStatesAndFailures, SMT
    <1>2a. \A index \in 1..count : \A prior \in source[index - 1].states :
        sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
        BY <1>1, IntInitializerChildrenSupplyOutcomeAgreement, SMT
    <1>2b. \A index \in 1..count : \A prior \in source[index - 1].states :
        sourceEvaluate[index][prior].firstFailure = NoFailure
            => \E value \in Values : sourceEvaluate[index][prior].candidates = {value}
        <2>. SUFFICES ASSUME NEW index \in 1..count, NEW prior \in source[index - 1].states
                     PROVE sourceEvaluate[index][prior].firstFailure = NoFailure
                         => \E value \in Values : sourceEvaluate[index][prior].candidates = {value}
            BY SMT
        <2>1. CASE index \in positions
            <3>1. sourceExpressions[index][prior][plans[index].count]
                    \in Expressions!ExpressionOutcomes
                BY <1>1, <2>1, Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
                    DEF IntInitializerChildren, Expressions!PartialExpressionPlan,
                        Expressions!ExpressionPlan, IntInitializationDomains, Expressions!IntegerDomain
            <3>. QED BY <1>1, <2>1, <3>1, SMT
                DEF SourceIntInitializerOutcome, Expressions!ExpressionOutcomes,
                    SourceFixed, SourceFailed, IntInitializationDomains
        <2>2. CASE index \notin positions
            BY <2>2, SMT DEF SourceFixed
        <2>. QED BY <2>1, <2>2, SMT
    <1>2c. PICK observations :
        /\ SingleBranchInitialObservationHistory(count, order, sourceEvaluate, observations)
        /\ \A index \in 0..count : InitialSetProjection(observations[index]) = source[index]
        BY <1>2b, DeterministicReachableInitializersConstructTheirOrderedObservations
    <1>2d. \A index \in 0..count :
        /\ InitialObservationIsTyped(observations[index])
        /\ observations[index].stateCount <= 1 /\ observations[index].failureCount <= 1
        /\ observations[index].stateCount + observations[index].failureCount = 1
        BY <1>2c, SingleBranchInitializationDerivesItsObservationBounds
    <1>2e. SingleBranchInitialObservationHistory(count, order, generatedEvaluate, observations)
        BY <1>2a, <1>2c, <1>2d, SMT
            DEF SingleBranchInitialObservationHistory, SingleBranchInitialObservationStep,
                InitialSetProjection, InitializationOrder
    <1>2f. \E observations :
        /\ SingleBranchInitialObservationHistory(count, order, sourceEvaluate, observations)
        /\ SingleBranchInitialObservationHistory(count, order, generatedEvaluate, observations)
        BY <1>2c, <1>2e, SMT
    <1>3. \A isGenerated \in BOOLEAN : \A observations :
        LET evaluate == IF isGenerated THEN generatedEvaluate ELSE sourceEvaluate
            actual == IF isGenerated THEN generated ELSE source
        IN SingleBranchInitialObservationHistory(count, order, evaluate, observations)
           => /\ InitialSetProjection(observations[count]) = actual[count]
              /\ InitialObservationIsTyped(observations[count])
              /\ observations[count].stateCount <= 1 /\ observations[count].failureCount <= 1
        <2>. SUFFICES ASSUME NEW isGenerated \in BOOLEAN, NEW observations,
                             SingleBranchInitialObservationHistory(count, order,
                                 IF isGenerated THEN generatedEvaluate ELSE sourceEvaluate, observations)
                     PROVE LET actual == IF isGenerated THEN generated ELSE source
                           IN /\ InitialSetProjection(observations[count]) = actual[count]
                              /\ InitialObservationIsTyped(observations[count])
                              /\ observations[count].stateCount <= 1 /\ observations[count].failureCount <= 1
            BY SMT
        <2>. DEFINE evaluate == IF isGenerated THEN generatedEvaluate ELSE sourceEvaluate
                    actual == IF isGenerated THEN generated ELSE source
                    projected == [index \in 0..count |-> InitialSetProjection(observations[index])]
        <2>1. InitializationHistory(isGenerated, count, order, evaluate, projected)
            BY SingleBranchObservationsSupplyTheirSetInitializationHistory, SMT DEF evaluate, projected
        <2>2. InitializationHistory(isGenerated, count, order, evaluate, actual)
            BY SMT DEF evaluate, actual
        <2>3. \A index \in 0..count : projected[index] = actual[index]
            BY <2>1, <2>2, InitializationHistoryIsUnique
        <2>4. /\ InitialObservationIsTyped(observations[count])
              /\ observations[count].stateCount <= 1 /\ observations[count].failureCount <= 1
            BY SingleBranchInitializationDerivesItsObservationBounds, SMT DEF evaluate, InitializationOrder
        <2>. QED BY <2>3, <2>4, SMT DEF actual, projected, InitializationOrder
    <1>4. \A sourceObservation, generatedObservation :
        ((\E observations : SingleBranchInitialObservationHistory(count, order, sourceEvaluate, observations)
              /\ sourceObservation = observations[count])
         /\ (\E observations : SingleBranchInitialObservationHistory(count, order, generatedEvaluate, observations)
              /\ generatedObservation = observations[count]))
        => /\ InitialObservation(sourceObservation.stateCount, sourceObservation.stateHistory,
                   sourceObservation.failureCount, sourceObservation.failureHistory)
                 = InitialObservation(generatedObservation.stateCount, generatedObservation.stateHistory,
                     generatedObservation.failureCount, generatedObservation.failureHistory)
           /\ InitialFirstFailure(sourceObservation.failureCount, sourceObservation.failureHistory)
                 = InitialFirstFailure(generatedObservation.failureCount, generatedObservation.failureHistory)
        BY <1>2, <1>3, SingletonInitialObservationsRetainOrderMultiplicityAndFirstFailure, SMT
            DEF InitializationOrder, InitialObservation
    <1>. QED BY <1>2, <1>2f, <1>4

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

SourceIntDomainInitialLeaf(prior, target, outcome) ==
    SourceTypedInitialLeaf(prior, target, SwiftIntMin..SwiftIntMax, outcome)
GeneratedIntDomainInitialLeaf(prior, target, outcome) ==
    GeneratedTypedInitialLeaf(prior, target, SwiftIntMin..SwiftIntMax, outcome)

THEOREM MathematicalIntDomainsRetainAllTypedInitialStatesAndFailures ==
    ASSUME IntInitializationDomains,
           NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW target \in IntKeys \ bound, NEW universe,
           NEW outcome \in [candidates: SUBSET universe,
                             firstFailure: FailureValues \cup {NoFailure}],
           outcome.firstFailure # NoFailure => outcome.candidates = {}
    PROVE SourceIntDomainInitialLeaf(prior, target, outcome)
        = GeneratedIntDomainInitialLeaf(prior, target, outcome)
    PROOF
    <1>1. /\ target \in Keys \ bound
          /\ SwiftIntMin..SwiftIntMax \in SUBSET Values
        BY SMT DEF IntInitializationDomains
    <1>2. SourceTypedInitialLeaf(prior, target, SwiftIntMin..SwiftIntMax, outcome)
            = GeneratedTypedInitialLeaf(prior, target, SwiftIntMin..SwiftIntMax, outcome)
        BY <1>1, TypedInitializerRetainsCompleteStatesAndFailures, SMT
    <1>. QED BY <1>2 DEF SourceIntDomainInitialLeaf, GeneratedIntDomainInitialLeaf

\* This is the complete logical initial relation; eager native enumeration is unavailable.
SourceIntegerSetInitialLeaf(prior, target) ==
    SourceIntDomainInitialLeaf(prior, target, SourceDomain(Membership!SourceIntegerDomain.value))
GeneratedIntegerSetInitialLeaf(prior, target) ==
    GeneratedInitialLeaf(prior, target,
        [candidates |-> {candidate \in SwiftIntMin..SwiftIntMax :
                            Membership!NativeIntegerDomain.value[candidate]},
         firstFailure |-> NoFailure])

THEOREM IntegerSetConstructorSuppliesEveryTypedInitialState ==
    ASSUME IntInitializationDomains,
           NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW target \in IntKeys \ bound
    PROVE /\ SourceIntegerSetInitialLeaf(prior, target)
                = GeneratedIntegerSetInitialLeaf(prior, target)
          /\ SourceIntegerSetInitialLeaf(prior, target).states
                = {GeneratedExtension(prior, target, candidate) : candidate \in SwiftIntMin..SwiftIntMax}
          /\ SourceIntegerSetInitialLeaf(prior, target).failures = {}
    PROOF
    <1>1. /\ Membership!SourceIntegerDomain.value = Int
          /\ {candidate \in SwiftIntMin..SwiftIntMax :
                  Membership!NativeIntegerDomain.value[candidate]} = SwiftIntMin..SwiftIntMax
        BY SMT DEF Membership!SourceIntegerDomain, Membership!NativeIntegerDomain,
            Membership!QueryValue, IntInitializationDomains
    <1>2. SourceIntDomainInitialLeaf(prior, target, SourceDomain(Int))
            = GeneratedIntDomainInitialLeaf(prior, target, SourceDomain(Int))
        PROOF
        <2>1. TypedInitializerOutcome(SwiftIntMin..SwiftIntMax, SourceDomain(Int))
                = SourceDomain(SwiftIntMin..SwiftIntMax)
            BY SMT DEF TypedInitializerOutcome, SourceDomain, IntInitializationDomains
        <2>2. SourceIntDomainInitialLeaf(prior, target, SourceDomain(Int))
                = SourceInitialLeaf(prior, target,
                    TypedInitializerOutcome(SwiftIntMin..SwiftIntMax, SourceDomain(Int)))
            BY SMT DEF SourceIntDomainInitialLeaf, SourceTypedInitialLeaf,
                SourceInitialLeaf, SourceInitialStates, SourceInitialFailures,
                SourceExtension, TypedInitializerOutcome
        <2>3. TypedInitializerOutcome(SwiftIntMin..SwiftIntMax, SourceDomain(Int))
                \in InitializerOutcomes
            BY <2>1, SMT DEF SourceDomain, InitializerOutcomes, IntInitializationDomains
        <2>4. SourceInitialLeaf(prior, target,
                    TypedInitializerOutcome(SwiftIntMin..SwiftIntMax, SourceDomain(Int)))
                = GeneratedInitialLeaf(prior, target,
                    TypedInitializerOutcome(SwiftIntMin..SwiftIntMax, SourceDomain(Int)))
            BY <2>3, InitializerLeafRetainsCompleteStatesAndFailures, SMT
                DEF IntInitializationDomains
        <2>. QED BY <2>2, <2>4 DEF GeneratedIntDomainInitialLeaf, GeneratedTypedInitialLeaf
    <1>3. GeneratedIntDomainInitialLeaf(prior, target, SourceDomain(Int))
            = GeneratedIntegerSetInitialLeaf(prior, target)
        PROOF
        <2>1. TypedInitializerOutcome(SwiftIntMin..SwiftIntMax, SourceDomain(Int))
                = SourceDomain(SwiftIntMin..SwiftIntMax)
            BY SMT DEF TypedInitializerOutcome, SourceDomain, IntInitializationDomains
        <2>2. GeneratedIntDomainInitialLeaf(prior, target, SourceDomain(Int))
                = GeneratedInitialLeaf(prior, target, SourceDomain(SwiftIntMin..SwiftIntMax))
            BY <2>1, SMT DEF GeneratedIntDomainInitialLeaf, GeneratedTypedInitialLeaf
        <2>3. GeneratedIntegerSetInitialLeaf(prior, target)
                = GeneratedInitialLeaf(prior, target, SourceDomain(SwiftIntMin..SwiftIntMax))
            BY <1>1, SMT DEF GeneratedIntegerSetInitialLeaf, SourceDomain
        <2>. QED BY <2>2, <2>3, SMT
    <1>4. SourceIntegerSetInitialLeaf(prior, target)
            = GeneratedIntegerSetInitialLeaf(prior, target)
        BY <1>1, <1>2, <1>3, SMT DEF SourceIntegerSetInitialLeaf
    <1>5. /\ GeneratedIntegerSetInitialLeaf(prior, target).states
                = {GeneratedExtension(prior, target, candidate) : candidate \in SwiftIntMin..SwiftIntMax}
          /\ GeneratedIntegerSetInitialLeaf(prior, target).failures = {}
        BY <1>1, SMT DEF GeneratedIntegerSetInitialLeaf, GeneratedInitialLeaf,
            GeneratedInitialStates, GeneratedInitialFailures
    <1>. QED BY <1>4, <1>5, SMT

THEOREM EmptyEnumerationIsNotTheMathematicalInitialRelation ==
    ASSUME IntInitializationDomains,
           NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW target \in IntKeys \ bound
    PROVE SourceIntegerSetInitialLeaf(prior, target)
        # GeneratedInitialLeaf(prior, target, GeneratedDomain({}))
    PROOF
    <1>1. GeneratedExtension(prior, target, 0) \in SourceIntegerSetInitialLeaf(prior, target).states
        BY IntegerSetConstructorSuppliesEveryTypedInitialState, SMT DEF IntInitializationDomains
    <1>2. GeneratedInitialLeaf(prior, target, GeneratedDomain({})).states = {}
        BY SMT DEF GeneratedInitialLeaf, GeneratedInitialStates, GeneratedDomain
    <1>. QED BY <1>1, <1>2, SMT

SourceDeclaredIntState(value) == value \in SwiftIntMin..SwiftIntMax
GeneratedDeclaredIntState(value, fastMinimum, fastMaximum) ==
    IF value >= fastMinimum /\ value <= fastMaximum THEN TRUE
    ELSE value \in SwiftIntMin..SwiftIntMax

THEOREM FastRepresentationPredicateKeepsEveryDeclaredIntState ==
    ASSUME IntInitializationDomains,
           NEW fastMinimum \in Int, NEW fastMaximum \in Int,
           SwiftIntMin <= fastMinimum, fastMinimum <= fastMaximum,
           fastMaximum <= SwiftIntMax, NEW value \in Int
    PROVE SourceDeclaredIntState(value)
        = GeneratedDeclaredIntState(value, fastMinimum, fastMaximum)
    BY SMT DEF SourceDeclaredIntState, GeneratedDeclaredIntState,
        IntInitializationDomains

=============================================================================
