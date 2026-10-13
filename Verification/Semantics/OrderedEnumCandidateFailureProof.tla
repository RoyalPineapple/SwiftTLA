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
EmittedFailedCandidates == {__atomic_0 \in {"alpha", "zed"}: (~((IF (__atomic_0 = "alpha") THEN divisor # 0 ELSE TRUE)) \/ (IF (IF (__atomic_0 = "alpha") THEN divisor # 0 ELSE TRUE) THEN ~((IF (__atomic_0 = "alpha") THEN divisor > 0 ELSE TRUE)) ELSE FALSE) \/ (IF (IF (__atomic_0 = "alpha") THEN divisor # 0 ELSE TRUE) THEN (IF (IF (__atomic_0 = "alpha") THEN divisor > 0 ELSE TRUE) THEN ~((IF (__atomic_0 = "alpha") THEN TRUE ELSE modulus # 0)) ELSE FALSE) ELSE FALSE) \/ (IF (IF (__atomic_0 = "alpha") THEN divisor # 0 ELSE TRUE) THEN (IF (IF (__atomic_0 = "alpha") THEN divisor > 0 ELSE TRUE) THEN (IF (IF (__atomic_0 = "alpha") THEN TRUE ELSE modulus # 0) THEN ~((IF (__atomic_0 = "alpha") THEN TRUE ELSE modulus > 0)) ELSE FALSE) ELSE FALSE) ELSE FALSE))}
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
    BY EmittedFailureSetAtInitialState, EmittedFirstFailureAtInitialState, SMT
        DEF SourceInit, EmittedFailedCandidates, EmittedFirstFailure,
            Members, Rank, __SwiftTLADivisionByZeroFailure0

THEOREM EmittedNegativeModuloAtInitialState ==
    ASSUME SourceInit
    PROVE ~__SwiftTLANegativeModuloDivisorFailure0
    BY EmittedFailureSetAtInitialState, EmittedFirstFailureAtInitialState, SMT
        DEF SourceInit, EmittedFailedCandidates, EmittedFirstFailure,
            Members, Rank, __SwiftTLANegativeModuloDivisorFailure0

THEOREM EmittedSecondSiteFailuresAtInitialState ==
    ASSUME SourceInit
    PROVE /\ ~__SwiftTLADivisionByZeroFailure0_1
          /\ ~__SwiftTLANegativeModuloDivisorFailure0_1
    BY EmittedFailureSetAtInitialState, EmittedFirstFailureAtInitialState, Isa
        DEF SourceInit, EmittedFailedCandidates, EmittedFirstFailure,
            Members, Rank, __SwiftTLADivisionByZeroFailure0_1,
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
        EmittedSecondSiteFailuresAtInitialState, SMT
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

=============================================================================
