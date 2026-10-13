---------------- MODULE CanonicalCandidateTraversalRule ----------------
EXTENDS TLAPS, Sequences, Integers, NaturalsInduction

CONSTANTS Values, FailureValues, NoFailure

Positions(order) == 1..Len(order)
FailedPositions(order, failure) ==
    {index \in Positions(order) : failure[order[index]] # NoFailure}
FailedPrefix(order, failure, length) ==
    {index \in 1..length : failure[order[index]] # NoFailure}
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
    <1>. DEFINE P(length) ==
        length \in 0..Len(order) =>
            (FailedPrefix(order, failure, length) # {} =>
                \E least \in FailedPrefix(order, failure, length) :
                    \A index \in FailedPrefix(order, failure, length) :
                        least <= index)
    <1>1. P(0)
        BY SMT DEF P, FailedPrefix
    <1>2. ASSUME NEW length \in Nat, P(length)
          PROVE P(length + 1)
        PROOF
        <2>. SUFFICES ASSUME length + 1 \in 0..Len(order),
                             FailedPrefix(order, failure, length + 1) # {}
                     PROVE \E least \in FailedPrefix(order, failure, length + 1) :
                               \A index \in FailedPrefix(order, failure, length + 1) :
                                   least <= index
            BY SMT DEF P
        <2>1. length \in 0..Len(order)
            BY SMT
        <2>2. FailedPrefix(order, failure, length + 1) =
                 FailedPrefix(order, failure, length) \cup
                     (IF failure[order[length + 1]] # NoFailure
                      THEN {length + 1} ELSE {})
            BY <2>1, SMT DEF FailedPrefix
        <2>3. CASE FailedPrefix(order, failure, length) = {}
            BY <2>2, <2>3, SMT DEF FailedPrefix
        <2>4. CASE FailedPrefix(order, failure, length) # {}
            BY <2>1, <2>2, <2>4, P(length), SMT DEF P, FailedPrefix
        <2>. QED
            BY <2>3, <2>4, SMT
    <1>3. \A length \in Nat : P(length)
        BY <1>1, <1>2, NatInduction
    <1>. QED
        BY <1>3, SMT DEF P, FailedPrefix, FailedPositions, Positions

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

=============================================================================
