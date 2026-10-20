------------- MODULE BranchwiseConjunctionFailureOrderProof -------------
EXTENDS TLAPS, BranchwiseConjunctionFailureOrderModel

SourceDomain ==
    /\ divisor \in 0..1
    /\ modulus \in {-1, 0, 1, 2}
    /\ selected \in Int
    /\ result \in Int

SourceInit ==
    /\ divisor \in 0..1
    /\ modulus \in {-1, 0, 1, 2}
    /\ selected = -1
    /\ result = 0

\* Either is visited branch by branch. The first branch sets selected to zero;
\* both branches then evaluate the shared division before committing a step.
SourcePick ==
    /\ UNCHANGED <<divisor, modulus>>
    /\ divisor = 1
    /\ \/ selected' = 0 /\ result' = 1
       \/ modulus > 0 /\ selected' = 1 % modulus /\ result' = 1

SourceFirstDivisionFailure == divisor = 0
SourceLaterModuloZeroFailure == divisor = 1 /\ modulus = 0
SourceLaterNegativeModuloFailure == divisor = 1 /\ modulus < 0
SourceEvaluationOK == divisor = 1 /\ modulus > 0
UngatedLaterModuloFailure == modulus < 0

THEOREM EmittedInitialMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedInitialInDomain ==
    Init => SourceDomain
    BY SMT DEF Init, SourceDomain

THEOREM EmittedStepPreservesDomain ==
    ASSUME SourceDomain, pick
    PROVE divisor' \in 0..1 /\ modulus' \in {-1, 0, 1, 2}
          /\ selected' \in Int /\ result' \in Int
    BY SMT DEF SourceDomain, pick

THEOREM EmittedStepMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, modulus' \in Int,
           selected' \in Int, result' \in Int
    PROVE pick <=> SourcePick
    BY SMT DEF SourceDomain, SourcePick, pick

THEOREM EmittedFirstFailureMatchesSource ==
    ASSUME SourceDomain
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceFirstDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLADivisionByZeroFailure0_1 <=> SourceLaterModuloZeroFailure
          /\ __SwiftTLANegativeModuloDivisorFailure0 <=> SourceLaterNegativeModuloFailure
          /\ __SwiftTLANegativeModuloDivisorValue0 = modulus
          /\ ~__SwiftTLADivisionByZeroFailure0_2
          /\ ~__SwiftTLAOverflowFailure0_1
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY SMT DEF SourceDomain, SourceFirstDivisionFailure,
        SourceLaterModuloZeroFailure, SourceLaterNegativeModuloFailure,
        SourceEvaluationOK, __SwiftTLADivisionByZeroFailure0,
        __SwiftTLADivisionByZeroDivisor0, __SwiftTLAOverflowFailure0,
        __SwiftTLADivisionByZeroFailure0_1,
        __SwiftTLANegativeModuloDivisorFailure0,
        __SwiftTLANegativeModuloDivisorValue0,
        __SwiftTLADivisionByZeroFailure0_2, __SwiftTLAOverflowFailure0_1,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

THEOREM CompleteEmittedOutcomeMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, modulus' \in Int,
           selected' \in Int, result' \in Int
    PROVE /\ Init <=> SourceInit
          /\ Next <=> SourcePick
          /\ __SwiftTLADivisionByZeroFailure0 <=> SourceFirstDivisionFailure
          /\ __SwiftTLADivisionByZeroFailure0_1 <=> SourceLaterModuloZeroFailure
          /\ __SwiftTLANegativeModuloDivisorFailure0 <=> SourceLaterNegativeModuloFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedInitialMatchesSource, EmittedStepMatchesSource,
       EmittedFirstFailureMatchesSource, SMT DEF Next

THEOREM UngatedLaterFailureWouldDisagree ==
    ASSUME divisor = 0, modulus = -1
    PROVE UngatedLaterModuloFailure
          /\ ~__SwiftTLANegativeModuloDivisorFailure0
    BY SMT DEF UngatedLaterModuloFailure,
        __SwiftTLANegativeModuloDivisorFailure0

=============================================================================
