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
    <1>1. state \in [IntKeys -> SwiftIntMin..SwiftIntMax]
        BY <1>0, Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
            DEF state, bound, IntInitializationDomains, Expressions!IntegerDomain
    <1>1a. /\ fallbackRead \in IntKeys
           /\ Expressions!NodeEmissionArrays(emitted) /\ emitted.count > 0
           /\ Expressions!AllNodePayloadsMatchSource(view, emitted)
           /\ Expressions!TypedVisitedSourceInputs(view, emitted)
        BY SMT
    <1>2. Expressions!ExpressionPlan(plan.count, plan.kinds, plan.literals,
        plan.reads, plan.left, plan.right, state)
        BY <1>0, <1>1, <1>1a, Expressions!SourceMatchedNodesSupplyTheTypedExpressionPlan, SMT
            DEF plan
    <1>3. Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
        plan.reads, plan.left, plan.right, bound, PartialIntProjection(prior))
        BY <1>2, SMT DEF plan, state, bound, Expressions!PartialExpressionPlan
    <1>4. /\ Expressions!SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                 plan.reads, plan.left, plan.right, PartialIntProjection(prior), source)
          /\ source[plan.count] = meaning[emitted.origins[emitted.count]]
        BY <1>0, Expressions!MatchedPostorderNodesRetainIndependentSourceSyntaxMeaning, SMT
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

\* Denotations of the emitted TLA scalar terms; values after overflow are not executions.
RenderedIntValueHistory(plan, state, values) ==
    /\ values \in [1..plan.count -> Int]
    /\ \A index \in 1..plan.count : values[index] =
        IF plan.kinds[index] = "literal" THEN plan.literals[index]
        ELSE IF plan.kinds[index] = "read" THEN state[plan.reads[index]]
        ELSE values[plan.left[index]] + values[plan.right[index]]

RenderedIntGuard(plan, values, index) ==
    IF plan.kinds[index] = "add"
    THEN Expressions!GeneratedAddDefined(values[plan.left[index]], values[plan.right[index]])
    ELSE TRUE

RenderedInitialAdditionEvents(plan, values, prior, target) ==
    UNION {IF plan.kinds[index] = "add"
              /\ (\A earlier \in 1..(index - 1) : RenderedIntGuard(plan, values, earlier))
              /\ ~RenderedIntGuard(plan, values, index)
           THEN {[before |-> prior, site |-> target, kind |-> "integerOverflow.addition",
                  operands |-> <<values[plan.left[index]], values[plan.right[index]]>>]}
           ELSE {} : index \in 1..plan.count}

\* Site and preceding-binding identity decoding are separate physical obligations.
DecodedRenderedAdditionEvents(events) ==
    {[before |-> event.before, site |-> event.site,
      payload |-> <<"integerOverflow", "addition", event.operands>>] :
        event \in {entry \in events : entry.kind = "integerOverflow.addition"}}

\* The actual record uses declaration ordinals and a tuple of named prefix entries.
RenderedInitialRecordLayout(names, ordinals) ==
    /\ DOMAIN names = Keys
    /\ ordinals \in [Keys -> Nat]
    /\ \A first, second \in Keys : names[first] = names[second] => first = second
    /\ \A first, second \in Keys : ordinals[first] = ordinals[second] => first = second

RenderedInitialPrefixOrder(length, order, prior) ==
    /\ length \in Nat
    /\ order \in [1..length -> DOMAIN prior]
    /\ {order[index] : index \in 1..length} = DOMAIN prior
    /\ \A first, second \in 1..length : order[first] = order[second] => first = second

RenderedInitialPrefixEntries(length, order, names, prior) ==
    [index \in 1..length |-> [name |-> names[order[index]], value |-> prior[order[index]]]]

DecodedRenderedPrefixEntries(entries, names) ==
    [key \in {key \in DOMAIN names :
        \E index \in DOMAIN entries : entries[index].name = names[key]} |->
        entries[CHOOSE index \in DOMAIN entries : entries[index].name = names[key]].value]

DecodedRenderedInitializerSite(site, ordinals) ==
    CHOOSE key \in DOMAIN ordinals : ordinals[key] = site

THEOREM RenderedInitialPrefixAndSiteDecodingRetainsEveryIdentity ==
    ASSUME NEW prior \in PartialBindings, NEW length, NEW order, NEW names, NEW ordinals,
           RenderedInitialRecordLayout(names, ordinals),
           RenderedInitialPrefixOrder(length, order, prior)
    PROVE /\ DecodedRenderedPrefixEntries(
                 RenderedInitialPrefixEntries(length, order, names, prior), names) = prior
          /\ \A target \in Keys :
                 DecodedRenderedInitializerSite(ordinals[target], ordinals) = target
    PROOF
    <1>. DEFINE entries == RenderedInitialPrefixEntries(length, order, names, prior)
    <1>. HIDE DEF entries
    <1>0. /\ DOMAIN prior \subseteq Keys
          /\ DOMAIN entries = 1..length
          /\ DOMAIN names = Keys /\ DOMAIN ordinals = Keys
        BY SMT DEF PartialBindings, RenderedInitialRecordLayout,
            RenderedInitialPrefixOrder, entries, RenderedInitialPrefixEntries
    <1>1. \A index \in 1..length :
        /\ order[index] \in DOMAIN prior
        /\ entries[index].name = names[order[index]]
        /\ entries[index].value = prior[order[index]]
        BY SMT DEF RenderedInitialPrefixOrder, entries, RenderedInitialPrefixEntries
    <1>2. \A key \in Keys :
        (\E index \in 1..length : entries[index].name = names[key]) <=> key \in DOMAIN prior
        BY <1>0, <1>1, SMT DEF RenderedInitialRecordLayout, RenderedInitialPrefixOrder
    <1>3. \A key \in DOMAIN prior :
        LET selected == CHOOSE index \in DOMAIN entries : entries[index].name = names[key]
        IN /\ selected \in 1..length
           /\ order[selected] = key
           /\ entries[selected].value = prior[key]
        BY <1>0, <1>1, <1>2, SMT DEF RenderedInitialRecordLayout
    <1>4. DecodedRenderedPrefixEntries(entries, names) = prior
        <2>1. {key \in DOMAIN names :
            \E index \in DOMAIN entries : entries[index].name = names[key]} = DOMAIN prior
            BY <1>0, <1>2, SetExtensionality, SMT
        <2>2. DecodedRenderedPrefixEntries(entries, names)
            = [key \in DOMAIN prior |->
                entries[CHOOSE index \in DOMAIN entries : entries[index].name = names[key]].value]
            BY ONLY <2>1, SMT DEF DecodedRenderedPrefixEntries
        <2>3. \A key \in DOMAIN prior :
            entries[CHOOSE index \in DOMAIN entries : entries[index].name = names[key]].value = prior[key]
            BY <1>3, SMT
        <2>4. DecodedRenderedPrefixEntries(entries, names) = [key \in DOMAIN prior |-> prior[key]]
            BY <2>2, <2>3, SMT
        <2>5. prior \in [DOMAIN prior -> Values]
            BY SMT DEF PartialBindings
        <2>. QED BY <2>4, <2>5, SMT
    <1>5. \A target \in Keys :
        /\ \E key \in DOMAIN ordinals : ordinals[key] = ordinals[target]
        /\ \A key \in DOMAIN ordinals : ordinals[key] = ordinals[target] => key = target
        BY <1>0, SMT DEF RenderedInitialRecordLayout
    <1>6. \A target \in Keys :
        DecodedRenderedInitializerSite(ordinals[target], ordinals) = target
        BY <1>5, SMT DEF DecodedRenderedInitializerSite
    <1>. QED BY <1>4, <1>6, SMT DEF entries

DecodedNamedRenderedAdditionEvents(events, names, ordinals) ==
    {[before |-> DecodedRenderedPrefixEntries(event.before, names),
      site |-> DecodedRenderedInitializerSite(event.site, ordinals),
      payload |-> <<"integerOverflow", "addition", event.operands>>] :
        event \in {entry \in events : entry.kind = "integerOverflow.addition"}}

THEOREM RenderedAdditionRecordDecodingRetainsCompleteObservations ==
    ASSUME NEW plan, NEW values, NEW prior \in PartialBindings, NEW target \in Keys,
           NEW length, NEW order, NEW names, NEW ordinals,
           RenderedInitialRecordLayout(names, ordinals),
           RenderedInitialPrefixOrder(length, order, prior)
    PROVE DecodedNamedRenderedAdditionEvents(
              RenderedInitialAdditionEvents(plan, values,
                  RenderedInitialPrefixEntries(length, order, names, prior), ordinals[target]),
              names, ordinals)
        = DecodedRenderedAdditionEvents(RenderedInitialAdditionEvents(plan, values, prior, target))
    PROOF
    <1>. DEFINE entries == RenderedInitialPrefixEntries(length, order, names, prior)
                fires(index) == plan.kinds[index] = "add"
                    /\ (\A earlier \in 1..(index - 1) : RenderedIntGuard(plan, values, earlier))
                    /\ ~RenderedIntGuard(plan, values, index)
                named(index) == IF fires(index)
                    THEN {[before |-> entries, site |-> ordinals[target], kind |-> "integerOverflow.addition",
                           operands |-> <<values[plan.left[index]], values[plan.right[index]]>>]}
                    ELSE {}
                logical(index) == IF fires(index)
                    THEN {[before |-> prior, site |-> target, kind |-> "integerOverflow.addition",
                           operands |-> <<values[plan.left[index]], values[plan.right[index]]>>]}
                    ELSE {}
    <1>. HIDE DEF entries, named, logical
    <1>1. /\ DecodedRenderedPrefixEntries(entries, names) = prior
          /\ DecodedRenderedInitializerSite(ordinals[target], ordinals) = target
        BY RenderedInitialPrefixAndSiteDecodingRetainsEveryIdentity, SMT DEF entries
    <1>2. \A index \in 1..plan.count :
        DecodedNamedRenderedAdditionEvents(named(index), names, ordinals)
            = DecodedRenderedAdditionEvents(logical(index))
        BY <1>1, SMT DEF named, logical, DecodedNamedRenderedAdditionEvents,
            DecodedRenderedAdditionEvents
    <1>3. \A groups : DecodedNamedRenderedAdditionEvents(UNION groups, names, ordinals)
        = UNION {DecodedNamedRenderedAdditionEvents(events, names, ordinals) : events \in groups}
        BY SetExtensionality, SMT DEF DecodedNamedRenderedAdditionEvents
    <1>4. \A groups : DecodedRenderedAdditionEvents(UNION groups)
        = UNION {DecodedRenderedAdditionEvents(events) : events \in groups}
        BY SetExtensionality, SMT DEF DecodedRenderedAdditionEvents
    <1>5. /\ RenderedInitialAdditionEvents(plan, values, entries, ordinals[target])
                 = UNION {named(index) : index \in 1..plan.count}
          /\ RenderedInitialAdditionEvents(plan, values, prior, target)
                 = UNION {logical(index) : index \in 1..plan.count}
        BY SMT DEF RenderedInitialAdditionEvents, named, logical, fires
    <1>6. DecodedNamedRenderedAdditionEvents(UNION {named(index) : index \in 1..plan.count}, names, ordinals)
        = UNION {DecodedNamedRenderedAdditionEvents(named(index), names, ordinals) : index \in 1..plan.count}
        BY <1>3, SetExtensionality, SMT
    <1>7. UNION {DecodedNamedRenderedAdditionEvents(named(index), names, ordinals) : index \in 1..plan.count}
        = UNION {DecodedRenderedAdditionEvents(logical(index)) : index \in 1..plan.count}
        BY <1>2, SetExtensionality, SMT
    <1>8. DecodedRenderedAdditionEvents(UNION {logical(index) : index \in 1..plan.count})
        = UNION {DecodedRenderedAdditionEvents(logical(index)) : index \in 1..plan.count}
        BY <1>4, SetExtensionality, SMT
    <1>9. DecodedNamedRenderedAdditionEvents(UNION {named(index) : index \in 1..plan.count}, names, ordinals)
        = DecodedRenderedAdditionEvents(UNION {logical(index) : index \in 1..plan.count})
        BY ONLY <1>6, <1>7, <1>8, SMT
    <1>10. DecodedNamedRenderedAdditionEvents(
        RenderedInitialAdditionEvents(plan, values, entries, ordinals[target]), names, ordinals)
        = DecodedRenderedAdditionEvents(RenderedInitialAdditionEvents(plan, values, prior, target))
        BY ONLY <1>5, <1>9, SMT
    <1>. QED BY ONLY <1>10, SMT DEF entries

NamedRenderedInitialLeaf(plan, values, outcome, prior, target, length, order, names, ordinals) ==
    [states |-> IF outcome.ok THEN {GeneratedExtension(prior, target, values[plan.count])} ELSE {},
     failures |-> DecodedNamedRenderedAdditionEvents(
         RenderedInitialAdditionEvents(plan, values,
             RenderedInitialPrefixEntries(length, order, names, prior), ordinals[target]), names, ordinals)]

RenderedInitialRecordInterpretation(plan, values, outcome, prior, target, leaf) ==
    \A length, order, names, ordinals :
        (RenderedInitialRecordLayout(names, ordinals) /\ RenderedInitialPrefixOrder(length, order, prior))
        => leaf = NamedRenderedInitialLeaf(plan, values, outcome, prior, target, length, order, names, ordinals)

RenderedInitialLeafWitness(plan, state, prior, target, leaf, witness) ==
    /\ RenderedIntValueHistory(plan, state, witness.values)
    /\ Expressions!ReachedCheckedPostorderExecution(plan, state, witness.execution)
    /\ RenderedInitialRecordInterpretation(plan, witness.values, witness.execution.outcome, prior, target, leaf)

RenderedInitialRecordOrders(count, prefixes, sorting, names, ordinals) ==
    /\ RenderedInitialRecordLayout(names, ordinals)
    /\ \A index \in 1..count : \A prior \in prefixes[index - 1].states :
        RenderedInitialPrefixOrder(index - 1, sorting[index], prior)

\* Union over reached prefixes; interpreting the emitted LET wrappers remains a separate obligation.
RenderedInitialFailureEventUnion(positions, order, plans, prefixes, witnesses, sorting, names, ordinals) ==
    UNION {UNION {RenderedInitialAdditionEvents(plans[index], witnesses[index][prior].values,
        RenderedInitialPrefixEntries(index - 1, sorting[index], names, prior), ordinals[order[index]]) :
        prior \in prefixes[index - 1].states} : index \in positions}

THEOREM RenderedAdditionGuardsConstructTheReachedInitializationEvent ==
    ASSUME IntInitializationDomains,
           NEW plan, NEW bound, NEW state, NEW values, NEW prior, NEW target,
           Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
               plan.reads, plan.left, plan.right, bound, state),
           RenderedIntValueHistory(plan, state, values)
    PROVE \E execution :
        /\ Expressions!ReachedCheckedPostorderExecution(plan, state, execution)
        /\ execution.outcome \in Expressions!ExpressionOutcomes
        /\ execution.values = [index \in 1..execution.completed |-> values[index]]
        /\ RenderedInitialAdditionEvents(plan, values, prior, target) =
            IF execution.outcome.ok THEN {}
            ELSE {[before |-> prior, site |-> target, kind |-> "integerOverflow.addition",
                   operands |-> execution.outcome.failure[3]]}
    PROOF
    <1>0. /\ Expressions!IntegerDomain
          /\ SwiftIntMin \in Int /\ SwiftIntMax \in Int
          /\ plan.count \in Nat /\ plan.count > 0
          /\ \A index \in 1..plan.count :
              /\ plan.kinds[index] \in {"literal", "read", "add"}
              /\ (plan.kinds[index] = "add" =>
                  /\ plan.left[index] \in 1..(index - 1)
                  /\ plan.right[index] \in 1..(index - 1))
        BY SMT DEF IntInitializationDomains, Expressions!IntegerDomain,
            Expressions!PartialExpressionPlan, Expressions!ExpressionPlan
    <1>. DEFINE good(index) == IF index = 0 THEN TRUE ELSE
        (\A earlier \in 1..index : RenderedIntGuard(plan, values, earlier))
            => Expressions!InRange(values[index])
    <1>. HIDE DEF good
    <1>1a. good(0) BY SMT DEF good
    <1>1b. \A index \in 1..plan.count :
        ((\A earlier \in 0..(index - 1) : good(earlier)) => good(index))
        <2>. SUFFICES ASSUME NEW index \in 1..plan.count,
                             \A earlier \in 0..(index - 1) : good(earlier),
                             \A earlier \in 1..index : RenderedIntGuard(plan, values, earlier)
                     PROVE Expressions!InRange(values[index])
            BY SMT DEF good
        <2>1. CASE plan.kinds[index] = "literal"
            BY <2>1, SMT DEF RenderedIntValueHistory, Expressions!PartialExpressionPlan,
                Expressions!ExpressionPlan, Expressions!InRange
        <2>2. CASE plan.kinds[index] = "read"
            BY <2>2, SMT DEF RenderedIntValueHistory, Expressions!PartialExpressionPlan,
                Expressions!ExpressionPlan, Expressions!ExpressionReadKeys, Expressions!InRange
        <2>3. CASE plan.kinds[index] = "add"
            <3>1. /\ Expressions!InRange(values[plan.left[index]])
                  /\ Expressions!InRange(values[plan.right[index]])
                BY <1>0, <2>3, SMT DEF good
            <3>2. Expressions!InRange(values[plan.left[index]] + values[plan.right[index]])
                BY <1>0, <2>3, <3>1, Expressions!GeneratedAddGuardMatchesSource, SMT
                    DEF RenderedIntGuard, RenderedIntValueHistory
            <3>. QED BY <2>3, <3>2, SMT DEF RenderedIntValueHistory
        <2>. QED BY <1>0, <2>1, <2>2, <2>3, SetExtensionality, SMT
    <1>. DEFINE goodFlags == [index \in 0..plan.count |-> good(index)]
    <1>1t. goodFlags \in [0..plan.count -> BOOLEAN]
        BY <1>0, SMT DEF goodFlags, good
    <1>1p. goodFlags[0] /\ \A index \in 1..plan.count :
        ((\A earlier \in 0..(index - 1) : goodFlags[earlier]) => goodFlags[index])
        BY <1>0, <1>1a, <1>1b, SMT DEF goodFlags
    <1>1. \A index \in 0..plan.count : good(index)
        BY <1>0, <1>1t, <1>1p, FiniteBooleanPrefixProperty, SMT DEF goodFlags
    <1>2. \A index \in 1..plan.count :
        Expressions!CheckedPostorderOperation(plan, state, values, index) =
            IF RenderedIntGuard(plan, values, index) THEN Expressions!Success(values[index])
            ELSE Expressions!GeneratedOverflow(values[plan.left[index]], values[plan.right[index]])
        BY <1>0, SMT DEF RenderedIntValueHistory, RenderedIntGuard,
            Expressions!CheckedPostorderOperation, Expressions!GeneratedAdd
    <1>. DEFINE stopped(length) ==
        (\A index \in 1..length : RenderedIntGuard(plan, values, index))
        \/ (\E failed \in 1..length :
             /\ \A earlier \in 1..(failed - 1) : RenderedIntGuard(plan, values, earlier)
             /\ ~RenderedIntGuard(plan, values, failed))
    <1>. HIDE DEF stopped
    <1>3a. stopped(0) BY SMT DEF stopped
    <1>3b. \A length \in 1..plan.count :
        ((\A earlier \in 0..(length - 1) : stopped(earlier)) => stopped(length))
        <2>. SUFFICES ASSUME NEW length \in 1..plan.count,
                             \A earlier \in 0..(length - 1) : stopped(earlier)
                     PROVE stopped(length)
            BY SMT
        <2>1. stopped(length - 1) BY <1>0, SMT
        <2>2. CASE \E failed \in 1..(length - 1) :
            /\ \A earlier \in 1..(failed - 1) : RenderedIntGuard(plan, values, earlier)
            /\ ~RenderedIntGuard(plan, values, failed)
            BY <2>2, SMT DEF stopped
        <2>3. CASE \A index \in 1..(length - 1) : RenderedIntGuard(plan, values, index)
            BY <2>3, SMT DEF stopped
        <2>. QED BY <2>1, <2>2, <2>3, SMT DEF stopped
    <1>. DEFINE stoppedFlags == [index \in 0..plan.count |-> stopped(index)]
    <1>3t. stoppedFlags \in [0..plan.count -> BOOLEAN]
        BY <1>0, SMT DEF stoppedFlags, stopped
    <1>3p. stoppedFlags[0] /\ \A index \in 1..plan.count :
        ((\A earlier \in 0..(index - 1) : stoppedFlags[earlier]) => stoppedFlags[index])
        BY <1>0, <1>3a, <1>3b, SMT DEF stoppedFlags
    <1>3. stopped(plan.count)
        <2>1. \A index \in 0..plan.count : stoppedFlags[index]
            BY <1>0, <1>3t, <1>3p, FiniteBooleanPrefixProperty, SMT
        <2>. QED BY <1>0, <2>1, SMT DEF stoppedFlags
    <1>4. CASE \A index \in 1..plan.count : RenderedIntGuard(plan, values, index)
        <2>. DEFINE execution == [completed |-> plan.count, values |-> values,
                                 outcome |-> Expressions!Success(values[plan.count])]
        <2>1a. \A index \in 1..plan.count : Expressions!InRange(values[index])
            BY <1>0, <1>1, <1>4, SMT DEF good
        <2>1. values \in [1..plan.count -> SwiftIntMin..SwiftIntMax]
            BY <1>0, <2>1a, SMT DEF RenderedIntValueHistory, Expressions!InRange
        <2>2. Expressions!ReachedCheckedPostorderExecution(plan, state, execution)
            BY <1>0, <1>2, <1>4, <2>1, SMT
                DEF execution, Expressions!ReachedCheckedPostorderExecution
        <2>3. RenderedInitialAdditionEvents(plan, values, prior, target) = {}
            BY <1>4, SMT DEF RenderedInitialAdditionEvents
        <2>4. execution.values = [index \in 1..execution.completed |-> values[index]]
            BY <2>1, SMT DEF execution
        <2>5. execution.outcome \in Expressions!ExpressionOutcomes
            <3>1. plan.count \in 1..plan.count
                BY <1>0, SMT
            <3>2. values[plan.count] \in SwiftIntMin..SwiftIntMax
                BY <2>1, <3>1, SMT
            <3>3. execution.outcome = Expressions!Success(values[plan.count])
                BY SMT DEF execution
            <3>4. Expressions!Success(values[plan.count])
                \in [ok: {TRUE}, value: SwiftIntMin..SwiftIntMax, failure: {<<"none", 0, 0>>}]
                BY <3>2, SMT DEF Expressions!Success
            <3>5. Expressions!Success(values[plan.count]) \in Expressions!ExpressionOutcomes
                BY <3>4, SMT DEF Expressions!ExpressionOutcomes
            <3>. QED BY <3>3, <3>5, SMT
        <2>. QED BY <1>0, <2>2, <2>3, <2>4, <2>5, SMT
            DEF execution, Expressions!Success, Expressions!ExpressionOutcomes
    <1>5. CASE ~(\A index \in 1..plan.count : RenderedIntGuard(plan, values, index))
        <2>0. PICK failed \in 1..plan.count :
            /\ \A earlier \in 1..(failed - 1) : RenderedIntGuard(plan, values, earlier)
            /\ ~RenderedIntGuard(plan, values, failed)
            BY <1>3, <1>5, SMT DEF stopped
        <2>1. /\ failed \in Nat /\ failed > 0
              /\ plan.kinds[failed] = "add"
              /\ \A index \in 1..(failed - 1) : Expressions!InRange(values[index])
            BY <1>0, <1>1, <2>0, SMT DEF good, RenderedIntGuard
        <2>. DEFINE prefix == [index \in 1..(failed - 1) |-> values[index]]
                    outcome == Expressions!GeneratedOverflow(
                        values[plan.left[failed]], values[plan.right[failed]])
                    execution == [completed |-> failed - 1, values |-> prefix, outcome |-> outcome]
        <2>. HIDE DEF prefix, outcome, execution
        <2>2. /\ prefix \in [1..(failed - 1) -> SwiftIntMin..SwiftIntMax]
              /\ ~outcome.ok
              /\ \A index \in 1..failed :
                  Expressions!CheckedPostorderOperation(plan, state, prefix, index)
                    = Expressions!CheckedPostorderOperation(plan, state, values, index)
            BY <1>0, <2>0, <2>1, SMT DEF prefix, outcome, Expressions!GeneratedOverflow,
                Expressions!InRange, Expressions!CheckedPostorderOperation
        <2>3. Expressions!ReachedCheckedPostorderExecution(plan, state, execution)
            BY <1>0, <1>2, <2>0, <2>1, <2>2, SMT
                DEF execution, prefix, outcome, Expressions!ReachedCheckedPostorderExecution
        <2>4. \A index \in 1..plan.count :
            ((\A earlier \in 1..(index - 1) : RenderedIntGuard(plan, values, earlier))
             /\ ~RenderedIntGuard(plan, values, index)) <=> index = failed
            BY <2>0, SMT
        <2>5. RenderedInitialAdditionEvents(plan, values, prior, target) =
            {[before |-> prior, site |-> target, kind |-> "integerOverflow.addition",
              operands |-> outcome.failure[3]]}
            BY <2>0, <2>1, <2>4, SetExtensionality, SMT
                DEF RenderedInitialAdditionEvents, outcome, Expressions!GeneratedOverflow
        <2>6. outcome \in Expressions!ExpressionOutcomes
            BY <1>0, <2>0, <2>1, <2>2, SMT
                DEF outcome, Expressions!GeneratedOverflow, Expressions!ExpressionOutcomes,
                    Expressions!ArithmeticFailures, Expressions!InRange
        <2>. QED BY <2>2, <2>3, <2>5, <2>6, SMT DEF execution, prefix
    <1>. QED BY <1>4, <1>5, SMT

THEOREM RenderedSourceAdditionSitesSupplyTheCompleteInitializerLeaf ==
    ASSUME IntInitializationDomains,
           NEW steps, NEW root, NEW view, NEW heights, NEW pendings, NEW currents, NEW emissions,
           NEW bound \in SUBSET IntKeys, NEW state \in [bound -> SwiftIntMin..SwiftIntMax],
           NEW meaning, NEW prior \in PartialBindings,
           NEW target \in IntKeys \ (DOMAIN prior),
           bound = (DOMAIN prior) \cap IntKeys, state = PartialIntProjection(prior),
           Expressions!SynchronizedNodeHistory(steps, root, view, heights, pendings, currents, emissions),
           heights[steps] = 0, Expressions!SourceSyntaxHistory(view, state, meaning),
           \A step \in 1..steps : pendings[step - 1][heights[step - 1]].node \in DOMAIN view.kinds,
           Expressions!TypedVisitedSourceInputs(view, emissions[steps]),
           {emissions[steps].origins[index] : index \in 1..emissions[steps].count}
               \subseteq DOMAIN view.kinds,
           LET plan == Expressions!ExtractedNodePlan(emissions[steps], target)
           IN Expressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads) \subseteq bound
    PROVE LET plan == Expressions!ExtractedNodePlan(emissions[steps], target)
          IN \E values, execution :
              /\ RenderedIntValueHistory(plan, state, values)
              /\ \A actualValues : RenderedIntValueHistory(plan, state, actualValues)
                    => actualValues = values
              /\ Expressions!ReachedCheckedPostorderExecution(plan, state, execution)
              /\ SourceIntInitializerOutcome(meaning[root])
                   = GeneratedIntInitializerOutcome(execution.outcome)
              /\ SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root])) =
                  [states |-> IF execution.outcome.ok
                              THEN {GeneratedExtension(prior, target, values[plan.count])}
                              ELSE {},
                   failures |-> DecodedRenderedAdditionEvents(
                       RenderedInitialAdditionEvents(plan, values, prior, target))]
              /\ RenderedInitialRecordInterpretation(plan, values, execution.outcome, prior, target,
                     SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root])))
    PROOF
    <1>. DEFINE plan == Expressions!ExtractedNodePlan(emissions[steps], target)
    <1>. HIDE DEF plan
    <1>0. /\ Expressions!IntegerDomain /\ target \in IntKeys \cap Keys
          /\ NoFailure \notin Expressions!ArithmeticFailures
        BY SMT DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>1. Expressions!CompleteIntBindings(bound, state) \in [IntKeys -> SwiftIntMin..SwiftIntMax]
        BY <1>0, Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
    <1>2. Expressions!ExpressionPlan(plan.count, plan.kinds, plan.literals,
              plan.reads, plan.left, plan.right, Expressions!CompleteIntBindings(bound, state))
        BY <1>0, <1>1, Expressions!SuccessfulSynchronizedVisitSuppliesItsExpressionPlan, SMT DEF plan
    <1>3. Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
              plan.reads, plan.left, plan.right, bound, state)
        BY <1>2, SMT DEF plan, Expressions!PartialExpressionPlan
    <1>3n. plan.count \in Nat
        BY <1>2, SMT DEF Expressions!ExpressionPlan
    <1>. DEFINE stepsForTerms == [index \in 1..plan.count |->
        [prefix \in [1..(index - 1) -> Int] |->
            IF plan.kinds[index] = "literal" THEN plan.literals[index]
            ELSE IF plan.kinds[index] = "read" THEN state[plan.reads[index]]
            ELSE prefix[plan.left[index]] + prefix[plan.right[index]]]]
    <1>. HIDE DEF stepsForTerms
    <1>3a. \A index \in 1..plan.count :
        stepsForTerms[index] \in [[1..(index - 1) -> Int] -> Int]
        BY <1>2, <1>3, SMT DEF stepsForTerms, Expressions!ExpressionPlan,
            Expressions!PartialExpressionPlan, Expressions!ExpressionReadKeys
    <1>3b. PICK values \in [1..plan.count -> Int] : IndexedHistory(stepsForTerms, values, plan.count)
        BY <1>3n, <1>3a, FiniteIndexedHistoryExists, SMT
    <1>3c. RenderedIntValueHistory(plan, state, values)
        BY <1>2, <1>3b, SMT DEF stepsForTerms, IndexedHistory, HistoryPrefix,
            RenderedIntValueHistory, Expressions!ExpressionPlan
    <1>3d. \A actualValues : RenderedIntValueHistory(plan, state, actualValues) => actualValues = values
        <2>. SUFFICES ASSUME NEW actualValues, RenderedIntValueHistory(plan, state, actualValues)
                     PROVE actualValues = values
            BY SMT
        <2>1. actualValues \in [1..plan.count -> Int] /\ values \in [1..plan.count -> Int]
            BY <1>3c, SMT DEF RenderedIntValueHistory
        <2>2. \A index \in 1..plan.count :
            ((\A earlier \in 1..(index - 1) : actualValues[earlier] = values[earlier])
                => actualValues[index] = values[index])
            BY <1>2, <1>3c, SMT DEF RenderedIntValueHistory, Expressions!ExpressionPlan
        <2>. QED BY <1>3n, <2>1, <2>2, FiniteIndexedHistoriesAgree, SMT
    <1>3e. /\ IntInitializationDomains
           /\ Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
                  plan.reads, plan.left, plan.right, bound, state)
           /\ RenderedIntValueHistory(plan, state, values)
        BY <1>3, <1>3c, SMT
    <1>3f. InitialSentinels /\ Expressions!IntegerDomain
        BY InitialSentinels, <1>3e, SMT DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>4. PICK execution :
        /\ Expressions!ReachedCheckedPostorderExecution(plan, state, execution)
        /\ execution.outcome \in Expressions!ExpressionOutcomes
        /\ execution.values = [index \in 1..execution.completed |-> values[index]]
        /\ RenderedInitialAdditionEvents(plan, values, prior, target) =
            IF execution.outcome.ok THEN {}
            ELSE {[before |-> prior, site |-> target, kind |-> "integerOverflow.addition",
                   operands |-> execution.outcome.failure[3]]}
        BY ONLY <1>3e, <1>3f, RenderedAdditionGuardsConstructTheReachedInitializationEvent, SMT
            DEF InitialSentinels
    <1>5. meaning[root] = execution.outcome
        BY <1>0, <1>4, Expressions!CompletedSyntaxVisitRetainsTheReachedCheckedOutcome, SMT DEF plan
    <1>6. /\ SourceIntInitializerOutcome(meaning[root])
                  = GeneratedIntInitializerOutcome(execution.outcome)
          /\ SourceIntInitializerOutcome(meaning[root]) \in InitializerOutcomes
        BY <1>4, <1>5, IntExpressionOutcomesSupplyInitializerOutcomes, SMT
    <1>7. SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root]))
            = GeneratedInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root]))
        BY <1>0, <1>6, InitializerLeafRetainsCompleteStatesAndFailures, SMT
            DEF PartialBindings, IntInitializationDomains
    <1>8. execution.outcome.ok => execution.outcome.value = values[plan.count]
        BY <1>3c, <1>4, SMT DEF Expressions!ReachedCheckedPostorderExecution,
            Expressions!Success, Expressions!ExpressionOutcomes, RenderedIntValueHistory
    <1>8a. ~execution.outcome.ok =>
        /\ execution.outcome.failure # NoFailure
        /\ execution.outcome.failure =
               <<"integerOverflow", "addition", execution.outcome.failure[3]>>
        BY <1>0, <1>4, SMT DEF Expressions!ExpressionOutcomes, Expressions!ArithmeticFailures
    <1>8b. execution.outcome.ok \in BOOLEAN
        BY ONLY <1>4, SMT DEF Expressions!ExpressionOutcomes
    <1>9. SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root])) =
        [states |-> IF execution.outcome.ok
                    THEN {GeneratedExtension(prior, target, values[plan.count])} ELSE {},
         failures |-> DecodedRenderedAdditionEvents(RenderedInitialAdditionEvents(plan, values, prior, target))]
        <2>1. CASE execution.outcome.ok
            <3>1. SourceIntInitializerOutcome(meaning[root]) = SourceFixed(values[plan.count])
                BY <1>5, <1>8, <2>1, SMT DEF SourceIntInitializerOutcome
            <3>2. DecodedRenderedAdditionEvents(RenderedInitialAdditionEvents(plan, values, prior, target)) = {}
                BY <1>4, <2>1, SMT DEF DecodedRenderedAdditionEvents
            <3>3. GeneratedInitialStates(prior, target, SourceFixed(values[plan.count]))
                = {GeneratedExtension(prior, target, values[plan.count])}
                BY SetExtensionality, SMT DEF GeneratedInitialStates, SourceFixed
            <3>4. GeneratedInitialFailures(prior, target, SourceFixed(values[plan.count])) = {}
                BY SMT DEF GeneratedInitialFailures, SourceFixed
            <3>5. GeneratedInitialLeaf(prior, target, SourceFixed(values[plan.count]))
                = [states |-> {GeneratedExtension(prior, target, values[plan.count])}, failures |-> {}]
                BY <3>3, <3>4, SMT DEF GeneratedInitialLeaf
            <3>. QED BY <1>7, <2>1, <3>1, <3>2, <3>5, SMT
        <2>2. CASE ~execution.outcome.ok
            <3>1. SourceIntInitializerOutcome(meaning[root]) = SourceFailed(execution.outcome.failure)
                BY <1>5, <2>2, SMT DEF SourceIntInitializerOutcome
            <3>2. DecodedRenderedAdditionEvents(RenderedInitialAdditionEvents(plan, values, prior, target))
                = {[before |-> prior, site |-> target, payload |-> execution.outcome.failure]}
                BY <1>4, <1>8a, <2>2, SMT DEF DecodedRenderedAdditionEvents
            <3>3. GeneratedInitialStates(prior, target, SourceFailed(execution.outcome.failure)) = {}
                BY SetExtensionality, SMT DEF GeneratedInitialStates, SourceFailed
            <3>4. GeneratedInitialFailures(prior, target, SourceFailed(execution.outcome.failure))
                = {[before |-> prior, site |-> target, payload |-> execution.outcome.failure]}
                BY <1>8a, <2>2, SetExtensionality, SMT DEF GeneratedInitialFailures, SourceFailed
            <3>5. GeneratedInitialLeaf(prior, target, SourceFailed(execution.outcome.failure))
                = [states |-> {}, failures |-> {[before |-> prior, site |-> target, payload |-> execution.outcome.failure]}]
                BY <3>3, <3>4, SMT DEF GeneratedInitialLeaf
            <3>6. SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root]))
                = GeneratedInitialLeaf(prior, target, SourceFailed(execution.outcome.failure))
                BY ONLY <1>7, <3>1, SMT
            <3>7. SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root]))
                = [states |-> {}, failures |-> {[before |-> prior, site |-> target, payload |-> execution.outcome.failure]}]
                BY ONLY <3>6, <3>5, SMT
            <3>8. execution.outcome.ok = FALSE
                BY ONLY <1>8b, <2>2, SMT
            <3>9. [states |-> IF execution.outcome.ok
                             THEN {GeneratedExtension(prior, target, values[plan.count])} ELSE {},
                    failures |-> DecodedRenderedAdditionEvents(
                        RenderedInitialAdditionEvents(plan, values, prior, target))]
                = [states |-> {}, failures |->
                    {[before |-> prior, site |-> target, payload |-> execution.outcome.failure]}]
                BY ONLY <3>2, <3>8, SMT
            <3>. QED BY <1>8b, <2>2, <3>2, <3>7, <3>8, <3>9, SMT
        <2>. QED BY <1>4, <2>1, <2>2, SMT DEF Expressions!ExpressionOutcomes
    <1>10. RenderedInitialRecordInterpretation(plan, values, execution.outcome, prior, target,
        SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root])))
        <2>. SUFFICES ASSUME NEW length, NEW order, NEW names, NEW ordinals,
                             RenderedInitialRecordLayout(names, ordinals),
                             RenderedInitialPrefixOrder(length, order, prior)
                     PROVE SourceInitialLeaf(prior, target, SourceIntInitializerOutcome(meaning[root]))
                         = NamedRenderedInitialLeaf(plan, values, execution.outcome,
                             prior, target, length, order, names, ordinals)
            BY SMT DEF RenderedInitialRecordInterpretation
        <2>1. DecodedNamedRenderedAdditionEvents(
            RenderedInitialAdditionEvents(plan, values,
                RenderedInitialPrefixEntries(length, order, names, prior), ordinals[target]), names, ordinals)
            = DecodedRenderedAdditionEvents(RenderedInitialAdditionEvents(plan, values, prior, target))
            BY <1>0, RenderedAdditionRecordDecodingRetainsCompleteObservations, SMT
        <2>. QED BY ONLY <1>9, <2>1, SMT DEF NamedRenderedInitialLeaf
    <1>. QED BY <1>3c, <1>3d, <1>4, <1>6, <1>9, <1>10, SMT DEF plan

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
              /\ InitialSetProjection(observations[count]) = source[count]
              /\ InitialObservationIsTyped(observations[count])
              /\ observations[count].stateCount <= 1 /\ observations[count].failureCount <= 1
              /\ observations[count].stateCount + observations[count].failureCount = 1
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
          /\ \A index \in positions : \A prior \in source[index - 1].states :
              LET visit == visits[index]
                  plan == Expressions!ExtractedNodePlan(visit.emissions[visit.steps], order[index])
              IN \E values, execution :
                  /\ RenderedIntValueHistory(plan, PartialIntProjection(prior), values)
                  /\ Expressions!ReachedCheckedPostorderExecution(plan, PartialIntProjection(prior), execution)
                  /\ RenderedInitialRecordInterpretation(plan, values, execution.outcome, prior, order[index],
                         SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]))
          /\ \E renderedPlans, witnesses :
                 /\ renderedPlans = [index \in positions |->
                        Expressions!ExtractedNodePlan(visits[index].emissions[visits[index].steps], order[index])]
                 /\ \A index \in positions : \A prior \in source[index - 1].states :
                     RenderedInitialLeafWitness(renderedPlans[index], PartialIntProjection(prior), prior, order[index],
                         SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]), witnesses[index][prior])
                 /\ \A sorting, names, ordinals :
                     RenderedInitialRecordOrders(count, source, sorting, names, ordinals) =>
                         DecodedNamedRenderedAdditionEvents(RenderedInitialFailureEventUnion(
                             positions, order, renderedPlans, source, witnesses, sorting, names, ordinals), names, ordinals)
                             = source[count].failures
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
    <1>. HIDE DEF emissions, plans, sourceExpressions, generatedExpressions
    <1>0. Expressions!IntegerDomain
        BY SMT DEF IntInitializationDomains, Expressions!IntegerDomain
    <1>. DEFINE typedPrefix(index) ==
        \A prior \in source[index].states :
            PartialIntProjection(prior) \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
    <1>. HIDE DEF typedPrefix
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
        <2>1a. PICK prior \in source[index - 1].states :
            \E value \in sourceEvaluate[index][prior].candidates :
                SourceExtension(prior, order[index], value, after)
            BY SMT DEF InitializationHistory, InitializationAdvance, SourceAdvance,
                SourceInitialLeaf, SourceInitialStates
        <2>1. PICK value \in sourceEvaluate[index][prior].candidates :
            /\ prior \in source[index - 1].states
            /\ SourceExtension(prior, order[index], value, after)
            BY <2>1a, SMT
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
                <4>0. /\ order[index] \in IntKeys
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
                             execution)
                    BY <2>1, <3>1, SMT DEF visit, emitted, plan, execution
                <4>0a. ((DOMAIN prior) \cap IntKeys) \in SUBSET IntKeys
                    BY SetExtensionality, SMT
                <4>1. meanings[index][prior][roots[index]] = execution.outcome
                    BY <1>0, <2>2, <4>0, <4>0a,
                        Expressions!CompletedSyntaxVisitRetainsTheReachedCheckedOutcome, SMT
                        DEF emitted, plan
                <4>1a. emitted.count \in Nat \ {0}
                    BY <1>0, <4>0, Expressions!SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot, SMT
                        DEF emitted
                <4>2. /\ emitted.count \in Nat \ {0}
                      /\ plan.count = emitted.count /\ plan.count \in Nat /\ plan.count > 0
                    BY <4>1a, SMT DEF plan, Expressions!ExtractedNodePlan
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
    <1>0p. typedPrefix(0) /\ \A index \in 1..count :
        ((\A earlier \in 0..(index - 1) : typedPrefix(earlier)) => typedPrefix(index))
        BY <1>0a, <1>0b, SMT
    <1>. DEFINE typedPrefixFlags == [index \in 0..count |-> typedPrefix(index)]
    <1>0t. typedPrefixFlags \in [0..count -> BOOLEAN]
        BY SMT DEF typedPrefixFlags, typedPrefix
    <1>0q. typedPrefixFlags[0] /\ \A index \in 1..count :
        ((\A earlier \in 0..(index - 1) : typedPrefixFlags[earlier]) => typedPrefixFlags[index])
        BY <1>0p, SMT DEF typedPrefixFlags
    <1>0c. \A index \in 0..count : typedPrefix(index)
        BY <1>0n, <1>0t, <1>0q, FiniteBooleanPrefixProperty, SMT DEF typedPrefixFlags
    <1>0d. \A index \in 1..count : \A prior \in source[index - 1].states :
        PartialIntProjection(prior) \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
        BY <1>0c, SMT DEF typedPrefix, InitializationOrder
    <1>. HIDE DEF typedPrefixFlags
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
            <3>0a. /\ Expressions!SynchronizedNodeHistory(visits[index].steps, roots[index], views[index],
                          visits[index].heights, visits[index].pendings, visits[index].currents, visits[index].emissions)
                   /\ visits[index].heights[visits[index].steps] = 0
                   /\ order[index] \in IntKeys
                   /\ \A step \in 1..visits[index].steps :
                         visits[index].pendings[step - 1][visits[index].heights[step - 1]].node
                             \in DOMAIN views[index].kinds
                   /\ Expressions!TypedVisitedSourceInputs(views[index], emissions[index])
                   /\ {emissions[index].origins[node] : node \in 1..emissions[index].count}
                         \subseteq DOMAIN views[index].kinds
                   /\ Expressions!SourceSyntaxHistory(views[index], PartialIntProjection(prior),
                         meanings[index][prior])
                   /\ Expressions!ExpressionReadKeys(plans[index].count, plans[index].kinds, plans[index].reads)
                         \subseteq (DOMAIN prior) \cap IntKeys
                   /\ Expressions!ReachedCheckedPostorderExecution(plans[index], PartialIntProjection(prior),
                         executions[index][prior])
                BY <2>1, SMT DEF emissions, plans
            <3>0b. \A step \in 0..visits[index].steps :
                /\ Expressions!NodeEmissionArrays(visits[index].emissions[step])
                /\ Expressions!AllNodePayloadsMatchSource(views[index], visits[index].emissions[step])
                BY <1>0, <3>0a, Expressions!SynchronizedNodeHistoryPreservesEverySourcePayload, SMT
            <3>0bs. visits[index].steps \in Nat
                    /\ visits[index].steps \in 0..visits[index].steps
                BY <3>0a, SMT DEF Expressions!SynchronizedNodeHistory, Expressions!PendingVisitHistory
            <3>0br. LET result == visits[index].emissions[visits[index].steps]
                    IN /\ result.count \in Nat \ {0} /\ result.height = 1
                       /\ result.indices[1] = result.count
                       /\ result.origins[result.count] = roots[index]
                       /\ Expressions!AllNodePayloadsMatchSource(views[index], result)
                BY <1>0, <3>0a, Expressions!SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot, SMT
            <3>0. /\ Expressions!NodeEmissionArrays(emissions[index])
                  /\ emissions[index].count \in Nat \ {0} /\ emissions[index].count > 0
                  /\ emissions[index].origins[emissions[index].count] = roots[index]
                  /\ Expressions!AllNodePayloadsMatchSource(views[index], emissions[index])
                BY <2>1, <3>0b, <3>0bs, <3>0br, SMT DEF emissions
            <3>0c. /\ ((DOMAIN prior) \cap IntKeys) \in SUBSET IntKeys
                   /\ PartialIntProjection(prior)
                          \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
                   /\ Expressions!CompleteIntBindings((DOMAIN prior) \cap IntKeys, PartialIntProjection(prior))
                          \in [IntKeys -> SwiftIntMin..SwiftIntMax]
                BY <1>0, <1>0d, <2>0, Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
                    DEF IntInitializationDomains, Expressions!IntegerDomain
            <3>0cp. plans[index] = Expressions!ExtractedNodePlan(emissions[index], order[index])
                BY <2>1, SMT DEF plans
            <3>1. Expressions!PartialExpressionPlan(plans[index].count, plans[index].kinds,
                plans[index].literals, plans[index].reads, plans[index].left, plans[index].right,
                (DOMAIN prior) \cap IntKeys, PartialIntProjection(prior))
                <4>1. Expressions!ExpressionPlan(plans[index].count, plans[index].kinds,
                    plans[index].literals, plans[index].reads, plans[index].left, plans[index].right,
                    Expressions!CompleteIntBindings((DOMAIN prior) \cap IntKeys, PartialIntProjection(prior)))
                    BY <1>0, <2>1, <3>0a, <3>0c,
                        Expressions!SuccessfulSynchronizedVisitSuppliesItsExpressionPlan, SMT DEF emissions, plans
                <4>2. Expressions!ExpressionReadKeys(plans[index].count,
                    plans[index].kinds, plans[index].reads) \subseteq (DOMAIN prior) \cap IntKeys
                    BY <3>0a, SMT
                <4>. QED BY <3>0c, <4>1, <4>2, SMT DEF Expressions!PartialExpressionPlan
            <3>2. \E history : Expressions!GeneratedExpressionHistory(plans[index].count,
                plans[index].kinds, plans[index].literals, plans[index].reads,
                plans[index].left, plans[index].right, PartialIntProjection(prior), history)
                BY <1>0, <3>1, Expressions!PartialOrderedIntExpressionsPreserveValueAndFailure, SMT
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
                BY <1>0, <2>1, <3>0a, <3>0c, <3>0cp,
                    Expressions!CompletedSyntaxVisitRetainsTheReachedCheckedOutcome, SMT DEF emissions
            <3>6. sourceExpressions[index][prior][plans[index].count] \in Expressions!ExpressionOutcomes
                BY <1>0, <3>4, Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
                    DEF IntInitializerChildren, Expressions!PartialExpressionPlan,
                        Expressions!ExpressionPlan, IntInitializationDomains, Expressions!IntegerDomain
            <3>6a. /\ plans[index].count = emissions[index].count
                   /\ sourceExpressions[index][prior][plans[index].count]
                          = meanings[index][prior][roots[index]]
                <4>1. plans[index].count = emissions[index].count
                    BY <3>0cp, SMT DEF Expressions!ExtractedNodePlan
                <4>2. emissions[index].count \in 0..emissions[index].count
                    BY <3>0, SMT
                <4>3. sourceExpressions[index][prior] =
                    Expressions!EmittedSourceSyntaxHistory(emissions[index], meanings[index][prior])
                    BY <2>0, <2>1, SMT DEF sourceExpressions
                <4>. QED BY <3>0, <4>1, <4>2, <4>3, SMT
                    DEF Expressions!EmittedSourceSyntaxHistory
            <3>6b. meanings[index][prior][roots[index]] \in Expressions!ExpressionOutcomes
                BY <3>6, <3>6a, SMT
            <3>7. SourceIntInitializerOutcome(meanings[index][prior][roots[index]])
                    = GeneratedIntInitializerOutcome(executions[index][prior].outcome)
                BY <3>5, <3>6b, IntExpressionOutcomesSupplyInitializerOutcomes, SMT
            <3>8. /\ sourceEvaluate[index][prior] = SourceIntInitializerOutcome(meanings[index][prior][roots[index]])
                  /\ generatedEvaluate[index][prior] = GeneratedIntInitializerOutcome(executions[index][prior].outcome)
                BY <2>0, <2>1, SMT
            <3>. QED BY <3>0a, <3>4, <3>6a, <3>7, <3>8, SMT
        <2>2. CASE index \notin positions
            BY <2>2, FixedInitializerRetainsItsOnlyCandidate, SMT
        <2>. QED BY <2>1, <2>2, SMT
    <1>2a. \A index \in 1..count : \A prior \in source[index - 1].states :
        sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
        BY <1>1, IntInitializerChildrenSupplyOutcomeAgreement, SMT
    <1>2h. \A index \in 0..count : source[index] = generated[index]
        BY <1>2a, InitializationHistoriesNeedOnlyReachableChildAgreement, SMT
    <1>2s. source[count].states \subseteq [Keys -> Values]
        BY SourceHistoriesBindEveryPrefixKey, SMT DEF InitializationOrder
    <1>2r. source[count] \in InitializationResults
        BY SMT DEF InitializationHistory, InitializationOrder
    <1>2t. \A sourceChecks, generatedChecks :
        (sourceChecks \in [PartialBindings -> SelectionOutcomes]
         /\ generatedChecks \in [PartialBindings -> SelectionOutcomes]
         /\ \A prior \in source[count].states : sourceChecks[prior] = generatedChecks[prior])
        => SourceTerminal(source[count], sourceChecks) = GeneratedTerminal(source[count], generatedChecks)
        BY <1>2r, TerminalSelectionRetainsEveryStateAndFailure, SMT
    <1>2. /\ \A index \in 0..count : source[index] = generated[index]
          /\ \A sourceChecks, generatedChecks :
                 (sourceChecks \in [PartialBindings -> SelectionOutcomes]
                  /\ generatedChecks \in [PartialBindings -> SelectionOutcomes]
                  /\ \A prior \in source[count].states : sourceChecks[prior] = generatedChecks[prior])
                 => /\ SourceTerminal(source[count], sourceChecks)
                         = GeneratedTerminal(generated[count], generatedChecks)
                    /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
        BY <1>2h, <1>2s, <1>2t, SMT
            DEF InitializationOrder, SourceTerminal, SourceSelectedStates
    <1>2u. \A index \in 0..count : source[index] = generated[index]
        BY ONLY <1>2, SMT
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
                BY <1>0, <1>1, <2>1, Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
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
        BY <1>2b, DeterministicReachableInitializersConstructTheirOrderedObservations, SMT
    <1>2d. \A index \in 0..count :
        /\ InitialObservationIsTyped(observations[index])
        /\ observations[index].stateCount <= 1 /\ observations[index].failureCount <= 1
        /\ observations[index].stateCount + observations[index].failureCount = 1
        BY <1>2c, SingleBranchInitializationDerivesItsObservationBounds, SMT
    <1>2e. SingleBranchInitialObservationHistory(count, order, generatedEvaluate, observations)
        <2>0. \A index \in 1..count : index - 1 \in 0..count
            BY <1>0n, SMT
        <2>1. \A index \in 1..count : observations[index - 1].stateCount = 1
            => observations[index - 1].stateHistory[1] \in source[index - 1].states
            BY <1>2c, <1>2d, <2>0, SMT DEF InitialSetProjection
        <2>2. \A index \in 1..count : observations[index - 1].stateCount = 1
            => sourceEvaluate[index][observations[index - 1].stateHistory[1]]
                 = generatedEvaluate[index][observations[index - 1].stateHistory[1]]
            BY <1>2a, <2>1, SMT
        <2>3. \A index \in 1..count : SingleBranchInitialObservationStep(
            observations[index - 1], order[index], generatedEvaluate[index], observations[index])
            BY <1>2c, <2>2, SMT
                DEF SingleBranchInitialObservationHistory, SingleBranchInitialObservationStep
        <2>. QED BY <1>2c, <2>3, SMT DEF SingleBranchInitialObservationHistory
    <1>2f. \E observations :
        /\ SingleBranchInitialObservationHistory(count, order, sourceEvaluate, observations)
        /\ SingleBranchInitialObservationHistory(count, order, generatedEvaluate, observations)
        /\ InitialSetProjection(observations[count]) = source[count]
        /\ InitialObservationIsTyped(observations[count])
        /\ observations[count].stateCount <= 1 /\ observations[count].failureCount <= 1
        /\ observations[count].stateCount + observations[count].failureCount = 1
        BY <1>2c, <1>2d, <1>2e, SMT DEF InitializationOrder
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
            BY <2>1, <2>2, InitializationHistoryIsUnique, SMT
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
    <1>5. \A index \in positions : \A prior \in source[index - 1].states :
        \E values, execution :
            /\ RenderedIntValueHistory(plans[index], PartialIntProjection(prior), values)
            /\ Expressions!ReachedCheckedPostorderExecution(plans[index], PartialIntProjection(prior), execution)
            /\ RenderedInitialRecordInterpretation(plans[index], values, execution.outcome, prior, order[index],
                   SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]))
        <2>. SUFFICES ASSUME NEW index \in positions, NEW prior \in source[index - 1].states
                     PROVE \E values, execution :
                         /\ RenderedIntValueHistory(plans[index], PartialIntProjection(prior), values)
                         /\ Expressions!ReachedCheckedPostorderExecution(
                                plans[index], PartialIntProjection(prior), execution)
                         /\ RenderedInitialRecordInterpretation(
                                plans[index], values, execution.outcome, prior, order[index],
                                SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]))
            BY SMT
        <2>1. /\ prior \in PartialBindings
              /\ DOMAIN prior = PrefixKeys(order, index - 1)
              /\ order[index] \in IntKeys \ (DOMAIN prior)
              /\ PartialIntProjection(prior) \in [(DOMAIN prior) \cap IntKeys -> SwiftIntMin..SwiftIntMax]
            BY <1>0d, SourceHistoriesBindEveryPrefixKey, SMT
                DEF PartialBindings, InitializationOrder, PrefixKeys, IntInitializationDomains
        <2>2. ((DOMAIN prior) \cap IntKeys) \in SUBSET IntKeys
            BY SetExtensionality, SMT
        <2>. QED BY <2>1, <2>2, RenderedSourceAdditionSitesSupplyTheCompleteInitializerLeaf, SMT
            DEF emissions, plans
    <1>5a. \A index \in positions : \A prior \in source[index - 1].states :
        LET visit == visits[index]
            plan == Expressions!ExtractedNodePlan(visit.emissions[visit.steps], order[index])
        IN \E values, execution :
            /\ RenderedIntValueHistory(plan, PartialIntProjection(prior), values)
            /\ Expressions!ReachedCheckedPostorderExecution(plan, PartialIntProjection(prior), execution)
            /\ RenderedInitialRecordInterpretation(plan, values, execution.outcome, prior, order[index],
                   SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]))
        <2>. SUFFICES ASSUME NEW index \in positions, NEW prior \in source[index - 1].states
                     PROVE LET visit == visits[index]
                               plan == Expressions!ExtractedNodePlan(visit.emissions[visit.steps], order[index])
                           IN \E values, execution :
                               /\ RenderedIntValueHistory(plan, PartialIntProjection(prior), values)
                               /\ Expressions!ReachedCheckedPostorderExecution(plan, PartialIntProjection(prior), execution)
                               /\ RenderedInitialRecordInterpretation(plan, values, execution.outcome, prior, order[index],
                                      SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]))
            BY SMT
        <2>0. index \in positions /\ prior \in source[index - 1].states BY SMT
        <2>1. plans[index] = Expressions!ExtractedNodePlan(
            visits[index].emissions[visits[index].steps], order[index])
            BY SMT DEF plans, emissions
        <2>. QED BY ONLY <1>5, <2>0, <2>1, SMT
    <1>6. \A index \in positions : \A prior \in source[index - 1].states :
        \E witness : RenderedInitialLeafWitness(plans[index], PartialIntProjection(prior), prior, order[index],
            SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]), witness)
        <2>. SUFFICES ASSUME NEW index \in positions, NEW prior \in source[index - 1].states
                     PROVE \E witness : RenderedInitialLeafWitness(
                         plans[index], PartialIntProjection(prior), prior, order[index],
                         SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]), witness)
            BY SMT
        <2>1. PICK values, execution :
            /\ RenderedIntValueHistory(plans[index], PartialIntProjection(prior), values)
            /\ Expressions!ReachedCheckedPostorderExecution(plans[index], PartialIntProjection(prior), execution)
            /\ RenderedInitialRecordInterpretation(plans[index], values, execution.outcome, prior, order[index],
                   SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]))
            BY <1>5, SMT
        <2>. DEFINE witness == [values |-> values, execution |-> execution]
        <2>2. RenderedInitialLeafWitness(plans[index], PartialIntProjection(prior), prior, order[index],
            SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]), witness)
            BY <2>1, SMT DEF witness, RenderedInitialLeafWitness
        <2>. QED BY <2>2, SMT
    <1>. DEFINE constructedWitnesses == [index \in positions |-> [prior \in source[index - 1].states |->
        CHOOSE witness : RenderedInitialLeafWitness(plans[index], PartialIntProjection(prior), prior, order[index],
            SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]), witness)]]
    <1>. HIDE DEF constructedWitnesses
    <1>7. \A index \in positions : \A prior \in source[index - 1].states :
        RenderedInitialLeafWitness(plans[index], PartialIntProjection(prior), prior, order[index],
            SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]), constructedWitnesses[index][prior])
        BY <1>6, SMT DEF constructedWitnesses
    <1>8. \A sorting, names, ordinals :
        RenderedInitialRecordOrders(count, source, sorting, names, ordinals) =>
            DecodedNamedRenderedAdditionEvents(RenderedInitialFailureEventUnion(
                positions, order, plans, source, constructedWitnesses, sorting, names, ordinals), names, ordinals)
                = source[count].failures
        <2>. SUFFICES ASSUME NEW sorting, NEW names, NEW ordinals,
                             RenderedInitialRecordOrders(count, source, sorting, names, ordinals)
                     PROVE DecodedNamedRenderedAdditionEvents(RenderedInitialFailureEventUnion(
                         positions, order, plans, source, constructedWitnesses, sorting, names, ordinals), names, ordinals)
                         = source[count].failures
            BY SMT
        <2>1. \A index \in positions : \A prior \in source[index - 1].states :
            DecodedNamedRenderedAdditionEvents(RenderedInitialAdditionEvents(
                plans[index], constructedWitnesses[index][prior].values,
                RenderedInitialPrefixEntries(index - 1, sorting[index], names, prior), ordinals[order[index]]),
                names, ordinals) = SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures
            <3>. SUFFICES ASSUME NEW index \in positions, NEW prior \in source[index - 1].states
                         PROVE DecodedNamedRenderedAdditionEvents(RenderedInitialAdditionEvents(
                             plans[index], constructedWitnesses[index][prior].values,
                             RenderedInitialPrefixEntries(index - 1, sorting[index], names, prior),
                             ordinals[order[index]]), names, ordinals)
                             = SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures
                BY SMT
            <3>1. /\ RenderedInitialRecordLayout(names, ordinals)
                  /\ RenderedInitialPrefixOrder(index - 1, sorting[index], prior)
                BY SMT DEF RenderedInitialRecordOrders
            <3>2. SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior])
                = NamedRenderedInitialLeaf(plans[index], constructedWitnesses[index][prior].values,
                    constructedWitnesses[index][prior].execution.outcome, prior, order[index],
                    index - 1, sorting[index], names, ordinals)
                BY <1>7, <3>1, SMT DEF RenderedInitialLeafWitness, RenderedInitialRecordInterpretation
            <3>. QED BY <3>2, SMT DEF NamedRenderedInitialLeaf
        <2>1u. \A groups : DecodedNamedRenderedAdditionEvents(UNION groups, names, ordinals)
            = UNION {DecodedNamedRenderedAdditionEvents(events, names, ordinals) : events \in groups}
            BY SetExtensionality, SMT DEF DecodedNamedRenderedAdditionEvents
        <2>2. DecodedNamedRenderedAdditionEvents(RenderedInitialFailureEventUnion(
            positions, order, plans, source, constructedWitnesses, sorting, names, ordinals), names, ordinals)
            = UNION {UNION {SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures :
                prior \in source[index - 1].states} : index \in positions}
            <3>1. \A index \in positions :
                DecodedNamedRenderedAdditionEvents(UNION {RenderedInitialAdditionEvents(
                    plans[index], constructedWitnesses[index][prior].values,
                    RenderedInitialPrefixEntries(index - 1, sorting[index], names, prior),
                    ordinals[order[index]]) : prior \in source[index - 1].states}, names, ordinals)
                = UNION {SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures :
                    prior \in source[index - 1].states}
                BY <2>1, <2>1u, SetExtensionality, SMT
            <3>. QED BY <2>1u, <3>1, SetExtensionality, SMT DEF RenderedInitialFailureEventUnion
        <2>3. \A index \in (1..count) \ positions : \A prior \in source[index - 1].states :
            SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures = {}
            BY SMT DEF SourceInitialLeaf, SourceInitialFailures, SourceFixed
        <2>4. UNION {UNION {SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures :
            prior \in source[index - 1].states} : index \in positions}
            = UNION {UNION {SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures :
                prior \in source[index - 1].states} : index \in 1..count}
            BY <2>3, SetExtensionality, SMT
        <2>5a. \A index \in 0..count :
            source[index].states = SourceConstraintPrefix(order, index, sourceEvaluate)
            BY SourceHistoriesMatchEveryInitializerPrefix, SMT
        <2>5b. source[count].failures = SourceFailureConstraintPrefix(order, count, sourceEvaluate)
            BY SourceHistoriesMatchEveryInitialFailurePrefix, SMT DEF InitializationOrder
        <2>5c. \A index \in 1..count :
            UNION {SourceInitialFailures(prior, order[index], sourceEvaluate[index][prior]) :
                prior \in SourceConstraintPrefix(order, index - 1, sourceEvaluate)}
            = UNION {SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures :
                prior \in source[index - 1].states}
            <3>. SUFFICES ASSUME NEW index \in 1..count
                         PROVE UNION {SourceInitialFailures(prior, order[index], sourceEvaluate[index][prior]) :
                             prior \in SourceConstraintPrefix(order, index - 1, sourceEvaluate)}
                             = UNION {SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures :
                                 prior \in source[index - 1].states}
                BY SMT
            <3>1. index - 1 \in 0..count BY <1>0n, SMT
            <3>2. SourceConstraintPrefix(order, index - 1, sourceEvaluate) = source[index - 1].states
                BY <2>5a, <3>1, SMT
            <3>. QED BY <3>2, SMT DEF SourceInitialLeaf
        <2>5. source[count].failures =
            UNION {UNION {SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]).failures :
                prior \in source[index - 1].states} : index \in 1..count}
            BY <2>5b, <2>5c, SetExtensionality, SMT DEF SourceFailureConstraintPrefix
        <2>. QED BY <2>2, <2>4, <2>5, SMT
    <1>9. \E actualPlans, actualWitnesses :
              /\ actualPlans = [index \in positions |->
                     Expressions!ExtractedNodePlan(visits[index].emissions[visits[index].steps], order[index])]
              /\ \A index \in positions : \A prior \in source[index - 1].states :
                  RenderedInitialLeafWitness(actualPlans[index], PartialIntProjection(prior), prior, order[index],
                      SourceInitialLeaf(prior, order[index], sourceEvaluate[index][prior]), actualWitnesses[index][prior])
              /\ \A sorting, names, ordinals :
                  RenderedInitialRecordOrders(count, source, sorting, names, ordinals) =>
                      DecodedNamedRenderedAdditionEvents(RenderedInitialFailureEventUnion(
                          positions, order, actualPlans, source, actualWitnesses, sorting, names, ordinals), names, ordinals)
                          = source[count].failures
        <2>1. plans = [index \in positions |->
            Expressions!ExtractedNodePlan(visits[index].emissions[visits[index].steps], order[index])]
            BY SMT DEF plans, emissions
        <2>. WITNESS plans, constructedWitnesses
        <2>. QED BY ONLY <2>1, <1>7, <1>8, SMT
    <1>. QED BY <1>0n, <1>2u, <1>2f, <1>4, <1>5a, <1>9, SMT

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
