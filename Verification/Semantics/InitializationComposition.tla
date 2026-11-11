-------------------- MODULE InitializationComposition --------------------
EXTENDS InitializationOutcomeRules, IndexedHistoryRules

Finite == INSTANCE FiniteSetTheorems

PartialBindings == UNION {[bound -> Values] : bound \in SUBSET Keys}
InitialFailureEvents ==
    [before: PartialBindings, site: Keys \cup {NoInitialSite}, payload: FailureValues]
InitializationResults ==
    [states: SUBSET PartialBindings, failures: SUBSET InitialFailureEvents]

InitialSeed ==
    [states |-> {[name \in {} |-> name]}, failures |-> {}]

\* Histories retain order and multiplicity before the existing set projection.
InitialFailureHistory(count, history) ==
    /\ count \in Nat
    /\ history \in [1..count -> InitialFailureEvents]

InitialObservation(stateCount, states, failureCount, failures) ==
    [stateCount |-> stateCount, stateHistory |-> states,
     failureCount |-> failureCount, failureHistory |-> failures]

InitialObservationIsTyped(observation) ==
    /\ observation.stateCount \in Nat
    /\ observation.stateHistory \in [1..observation.stateCount -> PartialBindings]
    /\ InitialFailureHistory(observation.failureCount, observation.failureHistory)

InitialFailureSet(count, history) == {history[index] : index \in 1..count}
InitialSetProjection(observation) ==
    [states |-> {observation.stateHistory[index] : index \in 1..observation.stateCount},
     failures |-> InitialFailureSet(observation.failureCount, observation.failureHistory)]
InitialFirstFailure(count, history) ==
    IF count = 0 THEN EmptyFirstFailure
    ELSE [payload |-> history[1].payload, site |-> history[1].site]

SourceFailureHistoryExtension(count, prior, event, next) ==
    /\ InitialFailureHistory(count, prior)
    /\ InitialFailureHistory(count + 1, next)
    /\ next[count + 1] = event
    /\ \A index \in 1..count : next[index] = prior[index]

THEOREM FailureHistoryExtensionMatchesIndexedAppend ==
    ASSUME NEW count \in Nat, NEW prior \in [1..count -> InitialFailureEvents],
           NEW event \in InitialFailureEvents,
           NEW next \in [1..(count + 1) -> InitialFailureEvents]
    PROVE SourceFailureHistoryExtension(count, prior, event, next)
        <=> next = HistoryAppend(prior, count, event)
    BY SMT DEF SourceFailureHistoryExtension, InitialFailureHistory, HistoryAppend

THEOREM AppendingAnInitialFailurePreservesItsSetAndFirstProjections ==
    ASSUME NEW count \in Nat, NEW prior \in [1..count -> InitialFailureEvents],
           NEW event \in InitialFailureEvents
    PROVE LET next == HistoryAppend(prior, count, event)
          IN /\ InitialFailureHistory(count + 1, next)
             /\ InitialFailureSet(count + 1, next) = InitialFailureSet(count, prior) \cup {event}
             /\ InitialFirstFailure(count + 1, next) =
                 IF count = 0 THEN [payload |-> event.payload, site |-> event.site]
                 ELSE InitialFirstFailure(count, prior)
    BY SMT DEF InitialFailureHistory, InitialFailureSet, InitialFirstFailure, HistoryAppend

THEOREM InitialObservationProjectsToExistingSetResult ==
    ASSUME NEW observation, InitialObservationIsTyped(observation)
    PROVE InitialSetProjection(observation) \in InitializationResults
    BY SMT DEF InitialObservationIsTyped, InitialFailureHistory, InitialSetProjection,
        InitialFailureSet, InitializationResults

\* A deterministic run cannot hide a duplicate or a permutation in its set projection.
THEOREM SingletonInitialObservationsRetainOrderMultiplicityAndFirstFailure ==
    ASSUME NEW source, NEW generated,
           InitialObservationIsTyped(source), InitialObservationIsTyped(generated),
           source.stateCount <= 1, generated.stateCount <= 1,
           source.failureCount <= 1, generated.failureCount <= 1,
           InitialSetProjection(source) = InitialSetProjection(generated)
    PROVE /\ source.stateCount = generated.stateCount
          /\ source.stateHistory = generated.stateHistory
          /\ source.failureCount = generated.failureCount
          /\ source.failureHistory = generated.failureHistory
          /\ InitialFirstFailure(source.failureCount, source.failureHistory)
              = InitialFirstFailure(generated.failureCount, generated.failureHistory)
    PROOF
    <1>1. /\ source.stateCount \in 0..1 /\ generated.stateCount \in 0..1
          /\ source.failureCount \in 0..1 /\ generated.failureCount \in 0..1
        BY SMT DEF InitialObservationIsTyped, InitialFailureHistory
    <1>2. source.stateCount = generated.stateCount
        BY <1>1, SMT DEF InitialSetProjection
    <1>3. source.stateCount = 1 => source.stateHistory[1] = generated.stateHistory[1]
        BY <1>1, <1>2, SMT DEF InitialSetProjection
    <1>4. source.stateHistory = generated.stateHistory
        BY <1>1, <1>2, <1>3, SMT DEF InitialObservationIsTyped
    <1>5. source.failureCount = generated.failureCount
        BY <1>1, SMT DEF InitialSetProjection, InitialFailureSet
    <1>6. source.failureCount = 1 => source.failureHistory[1] = generated.failureHistory[1]
        BY <1>1, <1>5, SMT DEF InitialSetProjection, InitialFailureSet
    <1>7. source.failureHistory = generated.failureHistory
        BY <1>1, <1>5, <1>6, SMT DEF InitialObservationIsTyped, InitialFailureHistory
    <1>. QED BY <1>2, <1>4, <1>5, <1>7, SMT

THEOREM TheSameFailureSetAndFirstEventCanHideADroppedOccurrence ==
    ASSUME NEW event \in InitialFailureEvents
    PROVE LET empty == [index \in 1..0 |-> index]
              repeated == [index \in 1..2 |-> event]
              single == [index \in 1..1 |-> event]
              source == InitialObservation(0, empty, 2, repeated)
              dropped == InitialObservation(0, empty, 1, single)
          IN /\ InitialObservationIsTyped(source) /\ InitialObservationIsTyped(dropped)
             /\ InitialSetProjection(source) = InitialSetProjection(dropped)
             /\ InitialFirstFailure(2, repeated) = InitialFirstFailure(1, single)
             /\ source # dropped
    BY SMT DEF InitialObservation, InitialObservationIsTyped, InitialFailureHistory,
        InitialSetProjection, InitialFailureSet, InitialFirstFailure

THEOREM TheSameFailureSetAndFirstEventCanHideReorderedLaterEvents ==
    ASSUME NEW first \in InitialFailureEvents, NEW second \in InitialFailureEvents,
           NEW third \in InitialFailureEvents, second # third
    PROVE LET empty == [index \in 1..0 |-> index]
              original == [index \in 1..3 |->
                  IF index = 1 THEN first ELSE IF index = 2 THEN second ELSE third]
              swapped == [index \in 1..3 |->
                  IF index = 1 THEN first ELSE IF index = 2 THEN third ELSE second]
              source == InitialObservation(0, empty, 3, original)
              reordered == InitialObservation(0, empty, 3, swapped)
          IN /\ InitialObservationIsTyped(source) /\ InitialObservationIsTyped(reordered)
             /\ InitialSetProjection(source) = InitialSetProjection(reordered)
             /\ InitialFirstFailure(3, original) = InitialFirstFailure(3, swapped)
             /\ source # reordered
    PROOF
    <1>. DEFINE empty == [index \in 1..0 |-> index]
                original == [index \in 1..3 |->
                    IF index = 1 THEN first ELSE IF index = 2 THEN second ELSE third]
                swapped == [index \in 1..3 |->
                    IF index = 1 THEN first ELSE IF index = 2 THEN third ELSE second]
                source == InitialObservation(0, empty, 3, original)
                reordered == InitialObservation(0, empty, 3, swapped)
    <1>1. 1..3 = {1, 2, 3}
        BY SMT
    <1>2. /\ original[1] = first /\ original[2] = second /\ original[3] = third
          /\ swapped[1] = first /\ swapped[2] = third /\ swapped[3] = second
        BY SMT DEF original, swapped
    <1>3. /\ original \in [1..3 -> InitialFailureEvents]
          /\ swapped \in [1..3 -> InitialFailureEvents]
        BY <1>1, SMT DEF original, swapped
    <1>4. /\ InitialFailureSet(3, original) = {first, second, third}
          /\ InitialFailureSet(3, swapped) = {first, second, third}
        BY <1>1, <1>2, SMT DEF InitialFailureSet
    <1>5. InitialObservationIsTyped(source) /\ InitialObservationIsTyped(reordered)
        BY <1>3, SMT DEF source, reordered, empty, InitialObservation,
            InitialObservationIsTyped, InitialFailureHistory
    <1>6. InitialSetProjection(source) = InitialSetProjection(reordered)
        BY <1>4, SMT DEF source, reordered, InitialObservation, InitialSetProjection
    <1>7. InitialFirstFailure(3, original) = InitialFirstFailure(3, swapped)
        BY <1>2, SMT DEF InitialFirstFailure
    <1>8. source.failureHistory[2] = second /\ reordered.failureHistory[2] = third
        BY <1>2, SMT DEF source, reordered, InitialObservation
    <1>9. source # reordered
        BY <1>8, SMT
    <1>. QED BY <1>5, <1>6, <1>7, <1>9, SMT

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
THEOREM PrefixKeysGrowByOne ==
    ASSUME NEW count \in Nat, NEW order \in [1..count -> Keys], NEW step \in 1..count
    PROVE PrefixKeys(order, step) = PrefixKeys(order, step - 1) \cup {order[step]}
    BY SMT DEF PrefixKeys

InitializationOrder(count, order) ==
    /\ count \in Nat
    /\ order \in [1..count -> Keys]
    /\ \A first, second \in 1..count : order[first] = order[second] => first = second
    /\ PrefixKeys(order, count) = Keys
SourceReadyKeys(dependencies, bound) ==
    {key \in Keys \ bound : dependencies[key] \subseteq bound}
GeneratedReadyKeys(dependencies, remaining) ==
    {key \in remaining : dependencies[key] \cap remaining = {}}
FirstReadyDeclaration(count, declarations, ready, index) ==
    /\ index \in 1..count
    /\ declarations[index] \in ready
    /\ \A earlier \in 1..(index - 1) : declarations[earlier] \notin ready

THEOREM UnboundDependenciesAreExactlyTheRemainingDependencies ==
    ASSUME NEW dependencies \in [Keys -> SUBSET Keys], NEW bound \in SUBSET Keys
    PROVE SourceReadyKeys(dependencies, bound)
        = GeneratedReadyKeys(dependencies, Keys \ bound)
    BY SMT DEF SourceReadyKeys, GeneratedReadyKeys

THEOREM AvailableKeyWithCertifiedEarlierReadsIsFirstReady ==
    ASSUME NEW count, NEW declarations, InitializationOrder(count, declarations),
           NEW dependencies \in [Keys -> SUBSET Keys], NEW bound \in SUBSET Keys,
           NEW certified \in SUBSET Keys, NEW index \in 1..count,
           declarations[index] \in SourceReadyKeys(dependencies, bound),
           \A earlier \in 1..(index - 1) :
               /\ (declarations[earlier] \notin bound => declarations[earlier] \in certified)
               /\ (declarations[earlier] \in certified =>
                   declarations[earlier] \notin GeneratedReadyKeys(dependencies, Keys \ bound))
    PROVE FirstReadyDeclaration(count, declarations, SourceReadyKeys(dependencies, bound), index)
    BY UnboundDependenciesAreExactlyTheRemainingDependencies, SMT
        DEF FirstReadyDeclaration, SourceReadyKeys

THEOREM AReadyDeclarationHasAUniqueFirstPosition ==
    ASSUME NEW count, NEW declarations, InitializationOrder(count, declarations),
           NEW ready \in SUBSET Keys, ready # {}
    PROVE \E index \in 1..count :
        /\ FirstReadyDeclaration(count, declarations, ready, index)
        /\ \A other : FirstReadyDeclaration(count, declarations, ready, other) => other = index
    PROOF
    <1>. DEFINE P(index) == index \in 1..count /\ declarations[index] \in ready
    <1>1. \E index \in Nat : P(index)
        BY SMT DEF P, InitializationOrder, PrefixKeys
    <1>1a. PICK candidate \in Nat : P(candidate) BY <1>1
    <1>1b. HIDE DEF P
    <1>2. \E index \in Nat : P(index) /\ \A earlier \in 0..(index - 1) : ~P(earlier)
        BY <1>1a, SmallestNatural
    <1>3. PICK index \in Nat : P(index) /\ \A earlier \in 0..(index - 1) : ~P(earlier)
        BY <1>2
    <1>4. FirstReadyDeclaration(count, declarations, ready, index)
        BY <1>3, SMT DEF P, FirstReadyDeclaration, InitializationOrder
    <1>5. \A other : FirstReadyDeclaration(count, declarations, ready, other) => other = index
        BY <1>4, SMT DEF FirstReadyDeclaration
    <1>. QED BY <1>3, <1>4, <1>5, SMT DEF P

SourceDependencyOrder(count, declarations, dependencies, order) ==
    /\ InitializationOrder(count, order)
    /\ \A step \in 1..count : \E index \in 1..count :
        /\ FirstReadyDeclaration(count, declarations,
            SourceReadyKeys(dependencies, PrefixKeys(order, step - 1)), index)
        /\ order[step] = declarations[index]
GeneratedDependencyOrder(count, declarations, dependencies, order) ==
    /\ InitializationOrder(count, order)
    /\ \A step \in 1..count : \E index \in 1..count :
        /\ FirstReadyDeclaration(count, declarations,
            GeneratedReadyKeys(dependencies, Keys \ PrefixKeys(order, step - 1)), index)
        /\ order[step] = declarations[index]

THEOREM SourceAndGeneratedDependencyOrderRulesAgree ==
    ASSUME NEW count, NEW declarations, InitializationOrder(count, declarations),
           NEW dependencies \in [Keys -> SUBSET Keys],
           NEW order, InitializationOrder(count, order)
    PROVE SourceDependencyOrder(count, declarations, dependencies, order)
        <=> GeneratedDependencyOrder(count, declarations, dependencies, order)
    PROOF
    <1>1. \A step \in 1..count : PrefixKeys(order, step - 1) \subseteq Keys
        BY SMT DEF InitializationOrder, PrefixKeys
    <1>2. \A step \in 1..count :
        SourceReadyKeys(dependencies, PrefixKeys(order, step - 1))
        = GeneratedReadyKeys(dependencies, Keys \ PrefixKeys(order, step - 1))
        BY <1>1, UnboundDependenciesAreExactlyTheRemainingDependencies, SMT
    <1>. QED BY <1>2, SMT DEF SourceDependencyOrder, GeneratedDependencyOrder

THEOREM StableDependencyOrdersHaveTheSamePrefixes ==
    ASSUME NEW count, NEW declarations, InitializationOrder(count, declarations),
           NEW dependencies \in [Keys -> SUBSET Keys], NEW source, NEW generated,
           SourceDependencyOrder(count, declarations, dependencies, source),
           GeneratedDependencyOrder(count, declarations, dependencies, generated)
    PROVE source = generated
    PROOF
    <1>1. InitializationOrder(count, source) /\ InitializationOrder(count, generated)
        BY SMT DEF SourceDependencyOrder, GeneratedDependencyOrder
    <1>2. SourceDependencyOrder(count, declarations, dependencies, generated)
        BY <1>1, SourceAndGeneratedDependencyOrderRulesAgree
    <1>. DEFINE P(length) == \A index \in 1..length : source[index] = generated[index]
    <1>3. P(0) BY SMT DEF P
    <1>4. \A step \in 1..count :
        ((\A prior \in 0..(step - 1) : P(prior)) => P(step))
        <2>. SUFFICES ASSUME NEW step \in 1..count,
                             \A prior \in 0..(step - 1) : P(prior)
                     PROVE P(step)
            BY SMT
        <2>1. P(step - 1) BY SMT
        <2>2. PrefixKeys(source, step - 1) = PrefixKeys(generated, step - 1)
            BY <2>1, SMT DEF P, PrefixKeys
        <2>3. PICK first \in 1..count :
            /\ FirstReadyDeclaration(count, declarations,
                SourceReadyKeys(dependencies, PrefixKeys(source, step - 1)), first)
            /\ source[step] = declarations[first]
            BY SMT DEF SourceDependencyOrder
        <2>4. PICK second \in 1..count :
            /\ FirstReadyDeclaration(count, declarations,
                SourceReadyKeys(dependencies, PrefixKeys(generated, step - 1)), second)
            /\ generated[step] = declarations[second]
            BY <1>2, SMT DEF SourceDependencyOrder
        <2>5. first = second
            BY <2>2, <2>3, <2>4, SMT DEF FirstReadyDeclaration
        <2>. QED BY <2>1, <2>3, <2>4, <2>5, SMT DEF P
    <1>5. count \in Nat BY SMT DEF InitializationOrder
    <1>5a. HIDE DEF P
    <1>6. \A step \in 0..count : P(step)
        BY <1>3, <1>4, <1>5, FiniteIndexedPrefixProperty
    <1>. QED BY <1>1, <1>5, <1>6, SMT DEF P, InitializationOrder

THEOREM DependencyOrderBindsEveryReadBeforeEvaluation ==
    ASSUME NEW count, NEW declarations, NEW dependencies, NEW order,
           SourceDependencyOrder(count, declarations, dependencies, order)
    PROVE \A step \in 1..count : dependencies[order[step]] \subseteq PrefixKeys(order, step - 1)
    BY SMT DEF SourceDependencyOrder, FirstReadyDeclaration, SourceReadyKeys

THEOREM RankedDependenciesAlwaysProvideAReadyKey ==
    ASSUME NEW dependencies \in [Keys -> SUBSET Keys],
           NEW rank \in [Keys -> Nat], NEW remaining \in SUBSET Keys, remaining # {},
           \A key \in Keys : \A dependency \in dependencies[key] : rank[dependency] < rank[key]
    PROVE GeneratedReadyKeys(dependencies, remaining) # {}
    PROOF
    <1>. DEFINE P(value) == \E key \in remaining : rank[key] = value
    <1>1. PICK key \in remaining : TRUE BY SMT
    <1>2. rank[key] \in Nat /\ P(rank[key]) BY <1>1, SMT DEF P
    <1>3. HIDE DEF P
    <1>4. PICK least \in Nat : P(least) /\ \A earlier \in 0..(least - 1) : ~P(earlier)
        BY <1>2, SmallestNatural
    <1>5. PICK ready \in remaining : rank[ready] = least BY <1>4 DEF P
    <1>6. \A dependency \in dependencies[ready] \cap remaining :
        rank[dependency] \in 0..(least - 1) /\ P(rank[dependency])
        BY <1>5, SMT DEF P
    <1>7. dependencies[ready] \cap remaining = {}
        BY <1>4, <1>6, SMT
    <1>. QED BY <1>5, <1>7, SMT DEF GeneratedReadyKeys

THEOREM RemovingAReadyKeyAdvancesTheBoundPrefix ==
    ASSUME NEW remaining \in SUBSET Keys,
           NEW dependencies, NEW key \in GeneratedReadyKeys(dependencies, remaining)
    PROVE /\ remaining \ {key} \subseteq remaining
          /\ remaining \ {key} # remaining
          /\ Keys \ (remaining \ {key}) = (Keys \ remaining) \cup {key}
    BY SMT DEF GeneratedReadyKeys

THEOREM OmittingAReadCanFalselyDeclareAnInitializerReady ==
    ASSUME NEW target \in Keys, NEW dependency \in Keys,
           NEW remaining \in SUBSET Keys, target \in remaining, dependency \in remaining
    PROVE /\ target \notin SourceReadyKeys([key \in Keys |-> {dependency}], Keys \ remaining)
          /\ target \in GeneratedReadyKeys([key \in Keys |-> {}], remaining)
    BY SMT DEF SourceReadyKeys, GeneratedReadyKeys

THEOREM SkippingAnEarlierReadyDeclarationChangesTheStableOrder ==
    ASSUME NEW count \in Nat, NEW declarations, NEW ready,
           NEW earlier \in 1..count, NEW later \in 1..count, earlier < later,
           declarations[earlier] \in ready, declarations[later] \in ready
    PROVE ~FirstReadyDeclaration(count, declarations, ready, later)
    BY SMT DEF FirstReadyDeclaration

GeneratedDependencyPrefix(count, declarations, dependencies, length, order) ==
    /\ length \in 0..count
    /\ order \in [1..length -> Keys]
    /\ \A first, second \in 1..length : order[first] = order[second] => first = second
    /\ \A step \in 1..length : \E index \in 1..count :
        /\ FirstReadyDeclaration(count, declarations,
            GeneratedReadyKeys(dependencies, Keys \ PrefixKeys(order, step - 1)), index)
        /\ order[step] = declarations[index]

THEOREM DeclarationOrderCountsAllKeys ==
    ASSUME NEW count, NEW declarations, InitializationOrder(count, declarations)
    PROVE Finite!IsFiniteSet(Keys) /\ Finite!Cardinality(Keys) = count
    PROOF
    <1>1. count \in Nat BY SMT DEF InitializationOrder
    <1>2. declarations \in Finite!Bijection(1..count, Keys)
        BY SMT DEF InitializationOrder, PrefixKeys, Finite!Bijection,
            Finite!Injection, Finite!Surjection, Finite!IsInjective
    <1>3. Finite!ExistsBijection(1..count, Keys)
        BY <1>2, SMT DEF Finite!ExistsBijection
    <1>4. Finite!IsFiniteSet(Keys)
        BY <1>1, <1>3, Finite!FS_NatBijection, SMT
    <1>5. Finite!Cardinality(Keys) = count
        BY <1>1, <1>3, Finite!FS_CountingElements, SMT
    <1>. QED BY <1>4, <1>5

THEOREM AppendingTheFirstReadyKeyExtendsDependencyPrefix ==
    ASSUME NEW count, NEW declarations, InitializationOrder(count, declarations),
           NEW dependencies \in [Keys -> SUBSET Keys], NEW length, NEW order,
           GeneratedDependencyPrefix(count, declarations, dependencies, length, order),
           length < count, NEW index,
           FirstReadyDeclaration(count, declarations,
               GeneratedReadyKeys(dependencies, Keys \ PrefixKeys(order, length)), index)
    PROVE /\ GeneratedDependencyPrefix(count, declarations, dependencies, length + 1,
               HistoryAppend(order, length, declarations[index]))
          /\ declarations[index] \in Keys \ PrefixKeys(order, length)
          /\ Keys \ PrefixKeys(HistoryAppend(order, length, declarations[index]), length + 1)
               = (Keys \ PrefixKeys(order, length)) \ {declarations[index]}
    PROOF
    <1>. DEFINE extended == HistoryAppend(order, length, declarations[index])
    <1>1. count \in Nat /\ length \in Nat /\ length + 1 \in 0..count
          /\ declarations[index] \in Keys \ PrefixKeys(order, length)
        BY SMT DEF InitializationOrder, GeneratedDependencyPrefix, FirstReadyDeclaration, GeneratedReadyKeys
    <1>2. extended \in [1..(length + 1) -> Keys]
          /\ \A first, second \in 1..(length + 1) : extended[first] = extended[second] => first = second
        BY <1>1, SMT DEF GeneratedDependencyPrefix, extended, HistoryAppend, PrefixKeys
    <1>3. \A prefix \in 0..length : PrefixKeys(extended, prefix) = PrefixKeys(order, prefix)
        BY <1>1, SMT DEF PrefixKeys, extended, HistoryAppend
    <1>4. \A step \in 1..(length + 1) : \E position \in 1..count :
        /\ FirstReadyDeclaration(count, declarations,
            GeneratedReadyKeys(dependencies, Keys \ PrefixKeys(extended, step - 1)), position)
        /\ extended[step] = declarations[position]
        <2>. SUFFICES ASSUME NEW step \in 1..(length + 1)
                     PROVE \E position \in 1..count :
                         /\ FirstReadyDeclaration(count, declarations,
                             GeneratedReadyKeys(dependencies, Keys \ PrefixKeys(extended, step - 1)), position)
                         /\ extended[step] = declarations[position]
            BY SMT
        <2>1. CASE step = length + 1
            BY <1>1, <1>3, <2>1, SMT DEF extended, HistoryAppend, FirstReadyDeclaration
        <2>2. CASE step # length + 1
            BY <1>1, <1>3, <2>2, SMT DEF GeneratedDependencyPrefix, extended, HistoryAppend
        <2>. QED BY <2>1, <2>2, SMT
    <1>5. GeneratedDependencyPrefix(count, declarations, dependencies, length + 1, extended)
        BY <1>1, <1>2, <1>4 DEF GeneratedDependencyPrefix
    <1>6a. PrefixKeys(extended, length + 1) = PrefixKeys(extended, length) \cup {extended[length + 1]}
        BY <1>1, <1>2, PrefixKeysGrowByOne, SMT
    <1>6b. PrefixKeys(extended, length) = PrefixKeys(order, length)
          /\ extended[length + 1] = declarations[index]
        BY <1>1, <1>3, SMT DEF extended, HistoryAppend
    <1>6. Keys \ PrefixKeys(extended, length + 1)
        = (Keys \ PrefixKeys(order, length)) \ {declarations[index]}
        BY <1>6a, <1>6b
    <1>. QED BY <1>1, <1>5, <1>6 DEF extended

THEOREM RankedDependenciesConstructACompleteStableOrder ==
    ASSUME NEW count, NEW declarations, InitializationOrder(count, declarations),
           NEW dependencies \in [Keys -> SUBSET Keys], NEW rank \in [Keys -> Nat],
           \A key \in Keys : \A dependency \in dependencies[key] : rank[dependency] < rank[key]
    PROVE \E order, remaining :
        /\ SourceDependencyOrder(count, declarations, dependencies, order)
        /\ GeneratedDependencyOrder(count, declarations, dependencies, order)
        /\ remaining \in [0..count -> SUBSET Keys]
        /\ remaining[0] = Keys /\ remaining[count] = {}
        /\ \A step \in 1..count :
            /\ order[step] \in remaining[step - 1]
            /\ remaining[step] = remaining[step - 1] \ {order[step]}
    PROOF
    <1>0. count \in Nat /\ Finite!IsFiniteSet(Keys) /\ Finite!Cardinality(Keys) = count
        BY DeclarationOrderCountsAllKeys, SMT DEF InitializationOrder
    <1>. DEFINE P(length) == length <= count => \E order :
        /\ GeneratedDependencyPrefix(count, declarations, dependencies, length, order)
        /\ Finite!IsFiniteSet(Keys \ PrefixKeys(order, length))
        /\ Finite!Cardinality(Keys \ PrefixKeys(order, length)) = count - length
    <1>1. P(0)
        <2>. DEFINE empty == [index \in 1..0 |-> index]
        <2>1. GeneratedDependencyPrefix(count, declarations, dependencies, 0, empty)
            BY <1>0, SMT DEF GeneratedDependencyPrefix, empty
        <2>2. Keys \ PrefixKeys(empty, 0) = Keys BY SMT DEF PrefixKeys
        <2>. QED BY <1>0, <2>1, <2>2, SMT DEF P
    <1>2. ASSUME NEW length \in Nat, P(length)
          PROVE P(length + 1)
        <2>. SUFFICES ASSUME length + 1 <= count
                     PROVE \E order :
                         /\ GeneratedDependencyPrefix(count, declarations, dependencies, length + 1, order)
                         /\ Finite!IsFiniteSet(Keys \ PrefixKeys(order, length + 1))
                         /\ Finite!Cardinality(Keys \ PrefixKeys(order, length + 1)) = count - (length + 1)
            BY SMT DEF P
        <2>1. PICK order :
            /\ GeneratedDependencyPrefix(count, declarations, dependencies, length, order)
            /\ Finite!IsFiniteSet(Keys \ PrefixKeys(order, length))
            /\ Finite!Cardinality(Keys \ PrefixKeys(order, length)) = count - length
            BY <1>0, P(length), SMT DEF P
        <2>. DEFINE remaining == Keys \ PrefixKeys(order, length)
        <2>2. remaining \in SUBSET Keys /\ remaining # {} /\ length < count
            BY <1>0, <2>1, Finite!FS_EmptySet, SMT DEF remaining
        <2>3. GeneratedReadyKeys(dependencies, remaining) \in SUBSET Keys
              /\ GeneratedReadyKeys(dependencies, remaining) # {}
            BY <2>2, RankedDependenciesAlwaysProvideAReadyKey, SMT DEF GeneratedReadyKeys
        <2>4. PICK index \in 1..count :
            FirstReadyDeclaration(count, declarations, GeneratedReadyKeys(dependencies, remaining), index)
            BY <2>3, AReadyDeclarationHasAUniqueFirstPosition, SMT
        <2>. DEFINE extended == HistoryAppend(order, length, declarations[index])
        <2>5. GeneratedDependencyPrefix(count, declarations, dependencies, length + 1, extended)
              /\ declarations[index] \in remaining
              /\ Keys \ PrefixKeys(extended, length + 1) = remaining \ {declarations[index]}
            BY <2>1, <2>2, <2>4, AppendingTheFirstReadyKeyExtendsDependencyPrefix, SMT DEF extended, remaining
        <2>6. Finite!IsFiniteSet(Keys \ PrefixKeys(extended, length + 1))
              /\ Finite!Cardinality(Keys \ PrefixKeys(extended, length + 1)) = count - (length + 1)
            BY <1>0, <2>1, <2>5, Finite!FS_RemoveElement, SMT DEF remaining
        <2>. QED BY <2>5, <2>6, SMT
    <1>3. HIDE DEF P
    <1>4. \A length \in Nat : P(length) BY <1>1, <1>2, NatInduction
    <1>5. PICK order :
        /\ GeneratedDependencyPrefix(count, declarations, dependencies, count, order)
        /\ Finite!IsFiniteSet(Keys \ PrefixKeys(order, count))
        /\ Finite!Cardinality(Keys \ PrefixKeys(order, count)) = 0
        BY <1>0, <1>4, SMT DEF P
    <1>6. Keys \ PrefixKeys(order, count) = {}
        BY <1>5, Finite!FS_EmptySet, SMT
    <1>6a. PrefixKeys(order, count) \subseteq Keys
        BY <1>5, SMT DEF GeneratedDependencyPrefix, PrefixKeys
    <1>6b. PrefixKeys(order, count) = Keys BY <1>6, <1>6a
    <1>7. InitializationOrder(count, order)
        BY <1>0, <1>5, <1>6b, SMT DEF InitializationOrder, GeneratedDependencyPrefix
    <1>8. GeneratedDependencyOrder(count, declarations, dependencies, order)
        BY <1>5, <1>7 DEF GeneratedDependencyOrder, GeneratedDependencyPrefix
    <1>9. SourceDependencyOrder(count, declarations, dependencies, order)
        BY <1>7, <1>8, SourceAndGeneratedDependencyOrderRulesAgree, SMT
    <1>. DEFINE remaining == [index \in 0..count |-> Keys \ PrefixKeys(order, index)]
    <1>10a. remaining \in [0..count -> SUBSET Keys]
        BY SMT DEF remaining
    <1>10b. remaining[0] = Keys BY <1>0 DEF remaining, PrefixKeys
    <1>10c. remaining[count] = {} BY <1>0, <1>6, SMT DEF remaining
    <1>11a. \A step \in 1..count :
        PrefixKeys(order, step) = PrefixKeys(order, step - 1) \cup {order[step]}
        BY <1>0, <1>7, PrefixKeysGrowByOne, SMT DEF InitializationOrder
    <1>11b. \A step \in 1..count : order[step] \in remaining[step - 1]
        BY <1>0, <1>8, SMT DEF remaining, GeneratedDependencyOrder,
            FirstReadyDeclaration, GeneratedReadyKeys
    <1>11c. \A step \in 1..count : remaining[step] = remaining[step - 1] \ {order[step]}
        BY <1>0, <1>11a DEF remaining
    <1>. QED BY <1>8, <1>9, <1>10a, <1>10b, <1>10c, <1>11b, <1>11c, SMT

THEOREM SuccessfulDependencyOrderSuppliesADecreasingRank ==
    ASSUME NEW count, NEW declarations, NEW dependencies \in [Keys -> SUBSET Keys],
           NEW order, SourceDependencyOrder(count, declarations, dependencies, order)
    PROVE \E rank \in [Keys -> Nat] :
        \A key \in Keys : \A dependency \in dependencies[key] : rank[dependency] < rank[key]
    PROOF
    <1>0. InitializationOrder(count, order) /\ count \in Nat
        BY SMT DEF SourceDependencyOrder, InitializationOrder
    <1>1. \A key \in Keys : \E position \in 1..count : order[position] = key
        BY <1>0, SMT DEF InitializationOrder, PrefixKeys
    <1>. DEFINE rank == [key \in Keys |-> CHOOSE position \in 1..count : order[position] = key]
    <1>2. rank \in [Keys -> Nat] /\
        \A key \in Keys : rank[key] \in 1..count /\ order[rank[key]] = key
        BY <1>0, <1>1, SMT DEF rank
    <1>3. \A position \in 1..count : rank[order[position]] = position
        BY <1>0, <1>2, SMT DEF InitializationOrder
    <1>4. \A key \in Keys : \A dependency \in dependencies[key] : rank[dependency] < rank[key]
        <2>. SUFFICES ASSUME NEW key \in Keys, NEW dependency \in dependencies[key]
                     PROVE rank[dependency] < rank[key]
            BY SMT
        <2>1. dependencies[key] \subseteq PrefixKeys(order, rank[key] - 1)
            BY <1>2, DependencyOrderBindsEveryReadBeforeEvaluation, SMT
        <2>2. PICK position \in 1..(rank[key] - 1) : order[position] = dependency
            BY <2>1, SMT DEF PrefixKeys
        <2>3. position \in 1..count BY <1>0, <1>2, <2>2, SMT
        <2>4. rank[dependency] = position BY <1>3, <2>2, <2>3, SMT
        <2>. QED BY <1>2, <2>2, <2>4, SMT
    <1>. QED BY <1>2, <1>4, SMT

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

\* One straight-line branch replaces its live state or appends its one failure.
SingleBranchInitialObservationStep(before, key, evaluate, after) ==
    IF before.stateCount = 0 THEN after = before
    ELSE /\ before.stateCount = 1
         /\ LET prior == before.stateHistory[1]
                outcome == evaluate[prior]
            IN /\ key \notin DOMAIN prior
               /\ IF outcome.firstFailure # NoFailure THEN
                      after = InitialObservation(0, [index \in 1..0 |-> index],
                          before.failureCount + 1, HistoryAppend(before.failureHistory, before.failureCount,
                              [before |-> prior, site |-> key, payload |-> outcome.firstFailure]))
                  ELSE \E value \in Values :
                      /\ outcome.candidates = {value}
                      /\ after = InitialObservation(1,
                             [index \in 1..1 |-> GeneratedExtension(prior, key, value)],
                             before.failureCount, before.failureHistory)

SingleBranchInitialObservationHistory(count, order, evaluate, observations) ==
    /\ count \in Nat
    /\ observations[0] = InitialObservation(1,
           [index \in 1..1 |-> [key \in {} |-> key]], 0, [index \in 1..0 |-> index])
    /\ \A index \in 1..count : SingleBranchInitialObservationStep(
           observations[index - 1], order[index], evaluate[index], observations[index])

THEOREM SingleBranchInitializationDerivesItsObservationBounds ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW observations,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           SingleBranchInitialObservationHistory(count, order, evaluate, observations)
    PROVE /\ \A index \in 0..count :
              /\ InitialObservationIsTyped(observations[index])
              /\ observations[index].stateCount <= 1
              /\ observations[index].failureCount <= 1
              /\ observations[index].stateCount + observations[index].failureCount = 1
          /\ \A index \in 1..count : observations[index - 1].stateCount = 0
                 => observations[index] = observations[index - 1]
    PROOF
    <1>. DEFINE bounded(index) ==
        /\ InitialObservationIsTyped(observations[index])
        /\ observations[index].stateCount <= 1
        /\ observations[index].failureCount <= 1
        /\ observations[index].stateCount + observations[index].failureCount = 1
    <1>0. count \in Nat BY SMT DEF InitializationOrder
    <1>1. bounded(0)
        BY SMT DEF bounded, SingleBranchInitialObservationHistory, InitialObservation,
            InitialObservationIsTyped, InitialFailureHistory, PartialBindings
    <1>2. \A index \in 1..count :
        ((\A earlier \in 0..(index - 1) : bounded(earlier)) => bounded(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A earlier \in 0..(index - 1) : bounded(earlier)
                     PROVE bounded(index)
            BY SMT
        <2>. DEFINE before == observations[index - 1]
                    after == observations[index]
        <2>0. index \in Nat /\ index - 1 \in 0..(index - 1)
            BY <1>0, SMT
        <2>1. bounded(index - 1)
              /\ SingleBranchInitialObservationStep(before, order[index], evaluate[index], after)
            BY <2>0, SMT DEF before, after, SingleBranchInitialObservationHistory
        <2>2. CASE before.stateCount = 0
            BY <2>1, <2>2, SMT DEF bounded, SingleBranchInitialObservationStep, before, after
        <2>3. CASE before.stateCount # 0
            <3>1. /\ before.stateCount = 1 /\ before.failureCount = 0
                  /\ before.stateHistory[1] \in PartialBindings
                  /\ order[index] \in Keys
                  /\ evaluate[index][before.stateHistory[1]] \in InitializerOutcomes
                BY <2>1, <2>3, SMT DEF bounded, before, InitialObservationIsTyped,
                    InitialFailureHistory, InitializerEvaluators, InitializationOrder
            <3>2. CASE evaluate[index][before.stateHistory[1]].firstFailure # NoFailure
                <4>. DEFINE event == [before |-> before.stateHistory[1], site |-> order[index],
                                     payload |-> evaluate[index][before.stateHistory[1]].firstFailure]
                <4>1. event \in InitialFailureEvents
                      /\ before.failureHistory \in [1..0 -> InitialFailureEvents]
                    BY <2>1, <3>1, <3>2, SMT DEF event, bounded, before,
                        InitialObservationIsTyped, InitialFailureHistory, InitialFailureEvents, InitializerOutcomes
                <4>2. InitialFailureHistory(1, HistoryAppend(before.failureHistory, 0, event))
                    BY <4>1, AppendingAnInitialFailurePreservesItsSetAndFirstProjections, SMT
                <4>3. after = InitialObservation(0, [position \in 1..0 |-> position],
                                1, HistoryAppend(before.failureHistory, 0, event))
                    BY <2>1, <3>1, <3>2, SMT
                        DEF SingleBranchInitialObservationStep, event
                <4>. QED BY <4>2, <4>3, SMT DEF bounded, after,
                    InitialObservation, InitialObservationIsTyped
            <3>3. CASE evaluate[index][before.stateHistory[1]].firstFailure = NoFailure
                BY <2>1, <2>3, <3>1, <3>3, ExtendedBindingsKeepSourceTypes, SMT
                    DEF bounded, before, after, SingleBranchInitialObservationStep, InitialObservation,
                        InitialObservationIsTyped, InitialFailureHistory
            <3>. QED BY <3>2, <3>3, SMT
        <2>. QED BY <2>2, <2>3, SMT
    <1>3. \A index \in 0..count : bounded(index)
        BY <1>0, <1>1, <1>2, FiniteIndexedPrefixProperty
    <1>. QED BY <1>3, SMT DEF bounded, SingleBranchInitialObservationHistory,
        SingleBranchInitialObservationStep

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

THEOREM SingleBranchObservationsSupplyTheirSetInitializationHistory ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW observations,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           SingleBranchInitialObservationHistory(count, order, evaluate, observations)
    PROVE \A generated \in BOOLEAN : InitializationHistory(generated, count, order, evaluate,
        [index \in 0..count |-> InitialSetProjection(observations[index])])
    PROOF
    <1>. DEFINE projected == [index \in 0..count |-> InitialSetProjection(observations[index])]
    <1>. HIDE DEF projected
    <1>0. count \in Nat /\ 0 \in 0..count BY SMT DEF InitializationOrder
    <1>0a. 1..0 = {} /\ 1..1 = {1} BY SMT
    <1>. USE <1>0a
    <1>1. \A index \in 0..count :
        /\ InitialObservationIsTyped(observations[index])
        /\ observations[index].stateCount <= 1 /\ observations[index].failureCount <= 1
        /\ observations[index].stateCount + observations[index].failureCount = 1
        BY SingleBranchInitializationDerivesItsObservationBounds
    <1>1a. \A index \in 0..count : InitialSetProjection(observations[index]) \in InitializationResults
        BY <1>1, InitialObservationProjectsToExistingSetResult, SMT
    <1>2a. projected \in [0..count -> InitializationResults]
        BY <1>1a, SMT DEF projected
    <1>2b. projected[0] = InitialSeed
        <2>1. observations[0] = InitialObservation(1,
            [index \in 1..1 |-> [key \in {} |-> key]], 0, [index \in 1..0 |-> index])
            BY SMT DEF SingleBranchInitialObservationHistory
        <2>2. /\ observations[0].stateCount = 1
              /\ observations[0].stateHistory[1] = [key \in {} |-> key]
              /\ observations[0].failureCount = 0
            BY <2>1, SMT DEF InitialObservation
        <2>3. {observations[0].stateHistory[position] :
                position \in 1..observations[0].stateCount} = {[key \in {} |-> key]}
            BY <2>2, SetExtensionality, SMT
        <2>4. InitialFailureSet(observations[0].failureCount, observations[0].failureHistory) = {}
            BY <2>2, SMT DEF InitialFailureSet
        <2>. QED BY <1>0, <2>3, <2>4, SMT
            DEF projected, InitialSetProjection, InitialSeed
    <1>2. projected \in [0..count -> InitializationResults] /\ projected[0] = InitialSeed
        BY <1>2a, <1>2b
    <1>3. \A index \in 1..count :
        /\ projected[index] = SourceAdvance(projected[index - 1], order[index], evaluate[index])
        /\ projected[index] = GeneratedAdvance(projected[index - 1], order[index], evaluate[index])
        <2>. SUFFICES ASSUME NEW index \in 1..count
                     PROVE /\ projected[index] = SourceAdvance(projected[index - 1], order[index], evaluate[index])
                           /\ projected[index] = GeneratedAdvance(projected[index - 1], order[index], evaluate[index])
            BY SMT
        <2>. DEFINE before == observations[index - 1]
                    after == observations[index]
        <2>. HIDE DEF before, after
        <2>0. /\ index - 1 \in 0..count /\ index \in 0..count
              /\ InitialObservationIsTyped(before)
              /\ before.stateCount <= 1 /\ before.failureCount <= 1
              /\ before.stateCount + before.failureCount = 1
              /\ projected[index - 1] = InitialSetProjection(before)
              /\ projected[index] = InitialSetProjection(after)
            BY <1>0, <1>1, SMT DEF before, after, projected
        <2>1. SingleBranchInitialObservationStep(before, order[index], evaluate[index], after)
            BY SMT DEF SingleBranchInitialObservationHistory, before, after
        <2>2. CASE before.stateCount = 0
            <3>1. after = before /\ projected[index - 1].states = {}
                BY <2>0, <2>1, <2>2, SMT
                    DEF SingleBranchInitialObservationStep, InitialSetProjection
            <3>2. projected[index] = projected[index - 1]
                BY <2>0, <3>1, SMT
            <3>3. projected[index - 1] =
                [states |-> {}, failures |-> projected[index - 1].failures]
                BY <2>0, <3>1, SMT DEF InitialSetProjection
            <3>4. /\ UNION {SourceInitialLeaf(prior, order[index], evaluate[index][prior]).states :
                              prior \in projected[index - 1].states} = {}
                  /\ UNION {SourceInitialLeaf(prior, order[index], evaluate[index][prior]).failures :
                              prior \in projected[index - 1].states} = {}
                  /\ UNION {GeneratedInitialLeaf(prior, order[index], evaluate[index][prior]).states :
                              prior \in projected[index - 1].states} = {}
                  /\ UNION {GeneratedInitialLeaf(prior, order[index], evaluate[index][prior]).failures :
                              prior \in projected[index - 1].states} = {}
                BY <3>1, SetExtensionality, SMT
            <3>. QED BY <3>1, <3>2, <3>3, <3>4, SMT
                DEF SourceAdvance, GeneratedAdvance
        <2>3. CASE before.stateCount # 0
            <3>. DEFINE prior == before.stateHistory[1]
                        outcome == evaluate[index][prior]
            <3>. HIDE DEF prior, outcome
            <3>1. /\ before.stateCount = 1 /\ before.failureCount = 0
                  /\ prior \in PartialBindings /\ order[index] \in Keys \ (DOMAIN prior)
                  /\ outcome \in InitializerOutcomes
                BY <2>0, <2>1, <2>3, SMT DEF before, prior, outcome,
                    SingleBranchInitialObservationStep, InitialObservationIsTyped,
                    InitialFailureHistory, InitializerEvaluators, InitializationOrder
            <3>1a. projected[index - 1] = [states |-> {prior}, failures |-> {}]
                <4>1. {before.stateHistory[position] : position \in 1..before.stateCount} = {prior}
                    BY <3>1, SMT DEF prior
                <4>2. InitialFailureSet(before.failureCount, before.failureHistory) = {}
                    BY <3>1, SMT DEF InitialFailureSet
                <4>. QED BY <2>0, <4>1, <4>2 DEF InitialSetProjection
            <3>2. SourceInitialLeaf(prior, order[index], outcome)
                    = GeneratedInitialLeaf(prior, order[index], outcome)
                BY <3>1, PartialBindingsHaveSourceTypes, InitializerLeafRetainsCompleteStatesAndFailures, SMT
            <3>2a. /\ SourceAdvance(projected[index - 1], order[index], evaluate[index])
                          = SourceInitialLeaf(prior, order[index], outcome)
                   /\ GeneratedAdvance(projected[index - 1], order[index], evaluate[index])
                          = GeneratedInitialLeaf(prior, order[index], outcome)
                <4>1. /\ SourceInitialLeaf(prior, order[index], outcome) \in InitializationResults
                      /\ GeneratedInitialLeaf(prior, order[index], outcome) \in InitializationResults
                    BY <3>1, InitializerLeavesKeepSourceTypes, SMT
                <4>2. /\ UNION {SourceInitialLeaf(bound, order[index], evaluate[index][bound]).states :
                                  bound \in {prior}} = SourceInitialLeaf(prior, order[index], outcome).states
                      /\ UNION {SourceInitialLeaf(bound, order[index], evaluate[index][bound]).failures :
                                  bound \in {prior}} = SourceInitialLeaf(prior, order[index], outcome).failures
                      /\ UNION {GeneratedInitialLeaf(bound, order[index], evaluate[index][bound]).states :
                                  bound \in {prior}} = GeneratedInitialLeaf(prior, order[index], outcome).states
                      /\ UNION {GeneratedInitialLeaf(bound, order[index], evaluate[index][bound]).failures :
                                  bound \in {prior}} = GeneratedInitialLeaf(prior, order[index], outcome).failures
                    BY <4>1, SetExtensionality, SMT DEF outcome, InitializationResults
                <4>. QED BY <3>1a, <4>2, SMT DEF SourceAdvance, GeneratedAdvance,
                    SourceInitialLeaf, GeneratedInitialLeaf
            <3>3. CASE outcome.firstFailure # NoFailure
                <4>. DEFINE event == [before |-> prior, site |-> order[index], payload |-> outcome.firstFailure]
                <4>. HIDE DEF event
                <4>1. event \in InitialFailureEvents
                      /\ before.failureHistory \in [1..0 -> InitialFailureEvents]
                    BY <2>0, <3>1, <3>3, SMT DEF event, InitialFailureEvents,
                        InitialObservationIsTyped, InitialFailureHistory, InitializerOutcomes
                <4>2. InitialFailureSet(1, HistoryAppend(before.failureHistory, 0, event)) = {event}
                    BY <4>1, AppendingAnInitialFailurePreservesItsSetAndFirstProjections, SMT
                        DEF InitialFailureSet
                <4>2a. after = InitialObservation(0, [position \in 1..0 |-> position],
                    1, HistoryAppend(before.failureHistory, 0, event))
                    BY <2>1, <3>1, <3>3, SMT
                        DEF SingleBranchInitialObservationStep, event, prior, outcome
                <4>2b. /\ after.stateCount = 0 /\ after.failureCount = 1
                       /\ after.failureHistory = HistoryAppend(before.failureHistory, 0, event)
                    BY <4>2a, SMT DEF InitialObservation
                <4>3. projected[index] = [states |-> {}, failures |-> {event}]
                    BY <2>0, <4>2, <4>2b, SetExtensionality, SMT DEF InitialSetProjection
                <4>3a. outcome.candidates = {}
                    BY <3>1, <3>3, SMT DEF InitializerOutcomes
                <4>3b. GeneratedInitialLeaf(prior, order[index], outcome)
                    = [states |-> {}, failures |-> {event}]
                    BY <3>3, <4>3a, SetExtensionality, SMT DEF event,
                        GeneratedInitialLeaf, GeneratedInitialStates, GeneratedInitialFailures
                <4>. QED BY <3>2, <3>2a, <4>3, <4>3b, SMT
            <3>4. CASE outcome.firstFailure = NoFailure
                <4>1. PICK value \in Values :
                    /\ outcome.candidates = {value}
                    /\ after = InitialObservation(1,
                           [position \in 1..1 |-> GeneratedExtension(prior, order[index], value)],
                           before.failureCount, before.failureHistory)
                    BY <2>1, <3>1, <3>4, SMT DEF SingleBranchInitialObservationStep, prior, outcome
                <4>2. projected[index] =
                    [states |-> {GeneratedExtension(prior, order[index], value)}, failures |-> {}]
                    <5>1. after.stateCount = 1 /\ after.failureCount = 0
                          /\ after.stateHistory[1] = GeneratedExtension(prior, order[index], value)
                        BY <3>1, <4>1, SMT DEF InitialObservation
                    <5>2. {after.stateHistory[position] : position \in 1..after.stateCount}
                        = {GeneratedExtension(prior, order[index], value)}
                        BY <5>1, SetExtensionality, SMT
                    <5>3. InitialFailureSet(after.failureCount, after.failureHistory) = {}
                        BY <5>1, SMT DEF InitialFailureSet
                    <5>. QED BY <2>0, <5>2, <5>3 DEF InitialSetProjection
                <4>2a. GeneratedInitialLeaf(prior, order[index], outcome)
                    = [states |-> {GeneratedExtension(prior, order[index], value)}, failures |-> {}]
                    BY <3>4, <4>1, SetExtensionality, SMT
                        DEF GeneratedInitialLeaf, GeneratedInitialStates, GeneratedInitialFailures
                <4>. QED BY <3>2, <3>2a, <4>2, <4>2a, SMT
            <3>. QED BY <3>3, <3>4, SMT
        <2>. QED BY <2>2, <2>3, SMT
    <1>. QED BY <1>2, <1>3, SMT DEF InitializationHistory, InitializationAdvance, projected

THEOREM InitializationHistoryIsUnique ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW generated \in BOOLEAN,
           InitializationOrder(count, order), NEW first, NEW second,
           InitializationHistory(generated, count, order, evaluate, first),
           InitializationHistory(generated, count, order, evaluate, second)
    PROVE \A index \in 0..count : first[index] = second[index]
    PROOF
    <1>. DEFINE agrees(index) == first[index] = second[index]
    <1>0. count \in Nat BY SMT DEF InitializationOrder
    <1>1. agrees(0) BY SMT DEF agrees, InitializationHistory
    <1>2. \A index \in 1..count :
        ((\A earlier \in 0..(index - 1) : agrees(earlier)) => agrees(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A earlier \in 0..(index - 1) : agrees(earlier)
                     PROVE agrees(index)
            BY SMT
        <2>1. index - 1 \in 0..(index - 1) BY <1>0, SMT
        <2>2. first[index - 1] = second[index - 1] BY <2>1, SMT DEF agrees
        <2>. QED BY <2>2, SMT DEF agrees, InitializationHistory
    <1>3. \A index \in 0..count : agrees(index)
        BY <1>0, <1>1, <1>2, FiniteIndexedPrefixProperty
    <1>. QED BY <1>3 DEF agrees

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

THEOREM DeterministicReachableInitializersConstructTheirOrderedObservations ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW history,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           InitializationHistory(FALSE, count, order, evaluate, history),
           \A index \in 1..count : \A prior \in history[index - 1].states :
               evaluate[index][prior].firstFailure = NoFailure
                   => \E value \in Values : evaluate[index][prior].candidates = {value}
    PROVE \E observations :
        /\ SingleBranchInitialObservationHistory(count, order, evaluate, observations)
        /\ \A index \in 0..count : InitialSetProjection(observations[index]) = history[index]
    PROOF
    <1>. DEFINE valid(length, observations) ==
        /\ SingleBranchInitialObservationHistory(length, order, evaluate, observations)
        /\ \A index \in 0..length :
            /\ InitialObservationIsTyped(observations[index])
            /\ observations[index].stateCount <= 1
            /\ observations[index].failureCount <= 1
            /\ observations[index].stateCount + observations[index].failureCount = 1
            /\ InitialSetProjection(observations[index]) = history[index]
    <1>. DEFINE constructed(length) == \E observations : valid(length, observations)
    <1>. HIDE DEF valid, constructed
    <1>0. count \in Nat
          /\ \A index \in 0..count :
                 history[index].states \subseteq [PrefixKeys(order, index) -> Values]
        BY SourceHistoriesBindEveryPrefixKey, SMT DEF InitializationOrder
    <1>0a. 1..0 = {} /\ 1..1 = {1} BY SMT
    <1>. USE <1>0a
    <1>1. constructed(0)
        <2>. DEFINE seed == InitialObservation(1,
                         [index \in 1..1 |-> [key \in {} |-> key]],
                         0, [index \in 1..0 |-> index])
                    observations == [index \in 0..0 |-> seed]
        <2>0. [key \in {} |-> key] \in PartialBindings
            BY InitialSeedIsTyped, SMT DEF InitialSeed, InitializationResults
        <2>0a. /\ InitialObservationIsTyped(seed)
               /\ seed.stateCount = 1 /\ seed.failureCount = 0
               /\ InitialSetProjection(seed) = InitialSeed
            BY <2>0, SMT DEF seed, InitialObservation, InitialObservationIsTyped,
                InitialFailureHistory, InitialSetProjection, InitialFailureSet, InitialSeed
        <2>1. valid(0, observations)
            BY <1>0, <2>0a, SMT DEF valid, observations, seed,
                SingleBranchInitialObservationHistory, InitializationHistory
        <2>. QED BY <2>1, SMT DEF constructed
    <1>2. \A index \in 1..count :
        ((\A earlier \in 0..(index - 1) : constructed(earlier)) => constructed(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A earlier \in 0..(index - 1) : constructed(earlier)
                     PROVE constructed(index)
            BY SMT
        <2>0. index \in Nat /\ index >= 1 /\ index - 1 \in 0..(index - 1)
            BY <1>0, SMT
        <2>. USE <2>0
        <2>1. PICK previous : valid(index - 1, previous)
            BY SMT DEF constructed
        <2>. DEFINE before == previous[index - 1]
                    prior == before.stateHistory[1]
                    outcome == evaluate[index][prior]
                    value == CHOOSE candidate \in Values : outcome.candidates = {candidate}
                    after == IF before.stateCount = 0 THEN before
                        ELSE IF outcome.firstFailure # NoFailure
                        THEN InitialObservation(0, [position \in 1..0 |-> position],
                            before.failureCount + 1,
                            HistoryAppend(before.failureHistory, before.failureCount,
                                [before |-> prior, site |-> order[index], payload |-> outcome.firstFailure]))
                        ELSE InitialObservation(1,
                            [position \in 1..1 |-> GeneratedExtension(prior, order[index], value)],
                            before.failureCount, before.failureHistory)
        <2>. HIDE DEF before, prior, outcome, value, after
        <2>1a. /\ InitialObservationIsTyped(before)
               /\ before.stateCount <= 1 /\ before.failureCount <= 1
               /\ before.stateCount + before.failureCount = 1
               /\ InitialSetProjection(before) = history[index - 1]
            BY <2>0, <2>1, SMT DEF valid, before
        <2>1b. history[index] = SourceAdvance(history[index - 1], order[index], evaluate[index])
            BY <2>0, SMT DEF InitializationHistory, InitializationAdvance
        <2>2. /\ SingleBranchInitialObservationStep(before, order[index], evaluate[index], after)
              /\ InitialObservationIsTyped(after)
              /\ after.stateCount <= 1 /\ after.failureCount <= 1
              /\ after.stateCount + after.failureCount = 1
              /\ InitialSetProjection(after) = history[index]
            <3>1. CASE before.stateCount = 0
                <4>1. after = before /\ history[index - 1].states = {}
                    BY <2>1a, <3>1, SMT DEF after, InitialSetProjection
                <4>1a. /\ UNION {SourceInitialLeaf(bound, order[index], evaluate[index][bound]).states :
                                   bound \in history[index - 1].states} = {}
                       /\ UNION {SourceInitialLeaf(bound, order[index], evaluate[index][bound]).failures :
                                   bound \in history[index - 1].states} = {}
                    BY <4>1, SetExtensionality, SMT
                <4>1b. history[index - 1]
                    = [states |-> {}, failures |-> history[index - 1].failures]
                    BY <2>1a, <4>1, SMT DEF InitialSetProjection
                <4>2. history[index] = history[index - 1]
                    BY <2>1b, <4>1a, <4>1b, SMT DEF SourceAdvance
                <4>. QED BY <2>1a, <3>1, <4>1, <4>2, SMT
                    DEF SingleBranchInitialObservationStep
            <3>2. CASE before.stateCount # 0
                <4>0a. /\ before.stateCount = 1 /\ before.failureCount = 0
                       /\ prior \in PartialBindings
                       /\ history[index - 1] = [states |-> {prior}, failures |-> {}]
                    <5>1. before.stateCount = 1 /\ before.failureCount = 0
                          /\ prior \in PartialBindings
                        BY <2>1a, <3>2, SMT DEF prior, InitialObservationIsTyped, InitialFailureHistory
                    <5>2. InitialSetProjection(before) = [states |-> {prior}, failures |-> {}]
                        BY <5>1, SMT DEF prior, InitialSetProjection, InitialFailureSet
                    <5>. QED BY <2>1a, <5>1, <5>2
                <4>0b. DOMAIN prior = PrefixKeys(order, index - 1)
                    BY <1>0, <2>0, <4>0a, SMT
                <4>0c. order[index] \in Keys \ (DOMAIN prior)
                    BY <1>0, <4>0b, SMT DEF InitializationOrder, PrefixKeys
                <4>0d. outcome \in InitializerOutcomes
                    BY <4>0a, SMT DEF outcome, InitializerEvaluators
                <4>1. /\ before.stateCount = 1 /\ before.failureCount = 0
                      /\ prior \in PartialBindings /\ prior \in history[index - 1].states
                      /\ DOMAIN prior = PrefixKeys(order, index - 1)
                      /\ order[index] \in Keys \ (DOMAIN prior)
                      /\ outcome \in InitializerOutcomes
                    BY <4>0a, <4>0b, <4>0c, <4>0d, SMT
                <4>2. SourceInitialLeaf(prior, order[index], outcome)
                        = GeneratedInitialLeaf(prior, order[index], outcome)
                    BY <4>1, PartialBindingsHaveSourceTypes,
                        InitializerLeafRetainsCompleteStatesAndFailures, SMT
                <4>2a. history[index] = GeneratedInitialLeaf(prior, order[index], outcome)
                    <5>1. SourceInitialLeaf(prior, order[index], outcome) \in InitializationResults
                        BY <4>1, InitializerLeavesKeepSourceTypes, SMT
                    <5>2. /\ UNION {SourceInitialLeaf(bound, order[index], evaluate[index][bound]).states :
                                      bound \in {prior}} = SourceInitialLeaf(prior, order[index], outcome).states
                          /\ UNION {SourceInitialLeaf(bound, order[index], evaluate[index][bound]).failures :
                                      bound \in {prior}} = SourceInitialLeaf(prior, order[index], outcome).failures
                        BY <5>1, SetExtensionality, SMT DEF outcome, InitializationResults
                    <5>. QED BY <2>1b, <4>0a, <4>2, <5>2, SMT
                        DEF SourceAdvance, SourceInitialLeaf
                <4>3. CASE outcome.firstFailure # NoFailure
                    <5>. DEFINE event == [before |-> prior, site |-> order[index],
                                         payload |-> outcome.firstFailure]
                    <5>. HIDE DEF event
                    <5>1. event \in InitialFailureEvents
                          /\ before.failureHistory \in [1..0 -> InitialFailureEvents]
                        BY <2>1a, <4>1, <4>3, SMT DEF event, InitialFailureEvents,
                            InitializerOutcomes, InitialObservationIsTyped, InitialFailureHistory
                    <5>2. /\ InitialFailureHistory(1, HistoryAppend(before.failureHistory, 0, event))
                          /\ InitialFailureSet(1, HistoryAppend(before.failureHistory, 0, event)) = {event}
                        BY <5>1, AppendingAnInitialFailurePreservesItsSetAndFirstProjections, SMT
                            DEF InitialFailureSet
                    <5>3. after = InitialObservation(0, [position \in 1..0 |-> position],
                                    1, HistoryAppend(before.failureHistory, 0, event))
                        BY <3>2, <4>1, <4>3, SMT DEF after, event
                    <5>3a. /\ after.stateCount = 0 /\ after.failureCount = 1
                           /\ after.stateHistory \in [1..0 -> PartialBindings]
                           /\ after.failureHistory = HistoryAppend(before.failureHistory, 0, event)
                           /\ after.failureHistory \in [1..1 -> InitialFailureEvents]
                        BY <5>2, <5>3, SMT DEF InitialObservation, InitialFailureHistory
                    <5>3b. InitialSetProjection(after) = [states |-> {}, failures |-> {event}]
                        BY <5>2, <5>3a, SetExtensionality, SMT DEF InitialSetProjection
                    <5>4. /\ InitialObservationIsTyped(after)
                          /\ after.stateCount = 0 /\ after.failureCount = 1
                          /\ InitialSetProjection(after) = [states |-> {}, failures |-> {event}]
                        BY <5>3a, <5>3b, SMT DEF InitialObservationIsTyped, InitialFailureHistory
                    <5>5. history[index] = [states |-> {}, failures |-> {event}]
                        BY <4>1, <4>2a, <4>3, SetExtensionality, SMT DEF event, InitializerOutcomes,
                            GeneratedInitialLeaf, GeneratedInitialStates, GeneratedInitialFailures
                    <5>. QED BY <4>1, <4>3, <5>3, <5>4, <5>5, SMT
                        DEF SingleBranchInitialObservationStep, prior, outcome, event
                <4>4. CASE outcome.firstFailure = NoFailure
                    <5>1. value \in Values /\ outcome.candidates = {value}
                        BY <4>1, <4>4, SMT DEF value, outcome
                    <5>2. GeneratedExtension(prior, order[index], value) \in PartialBindings
                        BY <4>1, <5>1, ExtendedBindingsKeepSourceTypes
                    <5>3. after = InitialObservation(1,
                        [position \in 1..1 |-> GeneratedExtension(prior, order[index], value)],
                        before.failureCount, before.failureHistory)
                        BY <3>2, <4>4, SMT DEF after
                    <5>3a. /\ after.stateCount = 1 /\ after.failureCount = 0
                           /\ after.stateHistory[1] = GeneratedExtension(prior, order[index], value)
                           /\ after.stateHistory \in [1..1 -> PartialBindings]
                           /\ after.failureHistory \in [1..0 -> InitialFailureEvents]
                        BY <2>1a, <4>1, <5>2, <5>3, SMT
                            DEF InitialObservation, InitialObservationIsTyped, InitialFailureHistory
                    <5>3b. {after.stateHistory[position] : position \in 1..after.stateCount}
                        = {GeneratedExtension(prior, order[index], value)}
                        BY <5>3a, SetExtensionality, SMT
                    <5>3c. InitialFailureSet(after.failureCount, after.failureHistory) = {}
                        BY <5>3a, SMT DEF InitialFailureSet
                    <5>4. /\ InitialObservationIsTyped(after)
                          /\ after.stateCount = 1 /\ after.failureCount = 0
                          /\ InitialSetProjection(after) =
                                 [states |-> {GeneratedExtension(prior, order[index], value)}, failures |-> {}]
                        BY <5>3a, <5>3b, <5>3c, SMT
                            DEF InitialObservationIsTyped, InitialFailureHistory, InitialSetProjection
                    <5>5. history[index] =
                        [states |-> {GeneratedExtension(prior, order[index], value)}, failures |-> {}]
                        BY <4>2a, <4>4, <5>1, SetExtensionality, SMT DEF GeneratedInitialLeaf,
                            GeneratedInitialStates, GeneratedInitialFailures
                    <5>. QED BY <4>1, <4>4, <5>1, <5>3, <5>4, <5>5, SMT
                        DEF SingleBranchInitialObservationStep, prior, outcome
                <4>. QED BY <4>3, <4>4, SMT
            <3>. QED BY <3>1, <3>2, SMT
        <2>. DEFINE extended == [position \in 0..index |->
                    IF position = index THEN after ELSE previous[position]]
        <2>. HIDE DEF extended
        <2>3. valid(index, extended)
            BY <2>1, <2>2, SMT DEF valid, extended, before, SingleBranchInitialObservationHistory
        <2>. QED BY <2>3, SMT DEF constructed
    <1>3. \A index \in 0..count : constructed(index)
        <2>. DEFINE P(length) == \A index \in 0..count : index <= length => constructed(index)
        <2>1. P(0) BY <1>1, SMT DEF P
        <2>2. ASSUME NEW length \in Nat, P(length)
              PROVE P(length + 1)
            <3>. SUFFICES ASSUME length + 1 \in 1..count
                         PROVE constructed(length + 1)
                BY P(length), SMT DEF P
            <3>0. /\ length \in 0..count /\ 0..length \subseteq 0..count
                  /\ (length + 1) - 1 = length
                BY <1>0, SMT
            <3>1. \A earlier \in 0..length : constructed(earlier)
                BY P(length), <3>0, SMT DEF P
            <3>. QED BY <1>2, <3>0, <3>1, SMT
        <2>3. \A length \in Nat : P(length)
            BY <2>1, <2>2, NatInduction
        <2>. QED BY <1>0, <2>3, SMT DEF P
    <1>. QED BY <1>0, <1>3, SMT DEF constructed, valid

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

THEOREM InitializationHistoriesNeedOnlyReachableChildAgreement ==
    ASSUME NEW count, NEW order, NEW sourceEvaluate, NEW generatedEvaluate,
           NEW source, NEW generated,
           InitializationOrder(count, order),
           InitializerEvaluators(count, sourceEvaluate),
           InitializerEvaluators(count, generatedEvaluate),
           InitializationHistory(FALSE, count, order, sourceEvaluate, source),
           InitializationHistory(TRUE, count, order, generatedEvaluate, generated),
           \A index \in 1..count :
               \A prior \in source[index - 1].states :
                   sourceEvaluate[index][prior] = generatedEvaluate[index][prior]
    PROVE \A index \in 0..count : source[index] = generated[index]
    PROOF
    <1>. DEFINE P(index) == source[index] = generated[index]
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
    <1>4. count \in Nat
        BY SMT DEF InitializationOrder
    <1>5. \A index \in 0..count : P(index)
        BY <1>2, <1>3, <1>4, FiniteIndexedPrefixProperty
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

THEOREM SourceHistoriesMatchEveryInitializerPrefix ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW history,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           InitializationHistory(FALSE, count, order, evaluate, history)
    PROVE \A index \in 0..count :
        history[index].states = SourceConstraintPrefix(order, index, evaluate)
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

THEOREM SourceHistoriesSatisfyExactlyTheInitializerConjunction ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW history,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           InitializationHistory(FALSE, count, order, evaluate, history)
    PROVE history[count].states = SourceConstraintPrefix(order, count, evaluate)
    BY SourceHistoriesMatchEveryInitializerPrefix, SMT DEF InitializationOrder

SourceFailureConstraintPrefix(order, count, evaluate) ==
    UNION {UNION {SourceInitialFailures(prior, order[index], evaluate[index][prior]) :
        prior \in SourceConstraintPrefix(order, index - 1, evaluate)} : index \in 1..count}

THEOREM FailureConstraintPrefixGrowsByTheNextInitializer ==
    ASSUME NEW count, NEW order, NEW evaluate,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           NEW index \in 1..count
    PROVE SourceFailureConstraintPrefix(order, index, evaluate)
        = SourceFailureConstraintPrefix(order, index - 1, evaluate)
          \cup UNION {SourceInitialFailures(prior, order[index], evaluate[index][prior]) :
              prior \in SourceConstraintPrefix(order, index - 1, evaluate)}
    PROOF
    <1>1. index \in Nat /\ index > 0
        BY SMT DEF InitializationOrder
    <1>2. 1..index = (1..(index - 1)) \cup {index}
        BY <1>1, SMT
    <1>. QED BY <1>2, SMT DEF SourceFailureConstraintPrefix

THEOREM SourceHistoriesMatchEveryInitialFailurePrefix ==
    ASSUME NEW count, NEW order, NEW evaluate, NEW history,
           InitializationOrder(count, order), InitializerEvaluators(count, evaluate),
           InitializationHistory(FALSE, count, order, evaluate, history)
    PROVE \A index \in 0..count :
        history[index].failures = SourceFailureConstraintPrefix(order, index, evaluate)
    PROOF
    <1>. DEFINE P(index) == history[index].failures
        = SourceFailureConstraintPrefix(order, index, evaluate)
    <1>0. count \in Nat BY SMT DEF InitializationOrder
    <1>1. \A index \in 0..count :
        history[index].states = SourceConstraintPrefix(order, index, evaluate)
        BY SourceHistoriesMatchEveryInitializerPrefix
    <1>2. P(0)
        BY SMT DEF P, InitializationHistory, InitialSeed, SourceFailureConstraintPrefix
    <1>3. \A index \in 1..count :
        ((\A child \in 0..(index - 1) : P(child)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
            \A child \in 0..(index - 1) : P(child)
            PROVE P(index) BY SMT
        <2>1. P(index - 1) BY SMT DEF InitializationOrder
        <2>2. history[index].failures
            = history[index - 1].failures
              \cup UNION {SourceInitialFailures(prior, order[index], evaluate[index][prior]) :
                  prior \in SourceConstraintPrefix(order, index - 1, evaluate)}
            BY <1>1, SMT DEF InitializationHistory, InitializationAdvance,
                SourceAdvance, SourceInitialLeaf, InitializationOrder
        <2>. QED BY <2>1, <2>2, FailureConstraintPrefixGrowsByTheNextInitializer, SMT DEF P
    <1>4. P(0) /\ \A index \in 1..count :
        ((\A child \in 0..(index - 1) : P(child)) => P(index))
        BY <1>2, <1>3
    <1>5. HIDE DEF P
    <1>6. \A index \in 0..count : P(index)
        BY <1>0, <1>4, FiniteIndexedPrefixProperty
    <1>. QED BY <1>6 DEF P

WideInitializerOutcomes(universe) ==
    {outcome \in [candidates: SUBSET universe,
                  firstFailure: FailureValues \cup {NoFailure}] :
        outcome.firstFailure # NoFailure => outcome.candidates = {}}

TypedCandidateEvaluators(count, order, allowed, evaluate) ==
    [index \in 1..count |-> [prior \in PartialBindings |->
        TypedInitializerOutcome(allowed[order[index]], evaluate[index][prior])]]

SourceTypedConstraintPrefix(order, count, allowed, evaluate) ==
    {state \in [PrefixKeys(order, count) -> Values] :
        \A index \in 1..count :
            /\ state[order[index]] \in allowed[order[index]]
            /\ state[order[index]] \in evaluate[index]
                [SourceRestriction(state, PrefixKeys(order, index - 1))].candidates}
SourceTypedFailurePrefix(order, count, allowed, evaluate) ==
    UNION {UNION {SourceInitialFailures(prior, order[index], evaluate[index][prior]) :
        prior \in SourceTypedConstraintPrefix(order, index - 1, allowed, evaluate)} :
            index \in 1..count}
SourceTypedInitialResult(order, count, allowed, evaluate) ==
    [states |-> SourceTypedConstraintPrefix(order, count, allowed, evaluate),
     failures |-> SourceTypedFailurePrefix(order, count, allowed, evaluate)]

THEOREM DeclaredTypesSupplyWellTypedInitializerEvaluators ==
    ASSUME NEW count, NEW order, InitializationOrder(count, order),
           NEW allowed \in [Keys -> SUBSET Values], NEW universe,
           NEW evaluate \in [1..count -> [PartialBindings -> WideInitializerOutcomes(universe)]]
    PROVE InitializerEvaluators(count, TypedCandidateEvaluators(count, order, allowed, evaluate))
    BY SMT DEF InitializerEvaluators, TypedCandidateEvaluators, TypedInitializerOutcome,
        InitializerOutcomes, WideInitializerOutcomes, InitializationOrder

THEOREM TypedConjunctionAndFailurePrefixesKeepTheRawDomainMeaning ==
    ASSUME NEW count, NEW order, InitializationOrder(count, order),
           NEW allowed \in [Keys -> SUBSET Values], NEW universe,
           NEW evaluate \in [1..count -> [PartialBindings -> WideInitializerOutcomes(universe)]]
    PROVE \A index \in 0..count :
        /\ SourceTypedConstraintPrefix(order, index, allowed, evaluate)
            = SourceConstraintPrefix(order, index,
                TypedCandidateEvaluators(count, order, allowed, evaluate))
        /\ SourceTypedFailurePrefix(order, index, allowed, evaluate)
            = SourceFailureConstraintPrefix(order, index,
                TypedCandidateEvaluators(count, order, allowed, evaluate))
    PROOF
    <1>1. \A index \in 0..count :
        SourceTypedConstraintPrefix(order, index, allowed, evaluate)
            = SourceConstraintPrefix(order, index,
                TypedCandidateEvaluators(count, order, allowed, evaluate))
        <2>. SUFFICES ASSUME NEW index \in 0..count
            PROVE SourceTypedConstraintPrefix(order, index, allowed, evaluate)
                = SourceConstraintPrefix(order, index,
                    TypedCandidateEvaluators(count, order, allowed, evaluate))
            BY SMT
        <2>1. \A child \in 1..index :
            /\ child \in 1..count
            /\ order[child] \in Keys
            /\ PrefixKeys(order, child - 1) \subseteq PrefixKeys(order, index)
            /\ PrefixKeys(order, child - 1) \subseteq Keys
            BY SMT DEF InitializationOrder, PrefixKeys
        <2>2. \A state \in [PrefixKeys(order, index) -> Values] :
            \A child \in 1..index :
                SourceRestriction(state, PrefixKeys(order, child - 1)) \in PartialBindings
            <3>. SUFFICES ASSUME NEW state \in [PrefixKeys(order, index) -> Values],
                NEW child \in 1..index
                PROVE SourceRestriction(state, PrefixKeys(order, child - 1)) \in PartialBindings
                BY SMT
            <3>1. PrefixKeys(order, child - 1) \subseteq PrefixKeys(order, index)
                /\ PrefixKeys(order, child - 1) \subseteq Keys
                BY <2>1
            <3>2. SourceRestriction(state, PrefixKeys(order, child - 1))
                \in [PrefixKeys(order, child - 1) -> Values]
                BY <3>1, SourceRestrictionIsTyped
            <3>3. [PrefixKeys(order, child - 1) -> Values]
                \subseteq PartialBindings
                BY <3>1, SMT DEF PartialBindings
            <3>. QED BY <3>2, <3>3, SMT
        <2>3. \A state \in [PrefixKeys(order, index) -> Values] :
            \A child \in 1..index :
                TypedCandidateEvaluators(count, order, allowed, evaluate)[child]
                    [SourceRestriction(state, PrefixKeys(order, child - 1))].candidates
                = allowed[order[child]] \cap evaluate[child]
                    [SourceRestriction(state, PrefixKeys(order, child - 1))].candidates
            BY <2>1, <2>2, SMT DEF TypedCandidateEvaluators, TypedInitializerOutcome
        <2>. QED BY <2>3, SMT DEF SourceTypedConstraintPrefix, SourceConstraintPrefix
    <1>2. \A index \in 1..count :
        \A prior \in SourceTypedConstraintPrefix(order, index - 1, allowed, evaluate) :
            /\ prior \in PartialBindings
            /\ TypedCandidateEvaluators(count, order, allowed, evaluate)[index][prior].firstFailure
                = evaluate[index][prior].firstFailure
        BY SMT DEF SourceTypedConstraintPrefix, PrefixKeys, InitializationOrder,
            PartialBindings, TypedCandidateEvaluators, TypedInitializerOutcome
    <1>3. \A index \in 1..count :
        UNION {SourceInitialFailures(prior, order[index], evaluate[index][prior]) :
            prior \in SourceTypedConstraintPrefix(order, index - 1, allowed, evaluate)}
        = UNION {SourceInitialFailures(prior, order[index],
                TypedCandidateEvaluators(count, order, allowed, evaluate)[index][prior]) :
            prior \in SourceConstraintPrefix(order, index - 1,
                TypedCandidateEvaluators(count, order, allowed, evaluate))}
        BY <1>1, <1>2, SMT DEF SourceInitialFailures, InitializationOrder
    <1>4. \A index \in 0..count : SourceTypedFailurePrefix(order, index, allowed, evaluate)
        = SourceFailureConstraintPrefix(order, index,
            TypedCandidateEvaluators(count, order, allowed, evaluate))
        BY <1>3, SMT DEF SourceTypedFailurePrefix, SourceFailureConstraintPrefix,
            InitializationOrder
    <1>. QED BY <1>1, <1>4, SMT

THEOREM TypedInitialRelationsRetainAllStatesAndFailureEvents ==
    ASSUME NEW count, NEW order, InitializationOrder(count, order),
           NEW allowed \in [Keys -> SUBSET Values], NEW universe,
           NEW sourceEvaluate \in [1..count -> [PartialBindings -> WideInitializerOutcomes(universe)]],
           NEW generatedEvaluate \in [1..count -> [PartialBindings -> WideInitializerOutcomes(universe)]],
           \A index \in 1..count :
               \A prior \in [PrefixKeys(order, index - 1) -> Values] :
                   TypedInitializerOutcome(allowed[order[index]], sourceEvaluate[index][prior])
                    = TypedInitializerOutcome(allowed[order[index]], generatedEvaluate[index][prior])
    PROVE /\ \E generated : InitializationHistory(TRUE, count, order,
                TypedCandidateEvaluators(count, order, allowed, generatedEvaluate), generated)
          /\ \A generated : InitializationHistory(TRUE, count, order,
                TypedCandidateEvaluators(count, order, allowed, generatedEvaluate), generated)
              => SourceTypedInitialResult(order, count, allowed, sourceEvaluate) = generated[count]
    PROOF
    <1>. DEFINE filteredSource == TypedCandidateEvaluators(count, order, allowed, sourceEvaluate)
                filteredGenerated == TypedCandidateEvaluators(count, order, allowed, generatedEvaluate)
    <1>1. InitializerEvaluators(count, filteredSource) /\ InitializerEvaluators(count, filteredGenerated)
        BY DeclaredTypesSupplyWellTypedInitializerEvaluators DEF filteredSource, filteredGenerated
    <1>2. PICK history : InitializationHistory(FALSE, count, order, filteredSource, history)
        BY <1>1, InitializationHistoriesExist
    <1>3. \E result : InitializationHistory(TRUE, count, order, filteredGenerated, result)
        BY <1>1, InitializationHistoriesExist
    <1>4. history[count].states = SourceConstraintPrefix(order, count, filteredSource)
          /\ history[count].failures = SourceFailureConstraintPrefix(order, count, filteredSource)
        BY <1>1, <1>2, SourceHistoriesMatchEveryInitializerPrefix,
            SourceHistoriesMatchEveryInitialFailurePrefix, SMT DEF InitializationOrder
    <1>5. /\ SourceTypedConstraintPrefix(order, count, allowed, sourceEvaluate)
                = SourceConstraintPrefix(order, count, filteredSource)
          /\ SourceTypedFailurePrefix(order, count, allowed, sourceEvaluate)
                = SourceFailureConstraintPrefix(order, count, filteredSource)
        BY TypedConjunctionAndFailurePrefixesKeepTheRawDomainMeaning, SMT
            DEF filteredSource, InitializationOrder
    <1>6. history[count] \in InitializationResults
        BY <1>2, SMT DEF InitializationHistory, InitializationOrder
    <1>7. SourceTypedInitialResult(order, count, allowed, sourceEvaluate) = history[count]
        BY <1>4, <1>5, <1>6, SMT DEF SourceTypedInitialResult, InitializationResults
    <1>8. \A index \in 1..count :
        \A prior \in [PrefixKeys(order, index - 1) -> Values] :
            filteredSource[index][prior] = filteredGenerated[index][prior]
        BY SMT DEF filteredSource, filteredGenerated, TypedCandidateEvaluators,
            PartialBindings, InitializationOrder, PrefixKeys
    <1>9. \A result : InitializationHistory(TRUE, count, order, filteredGenerated, result)
            => \A index \in 0..count : history[index] = result[index]
        BY <1>1, <1>2, <1>8, InitializationHistoriesRetainAllStatesAndFailures
    <1>. QED BY <1>3, <1>7, <1>9, SMT DEF filteredGenerated, InitializationOrder


=============================================================================
