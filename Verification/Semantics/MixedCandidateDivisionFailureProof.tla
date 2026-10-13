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
EmittedAllFailures ==
    {candidate \in 0..1 :
        (~(candidate # 0) \/
            (IF candidate # 0 THEN
                ~((IF candidate # -1 THEN TRUE
                    ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)))
             ELSE FALSE))}
EmittedFirstFailedCandidate ==
    CHOOSE first \in EmittedAllFailures :
        \A earlier \in EmittedAllFailures : first <= earlier

THEOREM IdentityImage ==
    \A members \in SUBSET Int : {member : member \in members} = members
    BY Isa

THEOREM FailedCandidateSetsAgree ==
    EmittedFailedCandidates = SourceFailedCandidates
    BY Isa DEF EmittedFailedCandidates, SourceFailedCandidates

THEOREM AllFailuresAreDivisionByZero ==
    EmittedAllFailures = SourceFailedCandidates
    BY SMT DEF EmittedAllFailures, SourceFailedCandidates

THEOREM EmittedFirstFailureIsZero == EmittedFirstFailedCandidate = 0
    BY SMT DEF EmittedFirstFailedCandidate, EmittedAllFailures

THEOREM EmittedDivisionFailureIsTrue == __SwiftTLADivisionByZeroFailure0
    BY AllFailuresAreDivisionByZero, EmittedFirstFailureIsZero, SMT
        DEF __SwiftTLADivisionByZeroFailure0, EmittedAllFailures,
            EmittedFirstFailedCandidate

THEOREM EmittedDivisionDivisorIsZero ==
    __SwiftTLADivisionByZeroDivisor0 = {0}
    BY AllFailuresAreDivisionByZero, EmittedFirstFailureIsZero, SMT
        DEF __SwiftTLADivisionByZeroDivisor0, EmittedAllFailures,
            EmittedFirstFailedCandidate

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
    BY EmittedDivisionFailureIsTrue, EmittedDivisionDivisorIsZero,
        FailedCandidateSetsAgree, SMT
        DEF EmittedFailedCandidates, SourceDivisionFailure,
            SourceFailedCandidates

THEOREM EmittedOverflowIsImpossible ==
    ASSUME result \in Int
    PROVE /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLAOverflowOperands0 = {}
    BY AllFailuresAreDivisionByZero, EmittedFirstFailureIsZero, SMT
        DEF __SwiftTLAOverflowFailure0, __SwiftTLAOverflowOperands0,
            EmittedAllFailures, EmittedFirstFailedCandidate

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
