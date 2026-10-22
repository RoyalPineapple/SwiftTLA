---------------- MODULE OrderedEnumCandidateFailureProof ----------------
EXTENDS TLAPS, OrderedEnumCandidateFailuresModel

Members == {"alpha", "zed"}
Rank(member) == CASE member = "alpha" -> 0 [] member = "zed" -> 1
SourceInit == divisor = 0 /\ modulus = -1 /\ result = 0
SourceFailedCandidates ==
    {candidate \in Members :
        IF candidate = "alpha" THEN divisor = 0 ELSE modulus < 0}
SourceFirstFailure ==
    CHOOSE candidate \in SourceFailedCandidates :
        \A other \in SourceFailedCandidates : Rank(candidate) <= Rank(other)
SourceDivisionByZero == SourceFirstFailure = "alpha" /\ divisor = 0
SourceNegativeModulo == SourceFirstFailure = "zed" /\ modulus < 0
SourceEvaluationOK == ~(SourceDivisionByZero \/ SourceNegativeModulo)
EmittedFailedCandidates ==
    {__atomic_0 \in {"alpha", "zed"}:
        ~(IF (IF (__atomic_0 = "alpha") THEN divisor # 0 ELSE TRUE)
             THEN (IF (IF (__atomic_0 = "alpha") THEN divisor > 0 ELSE TRUE)
                 THEN (IF (IF (__atomic_0 = "alpha") THEN TRUE ELSE modulus # 0)
                     THEN (IF (IF (__atomic_0 = "alpha") THEN TRUE ELSE modulus > 0)
                         THEN TRUE ELSE FALSE)
                     ELSE FALSE)
                 ELSE FALSE)
             ELSE FALSE)}
EmittedFirstFailure ==
    CHOOSE candidate \in EmittedFailedCandidates :
        \A other \in EmittedFailedCandidates : Rank(candidate) <= Rank(other)

THEOREM CanonicalFailureOrderIsIndependentOfDeclarationOrder ==
    ASSUME SourceInit
    PROVE /\ SourceFailedCandidates = Members
          /\ SourceFirstFailure = "alpha"
    BY SMT DEF SourceInit, SourceFailedCandidates, SourceFirstFailure,
        Members, Rank

THEOREM EmittedFailureSetAtInitialState ==
    ASSUME SourceInit
    PROVE EmittedFailedCandidates = Members
    BY SMT DEF SourceInit, EmittedFailedCandidates, Members

THEOREM EmittedFirstFailureAtInitialState ==
    ASSUME SourceInit
    PROVE EmittedFirstFailure = "alpha"
    BY EmittedFailureSetAtInitialState, SMT
        DEF EmittedFirstFailure, EmittedFailedCandidates, Members, Rank

THEOREM EmittedAggregateFailureAtInitialState ==
    ASSUME SourceInit
    PROVE __SwiftTLAAnyEvaluationFailure0
    BY EmittedFailureSetAtInitialState, SMT
        DEF __SwiftTLAAnyEvaluationFailure0, EmittedFailedCandidates,
            SourceInit, Members

ReversedRank(member) ==
    CASE member = "zed" -> 0 [] member = "alpha" -> 1
ReversedFirstFailure ==
    CHOOSE candidate \in Members :
        \A other \in Members :
            ReversedRank(candidate) <= ReversedRank(other)

THEOREM ReversedOrderChangesFailure ==
    ASSUME SourceInit
    PROVE /\ ReversedFirstFailure = "zed"
          /\ ReversedFirstFailure # SourceFirstFailure
    BY CanonicalFailureOrderIsIndependentOfDeclarationOrder, SMT
        DEF ReversedFirstFailure, ReversedRank, Members

THEOREM EmittedInitialMatchesSource == Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedDivisionByZeroAtInitialState ==
    ASSUME SourceInit
    PROVE __SwiftTLADivisionByZeroFailure0
    BY SMT DEF SourceInit, __SwiftTLADivisionByZeroFailure0

THEOREM EmittedNegativeModuloAtInitialState ==
    ASSUME SourceInit
    PROVE ~__SwiftTLANegativeModuloDivisorFailure0
    BY SMT DEF SourceInit, __SwiftTLANegativeModuloDivisorFailure0

THEOREM EmittedSecondSiteFailuresAtInitialState ==
    ASSUME SourceInit
    PROVE /\ ~__SwiftTLADivisionByZeroFailure0_1
          /\ ~__SwiftTLANegativeModuloDivisorFailure0_1
    BY SMT DEF SourceInit, __SwiftTLADivisionByZeroFailure0_1,
            __SwiftTLANegativeModuloDivisorFailure0_1

THEOREM SourceFailureAtInitialState ==
    ASSUME SourceInit
    PROVE /\ SourceDivisionByZero
          /\ ~SourceNegativeModulo
          /\ ~SourceEvaluationOK
    BY CanonicalFailureOrderIsIndependentOfDeclarationOrder, SMT
        DEF SourceInit, SourceDivisionByZero, SourceNegativeModulo,
            SourceEvaluationOK, SourceFirstFailure, SourceFailedCandidates,
            Members, Rank

THEOREM EmittedInitialFailureMatchesSource ==
    ASSUME SourceInit
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionByZero
          /\ __SwiftTLANegativeModuloDivisorFailure0 <=> SourceNegativeModulo
          /\ ~__SwiftTLADivisionByZeroFailure0_1
          /\ ~__SwiftTLANegativeModuloDivisorFailure0_1
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY SourceFailureAtInitialState,
        EmittedDivisionByZeroAtInitialState,
        EmittedNegativeModuloAtInitialState,
        EmittedSecondSiteFailuresAtInitialState,
        EmittedAggregateFailureAtInitialState, SMT
        DEF __SwiftTLAEvaluationOK

THEOREM CompleteInitialOutcomeMatchesSource ==
    ASSUME Init
    PROVE /\ SourceInit
          /\ ~Next
          /\ __SwiftTLADivisionByZeroFailure0
          /\ ~__SwiftTLANegativeModuloDivisorFailure0
          /\ ~__SwiftTLAEvaluationOK
    BY EmittedInitialMatchesSource, EmittedInitialFailureMatchesSource,
        CanonicalFailureOrderIsIndependentOfDeclarationOrder, SMT
        DEF Next, pick, SourceDivisionByZero, SourceNegativeModulo,
            SourceEvaluationOK, SourceFirstFailure, SourceFailedCandidates,
            Members, Rank, SourceInit

CanonicalOrder == <<"alpha", "zed">>
CandidateFailure == [member \in Members |->
    IF member = "alpha" THEN "divisionByZero" ELSE "negativeModulo"]
CandidateRank == [member \in Members |-> Rank(member)]
Traversal == INSTANCE CanonicalCandidateTraversalRule
    WITH Values <- Members,
         FailureValues <- {"divisionByZero", "negativeModulo"},
         NoFailure <- "none"

THEOREM EmittedInitialFailureUsesCanonicalTraversal ==
    ASSUME SourceInit
    PROVE /\ Traversal!NativeFailure(CanonicalOrder, CandidateFailure)
                 = "divisionByZero"
          /\ Traversal!FormalFailure(CanonicalOrder, CandidateFailure,
                 CandidateRank) = "divisionByZero"
          /\ EmittedFirstFailure = "alpha"
    PROOF
    <1>1. CanonicalOrder \in Seq(Members)
        BY SMT DEF CanonicalOrder, Members
    <1>2. CandidateFailure \in
             [Members -> {"divisionByZero", "negativeModulo", "none"}]
        BY SMT DEF CandidateFailure, Members
    <1>3. CandidateRank \in [Members -> Int]
        BY SMT DEF CandidateRank, Rank, Members
    <1>4. 1 \in Traversal!FailedPositions(CanonicalOrder,
             CandidateFailure)
        BY SMT DEF CanonicalOrder, CandidateFailure, Members,
            Traversal!FailedPositions, Traversal!Positions
    <1>5. \A index \in Traversal!FailedPositions(CanonicalOrder,
             CandidateFailure) : 1 <= index
        BY SMT DEF CanonicalOrder, Traversal!FailedPositions,
            Traversal!Positions
    <1>5a. \A index \in Traversal!Positions(CanonicalOrder) :
              CandidateRank[CanonicalOrder[index]] = index - 1
        BY SMT DEF CanonicalOrder, CandidateRank, Rank, Members,
            Traversal!Positions
    <1>5b. \A index \in Traversal!Positions(CanonicalOrder) :
              CandidateRank[CanonicalOrder[index]] = index + (-1)
        BY <1>5a, SMT DEF Traversal!Positions
    <1>6. \A earlier, later \in Traversal!Positions(CanonicalOrder) :
             earlier < later =>
                 CandidateRank[CanonicalOrder[earlier]]
                     < CandidateRank[CanonicalOrder[later]]
        BY Traversal!OrdinalRanksRespectTraversal,
           <1>1, <1>3, <1>5b, SMT
    <1>7. Traversal!FirstIndex(CanonicalOrder, CandidateFailure) = 1
           /\ Traversal!FirstValue(CanonicalOrder, CandidateFailure,
                  CandidateRank) = "alpha"
           /\ Traversal!NativeFailure(CanonicalOrder, CandidateFailure) =
                  Traversal!FormalFailure(CanonicalOrder,
                      CandidateFailure, CandidateRank)
        BY Traversal!FirstFailureMatchesStrictCandidateOrder,
           <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, SMT
            DEF CanonicalOrder
    <1>. QED
        BY <1>7, EmittedFirstFailureAtInitialState, SMT
            DEF CanonicalOrder, CandidateFailure, CandidateRank,
                Members, Traversal!NativeFailure,
                Traversal!FormalFailure, Traversal!FailedPositions,
                Traversal!FailedValues, Traversal!Positions

=============================================================================
