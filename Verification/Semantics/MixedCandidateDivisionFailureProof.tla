---------------- MODULE MixedCandidateDivisionFailureProof ----------------
EXTENDS TLAPS, MixedCandidateDivisionFailureModel

SourceInit == result = 0
SourcePick ==
    \E candidate \in 0..1 :
        IF candidate = 0 THEN FALSE ELSE result' = 1 \div candidate
SourceFailedCandidates == {candidate \in 0..1 : candidate = 0}
SourceDivisionFailure == SourceFailedCandidates # {}
SourceEvaluationOK == ~SourceDivisionFailure
EmittedFailedCandidates == {candidate \in 0..1 : ~(candidate # 0)}

THEOREM IdentityImage ==
    \A members \in SUBSET Int : {member : member \in members} = members
    BY Isa

THEOREM FailedCandidateSetsAgree ==
    EmittedFailedCandidates = SourceFailedCandidates
    BY Isa DEF EmittedFailedCandidates, SourceFailedCandidates

THEOREM EmittedInitialMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedStepMatchesSource ==
    ASSUME result \in Int
    PROVE pick <=> SourcePick
    BY SMT DEF pick, SourcePick

THEOREM EmittedDivisionFailureMatchesSource ==
    ASSUME result \in Int
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = SourceFailedCandidates
    BY IdentityImage, FailedCandidateSetsAgree, SMT
        DEF __SwiftTLADivisionByZeroFailure0,
            __SwiftTLADivisionByZeroDivisor0,
            EmittedFailedCandidates, SourceDivisionFailure

THEOREM EmittedOverflowIsImpossible ==
    ASSUME result \in Int
    PROVE /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLAOverflowOperands0 = {}
    BY SMT DEF __SwiftTLAOverflowFailure0, __SwiftTLAOverflowOperands0

THEOREM EmittedFailureMatchesSource ==
    ASSUME result \in Int
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = SourceFailedCandidates
          /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLAOverflowOperands0 = {}
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
    BY EmittedDivisionFailureMatchesSource, EmittedOverflowIsImpossible,
        SMT DEF __SwiftTLAEvaluationOK, SourceEvaluationOK

THEOREM CompleteEmittedOutcomeMatchesSource ==
    ASSUME result \in Int
    PROVE /\ Init <=> SourceInit
          /\ Next <=> SourcePick
          /\ (__SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure)
          /\ __SwiftTLADivisionByZeroDivisor0 = SourceFailedCandidates
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
    BY EmittedInitialMatchesSource, EmittedStepMatchesSource,
        EmittedFailureMatchesSource DEF Next

=============================================================================
