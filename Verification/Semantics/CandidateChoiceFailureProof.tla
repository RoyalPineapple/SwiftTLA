---------------- MODULE CandidateChoiceFailureProof ----------------
EXTENDS TLAPS, CandidateChoiceFailureModel

SourceDomain == result \in Int
SourceInit == result = 0
SourcePick == result' = 1
SourceFailedCandidates == {candidate \in 0..1 : candidate = 0}
SourceChoiceFailure == SourceFailedCandidates # {}
SourceEvaluationOK == ~SourceChoiceFailure
UngatedCandidateSuccess == result' = 1
EmittedFailedCandidates ==
    {candidate \in 0..1 : ~(\E selected \in {1} : selected = candidate)}
EmittedFirstFailedCandidate ==
    CHOOSE first \in EmittedFailedCandidates :
        \A earlier \in EmittedFailedCandidates : first <= earlier

THEOREM EmittedFailedCandidatesAgree ==
    EmittedFailedCandidates = SourceFailedCandidates
    BY SMT DEF EmittedFailedCandidates, SourceFailedCandidates

THEOREM EmittedFirstFailureIsZero == EmittedFirstFailedCandidate = 0
    BY SMT DEF EmittedFirstFailedCandidate, EmittedFailedCandidates

THEOREM EmittedInitialMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedInitialInDomain ==
    Init => SourceDomain
    BY SMT DEF Init, SourceDomain

THEOREM EmittedStepPreservesDomain ==
    ASSUME SourceDomain, pick
    PROVE result' \in Int
    BY SMT DEF SourceDomain, pick

THEOREM EmittedStepMatchesSource ==
    ASSUME SourceDomain, result' \in Int
    PROVE pick <=> SourcePick
    BY SMT DEF pick, SourcePick, SourceDomain

THEOREM EmittedFailureMatchesSource ==
    ASSUME SourceDomain
    PROVE /\ __SwiftTLAChoiceFailure0 <=> SourceChoiceFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedFailedCandidatesAgree, EmittedFirstFailureIsZero, SMT
        DEF SourceDomain, SourceFailedCandidates, SourceChoiceFailure,
            SourceEvaluationOK, EmittedFailedCandidates,
            EmittedFirstFailedCandidate, __SwiftTLAChoiceFailure0,
            __SwiftTLAEvaluationOK

THEOREM CompleteEmittedOutcomeMatchesSource ==
    ASSUME SourceDomain, result' \in Int
    PROVE /\ Init <=> SourceInit
          /\ Next <=> SourcePick
          /\ __SwiftTLAChoiceFailure0 <=> SourceChoiceFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedInitialMatchesSource, EmittedStepMatchesSource,
       EmittedFailureMatchesSource, SMT DEF Next

THEOREM SuccessfulCandidateDoesNotSuppressFailure ==
    ASSUME SourceDomain, result' = 1
    PROVE UngatedCandidateSuccess /\ SourceChoiceFailure
    BY Isa DEF UngatedCandidateSuccess, SourceChoiceFailure,
        SourceFailedCandidates

=============================================================================
