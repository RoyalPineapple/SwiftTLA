---------------- MODULE CanonicalCandidateTraversalRule ----------------
EXTENDS TLAPS, Sequences, Integers, NaturalsInduction

CONSTANTS Values, FailureValues, NoFailure

Positions(order) == 1..Len(order)
FailedPositions(order, failure) ==
    {index \in Positions(order) : failure[order[index]] # NoFailure}
FailedIndex(order, failure, index) ==
    index \in Positions(order) /\ failure[order[index]] # NoFailure
FailedValues(order, failure) ==
    {order[index] : index \in FailedPositions(order, failure)}
FirstIndex(order, failure) ==
    CHOOSE index \in FailedPositions(order, failure) :
        \A earlier \in FailedPositions(order, failure) : index <= earlier
FirstValue(order, failure, rank) ==
    CHOOSE value \in FailedValues(order, failure) :
        \A earlier \in FailedValues(order, failure) :
            rank[value] <= rank[earlier]
NativeFailure(order, failure) ==
    IF FailedPositions(order, failure) = {} THEN NoFailure
    ELSE failure[order[FirstIndex(order, failure)]]
FormalFailure(order, failure, rank) ==
    IF FailedValues(order, failure) = {} THEN NoFailure
    ELSE failure[FirstValue(order, failure, rank)]

THEOREM EmptyCandidateFailuresAgree ==
    ASSUME NEW order \in Seq(Values),
           NEW failure \in [Values -> FailureValues \cup {NoFailure}],
           NEW rank \in [Values -> Int],
           FailedPositions(order, failure) = {}
    PROVE NativeFailure(order, failure) = NoFailure
        /\ FormalFailure(order, failure, rank) = NoFailure
    BY SMT DEF NativeFailure, FormalFailure, FailedPositions,
        FailedValues, Positions

THEOREM NonemptyFiniteFailureHasLeast ==
    ASSUME NEW order \in Seq(Values),
           NEW failure \in [Values -> FailureValues \cup {NoFailure}],
           FailedPositions(order, failure) # {}
    PROVE \E least \in FailedPositions(order, failure) :
              \A index \in FailedPositions(order, failure) : least <= index
    PROOF
    <1>1. \E index \in Nat : FailedIndex(order, failure, index)
        BY SMT DEF FailedIndex, FailedPositions, Positions
    <1>2. \E index \in Nat :
             /\ FailedIndex(order, failure, index)
             /\ \A earlier \in 0..(index - 1) :
                    ~FailedIndex(order, failure, earlier)
        BY SmallestNatural, <1>1
    <1>. QED
        BY <1>2, SMT DEF FailedIndex, FailedPositions, Positions

THEOREM OrdinalRanksRespectTraversal ==
    ASSUME NEW order \in Seq(Values),
           NEW rank \in [Values -> Int],
           NEW offset \in Int,
           \A index \in Positions(order) : rank[order[index]] = index + offset
    PROVE \A earlier, later \in Positions(order) :
              earlier < later => rank[order[earlier]] < rank[order[later]]
    BY SMT DEF Positions

THEOREM FirstFailureMatchesStrictCandidateOrder ==
    ASSUME NEW order \in Seq(Values),
           NEW failure \in [Values -> FailureValues \cup {NoFailure}],
           NEW rank \in [Values -> Int],
           NEW least \in FailedPositions(order, failure),
           \A index \in FailedPositions(order, failure) : least <= index,
           \A earlier, later \in Positions(order) :
               earlier < later => rank[order[earlier]] < rank[order[later]]
    PROVE /\ FirstIndex(order, failure) = least
          /\ FirstValue(order, failure, rank) = order[least]
          /\ NativeFailure(order, failure) = FormalFailure(order, failure, rank)
    PROOF
    <1>3. FirstIndex(order, failure) = least
        BY SMT DEF FirstIndex, FailedPositions, Positions
    <1>4. order[least] \in FailedValues(order, failure)
        BY SMT DEF FailedValues
    <1>5. \A value \in FailedValues(order, failure) :
             /\ rank[order[least]] <= rank[value]
             /\ (rank[order[least]] = rank[value] => value = order[least])
        PROOF
        <2>. SUFFICES ASSUME NEW value \in FailedValues(order, failure)
                     PROVE /\ rank[order[least]] <= rank[value]
                           /\ (rank[order[least]] = rank[value]
                               => value = order[least])
            BY SMT
        <2>1. \E index \in FailedPositions(order, failure) :
                 order[index] = value
            BY DEF FailedValues
        <2>2. PICK index \in FailedPositions(order, failure) :
                 order[index] = value
            BY <2>1
        <2>3. least <= index
            BY SMT
        <2>4. index \in Positions(order) /\ least \in Positions(order)
            BY <2>2, SMT DEF FailedPositions
        <2>5. rank[order[least]] <= rank[order[index]]
            BY <2>3, <2>4, SMT DEF Positions
        <2>6. rank[order[least]] = rank[order[index]]
               => index = least
            BY <2>3, <2>4, SMT DEF Positions
        <2>. QED
            BY <2>2, <2>5, <2>6, SMT
    <1>6. \E value \in FailedValues(order, failure) :
             \A earlier \in FailedValues(order, failure) :
                 rank[value] <= rank[earlier]
        BY <1>4, <1>5, SMT
    <1>7. FirstValue(order, failure, rank) \in FailedValues(order, failure)
           /\ \A earlier \in FailedValues(order, failure) :
                  rank[FirstValue(order, failure, rank)] <= rank[earlier]
        BY <1>6 DEF FirstValue
    <1>8. rank[FirstValue(order, failure, rank)] <= rank[order[least]]
        BY <1>4, <1>7, SMT
    <1>8a. rank[order[least]] <= rank[FirstValue(order, failure, rank)]
        BY <1>5, <1>7, SMT
    <1>8c. rank[FirstValue(order, failure, rank)] \in Int
            /\ rank[order[least]] \in Int
        BY <1>4, <1>7, SMT
            DEF FailedValues, FailedPositions, Positions
    <1>8b. rank[FirstValue(order, failure, rank)] = rank[order[least]]
        BY <1>8, <1>8a, <1>8c, SMT
    <1>9. FirstValue(order, failure, rank) = order[least]
        BY <1>5, <1>7, <1>8b, SMT
    <1>10. FailedPositions(order, failure) # {}
        BY SMT
    <1>11. FailedValues(order, failure) # {}
        BY <1>4, SMT
    <1>. QED
        BY <1>3, <1>9, <1>10, <1>11, SMT
            DEF NativeFailure, FormalFailure

THEOREM AllFiniteCandidateFailuresAgree ==
    ASSUME NEW order \in Seq(Values),
           NEW failure \in [Values -> FailureValues \cup {NoFailure}],
           NEW rank \in [Values -> Int],
           \A earlier, later \in Positions(order) :
               earlier < later => rank[order[earlier]] < rank[order[later]]
    PROVE NativeFailure(order, failure) = FormalFailure(order, failure, rank)
    PROOF
    <1>1. CASE FailedPositions(order, failure) = {}
        BY EmptyCandidateFailuresAgree, <1>1, SMT
    <1>2. CASE FailedPositions(order, failure) # {}
        PROOF
        <2>1. \E least \in FailedPositions(order, failure) :
                 \A index \in FailedPositions(order, failure) : least <= index
            BY NonemptyFiniteFailureHasLeast, <1>2
        <2>2. PICK least \in FailedPositions(order, failure) :
                 \A index \in FailedPositions(order, failure) : least <= index
            BY <2>1
        <2>. QED
            BY FirstFailureMatchesStrictCandidateOrder, <2>2, SMT
    <1>. QED
        BY <1>1, <1>2, SMT

THEOREM FiniteParameterSubsetKeepsGlobalFailureOrder ==
    ASSUME NEW full \in Seq(Values),
           NEW selected \in Seq(Values),
           NEW positions \in Seq(Positions(full)),
           Len(positions) = Len(selected),
           \A index \in Positions(selected) :
               selected[index] = full[positions[index]],
           \A earlier, later \in Positions(selected) :
               earlier < later => positions[earlier] < positions[later],
           NEW rank \in [Values -> Int],
           \A index \in Positions(full) : rank[full[index]] = index - 1,
           NEW failure \in [Values -> FailureValues \cup {NoFailure}]
    PROVE NativeFailure(selected, failure) =
          FormalFailure(selected, failure, rank)
    PROOF
    <1>1. \A earlier, later \in Positions(selected) :
             earlier < later =>
                 rank[selected[earlier]] < rank[selected[later]]
        BY SMT DEF Positions
    <1>. QED
        BY AllFiniteCandidateFailuresAgree, <1>1, SMT

Members(order) == {order[index] : index \in Positions(order)}
SourceEdges(order, updates, state, action) ==
    UNION {{<<state, action, target>> : target \in updates[order[index]]} :
        index \in Positions(order)}
FormalEdges(order, updates, state, action) ==
    UNION {{<<state, action, target>> : target \in updates[candidate]} :
        candidate \in Members(order)}

THEOREM CompleteFiniteAlternativeOutcomeAgrees ==
    ASSUME NEW States,
           NEW order \in Seq(Values),
           NEW updates \in [Values -> SUBSET States],
           NEW failure \in [Values -> FailureValues \cup {NoFailure}],
           NEW rank \in [Values -> Int],
           NEW state \in States,
           NEW action,
           \A earlier, later \in Positions(order) :
               earlier < later => rank[order[earlier]] < rank[order[later]]
    PROVE /\ SourceEdges(order, updates, state, action) =
                 FormalEdges(order, updates, state, action)
          /\ NativeFailure(order, failure) =
                 FormalFailure(order, failure, rank)
    BY AllFiniteCandidateFailuresAgree, SMT
        DEF SourceEdges, FormalEdges, Members, Positions

CandidateHasSomeFailure(candidates, failures, kinds) ==
    \E candidate \in candidates :
        \E kind \in kinds : failures[candidate][kind]
AnyFailureKindHasCandidate(candidates, failures, kinds) ==
    \E kind \in kinds :
        \E candidate \in candidates : failures[candidate][kind]

THEOREM CandidateFailureAggregationPreservesVerdict ==
    ASSUME NEW candidates \in SUBSET Values,
           NEW kinds,
           NEW failures \in [Values -> [kinds -> BOOLEAN]]
    PROVE CandidateHasSomeFailure(candidates, failures, kinds)
        <=> AnyFailureKindHasCandidate(candidates, failures, kinds)
    BY SMT DEF CandidateHasSomeFailure, AnyFailureKindHasCandidate

THEOREM OmittingAFailureKindChangesVerdict ==
    ASSUME NEW candidates \in SUBSET Values,
           NEW kinds,
           NEW failures \in [Values -> [kinds -> BOOLEAN]],
           NEW candidate \in candidates,
           NEW omitted \in kinds,
           failures[candidate][omitted],
           \A value \in candidates :
               \A kind \in kinds \ {omitted} : ~failures[value][kind]
    PROVE CandidateHasSomeFailure(candidates, failures, kinds)
        /\ ~CandidateHasSomeFailure(candidates, failures, kinds \ {omitted})
    BY SMT DEF CandidateHasSomeFailure

THEOREM EarlierFailureShortCircuitsLaterFailure ==
    ASSUME NEW earlier \in BOOLEAN,
           NEW later \in BOOLEAN
    PROVE (earlier \/ (IF earlier THEN FALSE ELSE later))
        <=> (IF earlier THEN TRUE ELSE later)
    BY SMT

=============================================================================
