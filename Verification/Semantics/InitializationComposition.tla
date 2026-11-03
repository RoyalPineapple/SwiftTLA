-------------------- MODULE InitializationComposition --------------------
EXTENDS InitializationOutcomeRules, IndexedHistoryRules

PartialBindings == UNION {[bound -> Values] : bound \in SUBSET Keys}
InitialFailureEvents ==
    [before: PartialBindings, site: Keys \cup {NoInitialSite}, payload: FailureValues]
InitializationResults ==
    [states: SUBSET PartialBindings, failures: SUBSET InitialFailureEvents]

InitialSeed ==
    [states |-> {[name \in {} |-> name]}, failures |-> {}]

SourceAdvance(previous, key, evaluate) ==
    [states |-> UNION {SourceInitialLeaf(prior, key, evaluate[prior]).states :
                        prior \in previous.states},
     failures |-> previous.failures \cup
        UNION {SourceInitialLeaf(prior, key, evaluate[prior]).failures :
                 prior \in previous.states}]
GeneratedAdvance(previous, key, evaluate) ==
    [states |-> UNION {GeneratedInitialLeaf(prior, key, evaluate[prior]).states :
                        prior \in previous.states},
     failures |-> (UNION {GeneratedInitialLeaf(prior, key, evaluate[prior]).failures :
                           prior \in previous.states}) \cup previous.failures]

PrefixKeys(order, count) == {order[index] : index \in 1..count}
InitializationOrder(count, order) ==
    /\ count \in Nat
    /\ order \in [1..count -> Keys]
    /\ \A first, second \in 1..count : order[first] = order[second] => first = second
    /\ PrefixKeys(order, count) = Keys
InitializerEvaluators(count, evaluate) ==
    evaluate \in [1..count -> [PartialBindings -> InitializerOutcomes]]

InitializationAdvance(generated, previous, key, evaluate) ==
    IF generated THEN GeneratedAdvance(previous, key, evaluate)
    ELSE SourceAdvance(previous, key, evaluate)
InitializationHistory(generated, count, order, evaluate, history) ==
    /\ history \in [0..count -> InitializationResults]
    /\ history[0] = InitialSeed
    /\ \A index \in 1..count : history[index] =
        InitializationAdvance(generated, history[index - 1], order[index], evaluate[index])
InitializationSteps(generated, count, order, evaluate) ==
    [index \in 1..count |->
        [prefix \in [1..(index - 1) -> InitializationResults] |->
            InitializationAdvance(generated,
                IF index = 1 THEN InitialSeed ELSE prefix[index - 1],
                order[index], evaluate[index])]]

THEOREM PartialBindingsHaveSourceTypes ==
    ASSUME NEW prior \in PartialBindings
    PROVE /\ DOMAIN prior \subseteq Keys
          /\ prior \in [DOMAIN prior -> Values]
    BY SMT DEF PartialBindings

THEOREM InitialSeedIsTyped ==
    InitialSeed \in InitializationResults
    BY SMT DEF InitialSeed, InitializationResults, PartialBindings

THEOREM ExtendedBindingsKeepSourceTypes ==
    ASSUME NEW prior \in PartialBindings, NEW key \in Keys, NEW value \in Values
    PROVE GeneratedExtension(prior, key, value) \in PartialBindings
    PROOF
    <1>1. DOMAIN prior \subseteq Keys /\ prior \in [DOMAIN prior -> Values]
        BY PartialBindingsHaveSourceTypes
    <1>2. (DOMAIN prior) \cup {key} \subseteq Keys
        BY <1>1, SMT
    <1>3. GeneratedExtension(prior, key, value)
            \in [(DOMAIN prior) \cup {key} -> Values]
        BY <1>1, SMT DEF GeneratedExtension
    <1>. QED BY <1>2, <1>3, SMT DEF PartialBindings

THEOREM InitializerLeavesKeepSourceTypes ==
    ASSUME NEW prior \in PartialBindings, NEW key \in Keys,
           NEW outcome \in InitializerOutcomes
    PROVE /\ SourceInitialLeaf(prior, key, outcome) \in InitializationResults
          /\ GeneratedInitialLeaf(prior, key, outcome) \in InitializationResults
    PROOF
    <1>1. DOMAIN prior \subseteq Keys
        BY PartialBindingsHaveSourceTypes
    <1>2. SourceInitialStates(prior, key, outcome) \subseteq PartialBindings
        BY <1>1, SMT DEF SourceInitialStates, PartialBindings
    <1>3. GeneratedInitialStates(prior, key, outcome) \subseteq PartialBindings
        BY ExtendedBindingsKeepSourceTypes, SMT DEF GeneratedInitialStates, InitializerOutcomes
    <1>4. SourceInitialFailures(prior, key, outcome) \subseteq InitialFailureEvents
        BY SMT DEF SourceInitialFailures, InitializerOutcomes, InitialFailureEvents
    <1>5. SourceInitialFailures(prior, key, outcome)
            = GeneratedInitialFailures(prior, key, outcome)
        BY SMT DEF SourceInitialFailures, GeneratedInitialFailures
    <1>. QED BY <1>2, <1>3, <1>4, <1>5, SMT
        DEF SourceInitialLeaf, GeneratedInitialLeaf, InitializationResults

THEOREM InitializationAdvanceIsTyped ==
    ASSUME NEW previous \in InitializationResults, NEW key \in Keys,
           NEW evaluate \in [PartialBindings -> InitializerOutcomes]
    PROVE /\ SourceAdvance(previous, key, evaluate) \in InitializationResults
          /\ GeneratedAdvance(previous, key, evaluate) \in InitializationResults
    PROOF
    <1>1. \A prior \in previous.states :
              /\ SourceInitialLeaf(prior, key, evaluate[prior]) \in InitializationResults
              /\ GeneratedInitialLeaf(prior, key, evaluate[prior]) \in InitializationResults
        BY InitializerLeavesKeepSourceTypes, SMT DEF InitializationResults
    <1>. QED BY <1>1, SMT DEF SourceAdvance, GeneratedAdvance, InitializationResults

THEOREM InitializationHistoriesExist ==
    ASSUME NEW generated \in BOOLEAN, NEW count, NEW order, NEW evaluate,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate)
    PROVE \E history : InitializationHistory(generated, count, order, evaluate, history)
    PROOF
    <1>. DEFINE steps == InitializationSteps(generated, count, order, evaluate)
    <1>0. count \in Nat
        BY SMT DEF InitializationOrder
    <1>1. \A index \in 1..count :
              steps[index] \in [[1..(index - 1) -> InitializationResults] -> InitializationResults]
        <2>. SUFFICES ASSUME NEW index \in 1..count
                     PROVE steps[index] \in
                         [[1..(index - 1) -> InitializationResults] -> InitializationResults]
            BY SMT
        <2>1. \A prefix \in [1..(index - 1) -> InitializationResults] :
                  (IF index = 1 THEN InitialSeed ELSE prefix[index - 1]) \in InitializationResults
            BY InitialSeedIsTyped, SMT DEF InitializationOrder
        <2>2. \A prefix \in [1..(index - 1) -> InitializationResults] :
                  InitializationAdvance(generated,
                      IF index = 1 THEN InitialSeed ELSE prefix[index - 1],
                      order[index], evaluate[index]) \in InitializationResults
            BY <2>1, InitializationAdvanceIsTyped, SMT
                DEF InitializationAdvance, InitializationOrder, InitializerEvaluators
        <2>. QED BY <2>2, SMT DEF steps, InitializationSteps
    <1>2. PICK indexed \in [1..count -> InitializationResults] :
              IndexedHistory(steps, indexed, count)
        BY <1>0, <1>1, FiniteIndexedHistoryExists
    <1>. DEFINE history ==
            [index \in 0..count |-> IF index = 0 THEN InitialSeed ELSE indexed[index]]
    <1>3. history \in [0..count -> InitializationResults] /\ history[0] = InitialSeed
        BY <1>2, InitialSeedIsTyped, SMT DEF history, InitializationOrder
    <1>4. \A index \in 1..count :
              HistoryPrefix(history, index - 1) = HistoryPrefix(indexed, index - 1)
        BY <1>2, SMT DEF history, HistoryPrefix, InitializationOrder
    <1>5. InitializationHistory(generated, count, order, evaluate, history)
        BY <1>2, <1>3, <1>4, SMT
            DEF InitializationHistory, IndexedHistory, HistoryPrefix,
                steps, InitializationSteps, history, InitializationOrder
    <1>. QED BY <1>5, SMT

THEOREM SourceAdvanceBindsTheNextKey ==
    ASSUME NEW bound \in SUBSET Keys, NEW previous,
           previous.states \subseteq [bound -> Values],
           NEW key \in Keys \ bound, NEW evaluate
    PROVE SourceAdvance(previous, key, evaluate).states
        \subseteq [bound \cup {key} -> Values]
    BY SMT DEF SourceAdvance, SourceInitialLeaf, SourceInitialStates

THEOREM SourceHistoriesBindEveryPrefixKey ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW history,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           InitializationHistory(FALSE, count, order, evaluate, history)
    PROVE \A index \in 0..count :
              history[index].states \subseteq [PrefixKeys(order, index) -> Values]
    PROOF
    <1>. DEFINE P(index) == history[index].states \subseteq [PrefixKeys(order, index) -> Values]
    <1>0. count \in Nat
        BY SMT DEF InitializationOrder
    <1>1. P(0)
        <2>1. PrefixKeys(order, 0) = {}
            BY SMT DEF PrefixKeys
        <2>2. [name \in {} |-> name] \in [{} -> Values]
            BY SMT
        <2>. QED BY <2>1, <2>2, SMT
            DEF P, InitializationHistory, InitialSeed, InitializationOrder
    <1>2. \A index \in 1..count :
              ((\A child \in 0..(index - 1) : P(child)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 0..(index - 1) : P(child)
                     PROVE P(index)
            BY SMT
        <2>1. P(index - 1)
            BY SMT DEF InitializationOrder
        <2>2. PrefixKeys(order, index - 1) \subseteq Keys
              /\ order[index] \in Keys \ PrefixKeys(order, index - 1)
              /\ PrefixKeys(order, index)
                    = PrefixKeys(order, index - 1) \cup {order[index]}
            BY SMT DEF InitializationOrder, PrefixKeys
        <2>. QED BY <2>1, <2>2, SourceAdvanceBindsTheNextKey, SMT
            DEF P, InitializationHistory, InitializationAdvance
    <1>3. P(0) /\ \A index \in 1..count :
              ((\A child \in 0..(index - 1) : P(child)) => P(index))
        BY <1>1, <1>2
    <1>4. \A index \in 0..count : P(index)
        BY <1>0, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4 DEF P

THEOREM InitializerAdvancesPreserveAllBranches ==
    ASSUME NEW bound \in SUBSET Keys, NEW previous \in InitializationResults,
           previous.states \subseteq [bound -> Values], NEW key \in Keys \ bound,
           NEW source \in [PartialBindings -> InitializerOutcomes],
           NEW generated \in [PartialBindings -> InitializerOutcomes],
           \A prior \in previous.states : source[prior] = generated[prior]
    PROVE SourceAdvance(previous, key, source) = GeneratedAdvance(previous, key, generated)
    BY InitializerLeafRetainsCompleteStatesAndFailures, SMT
        DEF SourceAdvance, GeneratedAdvance, InitializationResults

THEOREM InitializationHistoriesRetainAllStatesAndFailures ==
    ASSUME NEW count, NEW order, NEW sourceEvaluate, NEW generatedEvaluate,
           NEW source, NEW generated,
           InitializationOrder(count, order),
           InitializerEvaluators(count, sourceEvaluate),
           InitializerEvaluators(count, generatedEvaluate),
           InitializationHistory(FALSE, count, order, sourceEvaluate, source),
           InitializationHistory(TRUE, count, order, generatedEvaluate, generated),
           \A index \in 1..count :
               \A prior \in [PrefixKeys(order, index - 1) -> Values] :
                   sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
    PROVE \A index \in 0..count : source[index] = generated[index]
    PROOF
    <1>. DEFINE P(index) == source[index] = generated[index]
    <1>0. count \in Nat
        BY SMT DEF InitializationOrder
    <1>1. \A index \in 0..count :
              source[index].states \subseteq [PrefixKeys(order, index) -> Values]
        BY SourceHistoriesBindEveryPrefixKey
    <1>2. P(0)
        BY SMT DEF P, InitializationHistory
    <1>3. \A index \in 1..count :
              ((\A child \in 0..(index - 1) : P(child)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 0..(index - 1) : P(child)
                     PROVE P(index)
            BY SMT
        <2>1. P(index - 1)
            BY SMT DEF InitializationOrder
        <2>2. PrefixKeys(order, index - 1) \subseteq Keys
              /\ order[index] \in Keys \ PrefixKeys(order, index - 1)
            BY SMT DEF InitializationOrder, PrefixKeys
        <2>3. SourceAdvance(source[index - 1], order[index], sourceEvaluate[index])
                = GeneratedAdvance(source[index - 1], order[index], generatedEvaluate[index])
            BY <1>1, <2>2, InitializerAdvancesPreserveAllBranches, SMT
                DEF InitializerEvaluators, InitializationHistory, InitializationOrder
        <2>. QED BY <2>1, <2>3, SMT
            DEF P, InitializationHistory, InitializationAdvance, InitializationOrder
    <1>4. P(0) /\ \A index \in 1..count :
              ((\A child \in 0..(index - 1) : P(child)) => P(index))
        BY <1>2, <1>3
    <1>5. \A index \in 0..count : P(index)
        BY <1>0, <1>4, FiniteIndexedPrefixProperty
    <1>. QED BY <1>5 DEF P

SelectionOutcomes ==
    {outcome \in [satisfied: BOOLEAN, firstFailure: FailureValues \cup {NoFailure}] :
        outcome.firstFailure # NoFailure => ~outcome.satisfied}
SourceSelectedStates(states, checks) ==
    {state \in states : checks[state].firstFailure = NoFailure /\ checks[state].satisfied}
GeneratedSelectedStates(states, checks) ==
    UNION {IF checks[state].firstFailure # NoFailure THEN {}
           ELSE IF checks[state].satisfied THEN {state} ELSE {} : state \in states}
SourceSelectionFailures(states, checks) ==
    {[before |-> state, site |-> NoInitialSite, payload |-> checks[state].firstFailure] :
        state \in {candidate \in states : checks[candidate].firstFailure # NoFailure}}
GeneratedSelectionFailures(states, checks) ==
    UNION {IF checks[state].firstFailure = NoFailure THEN {}
           ELSE {[before |-> state, site |-> NoInitialSite, payload |-> checks[state].firstFailure]} :
              state \in states}

SourceTerminal(previous, checks) ==
    [states |-> SourceSelectedStates(previous.states, checks),
     failures |-> previous.failures \cup SourceSelectionFailures(previous.states, checks)]
GeneratedTerminal(previous, checks) ==
    [states |-> GeneratedSelectedStates(previous.states, checks),
     failures |-> GeneratedSelectionFailures(previous.states, checks) \cup previous.failures]

THEOREM TerminalSelectionRetainsEveryStateAndFailure ==
    ASSUME NEW previous \in InitializationResults,
           NEW source \in [PartialBindings -> SelectionOutcomes],
           NEW generated \in [PartialBindings -> SelectionOutcomes],
           \A state \in previous.states : source[state] = generated[state]
    PROVE SourceTerminal(previous, source) = GeneratedTerminal(previous, generated)
    BY SMT DEF SourceTerminal, GeneratedTerminal, SourceSelectedStates,
        GeneratedSelectedStates, SourceSelectionFailures, GeneratedSelectionFailures

THEOREM SelectionFailuresHaveNoInitializerSite ==
    ASSUME NEW states, NEW checks, NEW event \in SourceSelectionFailures(states, checks)
    PROVE event.site = NoInitialSite
    BY SMT DEF SourceSelectionFailures

THEOREM CompleteInitialStatesAndFailureEventsCompose ==
    ASSUME NEW count, NEW order, NEW sourceEvaluate, NEW generatedEvaluate,
           NEW source, NEW generated, NEW sourceChecks, NEW generatedChecks,
           InitializationOrder(count, order),
           InitializerEvaluators(count, sourceEvaluate),
           InitializerEvaluators(count, generatedEvaluate),
           InitializationHistory(FALSE, count, order, sourceEvaluate, source),
           InitializationHistory(TRUE, count, order, generatedEvaluate, generated),
           \A index \in 1..count :
               \A prior \in [PrefixKeys(order, index - 1) -> Values] :
                   sourceEvaluate[index][prior] = generatedEvaluate[index][prior],
           sourceChecks \in [PartialBindings -> SelectionOutcomes],
           generatedChecks \in [PartialBindings -> SelectionOutcomes],
           \A state \in [Keys -> Values] : sourceChecks[state] = generatedChecks[state]
    PROVE /\ SourceTerminal(source[count], sourceChecks)
                = GeneratedTerminal(generated[count], generatedChecks)
          /\ SourceTerminal(source[count], sourceChecks).states \subseteq [Keys -> Values]
    PROOF
    <1>1. \A index \in 0..count : source[index] = generated[index]
        BY InitializationHistoriesRetainAllStatesAndFailures
    <1>2. source[count].states \subseteq [Keys -> Values]
        BY SourceHistoriesBindEveryPrefixKey, SMT DEF InitializationOrder
    <1>3. SourceTerminal(source[count], sourceChecks)
            = GeneratedTerminal(source[count], generatedChecks)
        BY <1>2, TerminalSelectionRetainsEveryStateAndFailure, SMT
            DEF InitializationHistory, InitializationOrder
    <1>. QED BY <1>1, <1>2, <1>3, SMT
        DEF SourceTerminal, SourceSelectedStates, InitializationOrder

SourceRestriction(state, bound) == [name \in bound |-> state[name]]
SourceConstraintPrefix(order, count, evaluate) ==
    {state \in [PrefixKeys(order, count) -> Values] :
        \A index \in 1..count :
            state[order[index]] \in
                evaluate[index][SourceRestriction(state, PrefixKeys(order, index - 1))].candidates}

THEOREM PrefixKeySetsAreContained ==
    ASSUME NEW count, NEW order, InitializationOrder(count, order),
           NEW first \in 0..count, NEW last \in first..count
    PROVE /\ PrefixKeys(order, first) \subseteq PrefixKeys(order, last)
          /\ PrefixKeys(order, last) \subseteq Keys
    BY SMT DEF InitializationOrder, PrefixKeys

THEOREM SourceRestrictionIsTyped ==
    ASSUME NEW full, NEW bound \in SUBSET full, NEW state \in [full -> Values]
    PROVE SourceRestriction(state, bound) \in [bound -> Values]
    BY SMT DEF SourceRestriction

THEOREM RestrictingAPrefixAgainKeepsItsValues ==
    ASSUME NEW full, NEW outer \in SUBSET full, NEW inner \in SUBSET outer,
           NEW state \in [full -> Values]
    PROVE SourceRestriction(SourceRestriction(state, outer), inner)
        = SourceRestriction(state, inner)
    BY SMT DEF SourceRestriction

THEOREM SourceExtensionSelectsTheUniquePriorPrefix ==
    ASSUME NEW bound \in SUBSET Keys, NEW key \in Keys \ bound,
           NEW prior \in [bound -> Values], NEW next \in [bound \cup {key} -> Values],
           NEW value
    PROVE SourceExtension(prior, key, value, next)
        <=> prior = SourceRestriction(next, bound) /\ next[key] = value
    BY SMT DEF SourceExtension, SourceRestriction

THEOREM EmptyConstraintPrefixKeepsTheEmptyBinding ==
    ASSUME NEW order, NEW evaluate
    PROVE SourceConstraintPrefix(order, 0, evaluate) = InitialSeed.states
    PROOF
    <1>1. PrefixKeys(order, 0) = {}
        BY SMT DEF PrefixKeys
    <1>2. [{} -> Values] = {[name \in {} |-> name]}
        BY SMT
    <1>. QED BY <1>1, <1>2, SMT DEF SourceConstraintPrefix, InitialSeed

THEOREM SourceConstraintsSeparateTheLastInitializer ==
    ASSUME NEW count, NEW order, NEW evaluate,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           NEW index \in 1..count,
           NEW next \in [PrefixKeys(order, index) -> Values]
    PROVE next \in SourceConstraintPrefix(order, index, evaluate)
        <=> /\ SourceRestriction(next, PrefixKeys(order, index - 1))
                    \in SourceConstraintPrefix(order, index - 1, evaluate)
            /\ next[order[index]] \in
                evaluate[index][SourceRestriction(next, PrefixKeys(order, index - 1))].candidates
    PROOF
    <1>. DEFINE prior == SourceRestriction(next, PrefixKeys(order, index - 1))
    <1>1. PrefixKeys(order, index - 1) \subseteq PrefixKeys(order, index)
        BY PrefixKeySetsAreContained, SMT DEF InitializationOrder
    <1>2. prior \in [PrefixKeys(order, index - 1) -> Values]
        BY <1>1, SourceRestrictionIsTyped DEF prior
    <1>3. \A earlier \in 1..(index - 1) :
              /\ PrefixKeys(order, earlier - 1) \subseteq PrefixKeys(order, index - 1)
              /\ order[earlier] \in PrefixKeys(order, index - 1)
        BY SMT DEF InitializationOrder, PrefixKeys
    <1>4. \A earlier \in 1..(index - 1) :
              SourceRestriction(prior, PrefixKeys(order, earlier - 1))
                = SourceRestriction(next, PrefixKeys(order, earlier - 1))
        BY <1>1, <1>3, RestrictingAPrefixAgainKeepsItsValues, SMT DEF prior
    <1>5. \A earlier \in 1..(index - 1) : prior[order[earlier]] = next[order[earlier]]
        BY <1>3, SMT DEF prior, SourceRestriction
    <1>. QED BY <1>2, <1>4, <1>5, SMT
        DEF SourceConstraintPrefix, prior, InitializationOrder

THEOREM SourceAdvanceBuildsExactlyTheNextConstraintPrefix ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW previous,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           NEW index \in 1..count,
           previous.states = SourceConstraintPrefix(order, index - 1, evaluate)
    PROVE SourceAdvance(previous, order[index], evaluate[index]).states
        = SourceConstraintPrefix(order, index, evaluate)
    PROOF
    <1>1. PrefixKeys(order, index - 1) \subseteq Keys
          /\ order[index] \in Keys \ PrefixKeys(order, index - 1)
          /\ PrefixKeys(order, index)
                = PrefixKeys(order, index - 1) \cup {order[index]}
        BY SMT DEF InitializationOrder, PrefixKeys
    <1>2. previous.states \subseteq [PrefixKeys(order, index - 1) -> Values]
        BY SMT DEF SourceConstraintPrefix
    <1>3. SourceAdvance(previous, order[index], evaluate[index]).states
            \subseteq [PrefixKeys(order, index) -> Values]
        BY <1>1, <1>2, SourceAdvanceBindsTheNextKey
    <1>4. \A next \in [PrefixKeys(order, index) -> Values] :
              next \in SourceAdvance(previous, order[index], evaluate[index]).states
                <=> next \in SourceConstraintPrefix(order, index, evaluate)
        <2>. SUFFICES ASSUME NEW next \in [PrefixKeys(order, index) -> Values]
                     PROVE next \in SourceAdvance(previous, order[index], evaluate[index]).states
                        <=> next \in SourceConstraintPrefix(order, index, evaluate)
            BY SMT
        <2>. DEFINE prior == SourceRestriction(next, PrefixKeys(order, index - 1))
        <2>1. prior \in [PrefixKeys(order, index - 1) -> Values]
            BY <1>1, SourceRestrictionIsTyped DEF prior
        <2>2. next \in SourceConstraintPrefix(order, index, evaluate)
                <=> /\ prior \in previous.states
                    /\ next[order[index]] \in evaluate[index][prior].candidates
            BY SourceConstraintsSeparateTheLastInitializer DEF prior
        <2>3. next \in SourceAdvance(previous, order[index], evaluate[index]).states
                <=> /\ prior \in previous.states
                    /\ next[order[index]] \in evaluate[index][prior].candidates
            BY <1>1, <1>2, <2>1, SourceExtensionSelectsTheUniquePriorPrefix, SMT
                DEF SourceAdvance, SourceInitialLeaf, SourceInitialStates, prior
        <2>. QED BY <2>2, <2>3
    <1>. QED BY <1>3, <1>4, SMT DEF SourceConstraintPrefix

THEOREM SourceHistoriesSatisfyExactlyTheInitializerConjunction ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW history,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           InitializationHistory(FALSE, count, order, evaluate, history)
    PROVE history[count].states = SourceConstraintPrefix(order, count, evaluate)
    PROOF
    <1>. DEFINE P(index) == history[index].states = SourceConstraintPrefix(order, index, evaluate)
    <1>0. count \in Nat
        BY SMT DEF InitializationOrder
    <1>1. P(0)
        BY EmptyConstraintPrefixKeepsTheEmptyBinding, SMT DEF P, InitializationHistory
    <1>2. \A index \in 1..count :
              ((\A child \in 0..(index - 1) : P(child)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 0..(index - 1) : P(child)
                     PROVE P(index)
            BY SMT
        <2>1. P(index - 1)
            BY SMT DEF InitializationOrder
        <2>2. SourceAdvance(history[index - 1], order[index], evaluate[index]).states
                = SourceConstraintPrefix(order, index, evaluate)
            BY <2>1, SourceAdvanceBuildsExactlyTheNextConstraintPrefix DEF P
        <2>. QED BY <2>2, SMT
            DEF P, InitializationHistory, InitializationAdvance, InitializationOrder
    <1>3. P(0) /\ \A index \in 1..count :
              ((\A child \in 0..(index - 1) : P(child)) => P(index))
        BY <1>1, <1>2
    <1>4. \A index \in 0..count : P(index)
        BY <1>0, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>0, <1>4, SMT DEF P

=============================================================================
