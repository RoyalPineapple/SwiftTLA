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
