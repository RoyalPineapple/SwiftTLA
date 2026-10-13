---------------- MODULE EitherDistinctFailuresProof ----------------
EXTENDS TLAPS, EitherDistinctFailuresModel

SourceDomain ==
    /\ divisor \in 0..1
    /\ modulus \in -1..1
    /\ result \in Int

SourceInit == divisor = 0 /\ modulus = -1 /\ result = 0
SourcePick ==
    /\ UNCHANGED <<divisor, modulus>>
    /\ \/ divisor = 1 /\ result' = 1
       \/ modulus = 1 /\ result' = 0

SourceDivisionFailure == divisor = 0
SourceModuloZeroFailure == divisor # 0 /\ modulus = 0
SourceNegativeModuloFailure == divisor # 0 /\ modulus < 0
SourceEvaluationOK ==
    ~(SourceDivisionFailure \/ SourceModuloZeroFailure \/ SourceNegativeModuloFailure)
UngatedNegativeModuloFailure == modulus # 0 /\ modulus < 0

THEOREM EmittedInitialMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedInitialInDomain ==
    Init => SourceDomain
    BY SMT DEF Init, SourceDomain

THEOREM EmittedStepPreservesDomain ==
    ASSUME SourceDomain, pick
    PROVE divisor' \in 0..1 /\ modulus' \in -1..1 /\ result' \in Int
    BY SMT DEF SourceDomain, pick

THEOREM EmittedStepMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, modulus' \in Int, result' \in Int
    PROVE pick <=> SourcePick
    BY SMT DEF pick, SourcePick, SourceDomain

THEOREM EmittedFirstFailureMatchesSource ==
    ASSUME SourceDomain
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLADivisionByZeroFailure0_1 <=> SourceModuloZeroFailure
          /\ __SwiftTLANegativeModuloDivisorFailure0 <=> SourceNegativeModuloFailure
          /\ __SwiftTLANegativeModuloDivisorValue0 = modulus
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY SMT DEF SourceDomain, SourceDivisionFailure, SourceModuloZeroFailure,
        SourceNegativeModuloFailure, SourceEvaluationOK,
        __SwiftTLADivisionByZeroFailure0, __SwiftTLADivisionByZeroDivisor0,
        __SwiftTLAOverflowFailure0, __SwiftTLADivisionByZeroFailure0_1,
        __SwiftTLANegativeModuloDivisorFailure0,
        __SwiftTLANegativeModuloDivisorValue0, __SwiftTLAEvaluationOK

THEOREM CompleteEmittedOutcomeMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, modulus' \in Int, result' \in Int
    PROVE /\ Init <=> SourceInit
          /\ Next <=> SourcePick
          /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLADivisionByZeroFailure0_1 <=> SourceModuloZeroFailure
          /\ __SwiftTLANegativeModuloDivisorFailure0 <=> SourceNegativeModuloFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedInitialMatchesSource, EmittedStepMatchesSource,
       EmittedFirstFailureMatchesSource, SMT DEF Next

THEOREM UngatedLaterFailureWouldDisagree ==
    ASSUME divisor = 0, modulus = -1
    PROVE UngatedNegativeModuloFailure
          /\ ~__SwiftTLANegativeModuloDivisorFailure0
    BY SMT DEF UngatedNegativeModuloFailure,
        __SwiftTLANegativeModuloDivisorFailure0

=============================================================================
