------------- MODULE EitherChoiceAfterDivisionFailureProof -------------
EXTENDS TLAPS, EitherChoiceAfterDivisionFailureModel

SourceDomain == divisor \in 0..1 /\ result \in Int
SourceInit == divisor \in 0..1 /\ result = 0
SourcePick == divisor = 1 /\ divisor' = divisor /\ result' = 1
SourceDivisionFailure == divisor = 0
SourceChoiceFailure == divisor = 1
SourceEvaluationOK == ~(SourceDivisionFailure \/ SourceChoiceFailure)
UngatedChoiceFailure == TRUE

THEOREM EmittedInitialMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedInitialInDomain ==
    Init => SourceDomain
    BY SMT DEF Init, SourceDomain

THEOREM EmittedStepPreservesDomain ==
    ASSUME SourceDomain, pick
    PROVE divisor' \in 0..1 /\ result' \in Int
    BY SMT DEF SourceDomain, pick

THEOREM EmittedStepMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, result' \in Int
    PROVE pick <=> SourcePick
    BY SMT DEF pick, SourcePick, SourceDomain

THEOREM EmittedFirstFailureMatchesSource ==
    ASSUME SourceDomain
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLAChoiceFailure0 <=> SourceChoiceFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY SMT DEF SourceDomain, SourceDivisionFailure, SourceChoiceFailure,
        SourceEvaluationOK, __SwiftTLADivisionByZeroFailure0,
        __SwiftTLADivisionByZeroDivisor0, __SwiftTLAOverflowFailure0,
        __SwiftTLAChoiceFailure0, __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAEvaluationOK

THEOREM CompleteEmittedOutcomeMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, result' \in Int
    PROVE /\ Init <=> SourceInit
          /\ Next <=> SourcePick
          /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLAChoiceFailure0 <=> SourceChoiceFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedInitialMatchesSource, EmittedStepMatchesSource,
       EmittedFirstFailureMatchesSource, SMT DEF Next

THEOREM UngatedChoiceFailureWouldDisagree ==
    ASSUME divisor = 0
    PROVE UngatedChoiceFailure /\ ~__SwiftTLAChoiceFailure0
    BY SMT DEF UngatedChoiceFailure, __SwiftTLAChoiceFailure0

=============================================================================
