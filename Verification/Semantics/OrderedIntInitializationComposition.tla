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
