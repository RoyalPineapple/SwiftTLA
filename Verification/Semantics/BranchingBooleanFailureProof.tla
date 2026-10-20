---------------- MODULE BranchingBooleanFailureProof ----------------
EXTENDS TLAPS, BranchingBooleanFailureModel, LazyExpressionFailureRule

SourceInit ==
    enabled \in BOOLEAN /\ ready \in BOOLEAN /\ divisor \in 0..1 /\ result = 0
SourceDivisionByZeroFailure == enabled /\ ready /\ divisor = 0
SourceNegativeModuloFailure == enabled /\ ready /\ divisor < 0
SourceEvaluationOK ==
    ~SourceDivisionByZeroFailure /\ ~SourceNegativeModuloFailure
SourceGuard == IF enabled THEN (ready /\ divisor = 1) ELSE ~ready
SourceAdvance ==
    SourceEvaluationOK /\ SourceGuard /\ result' = 1
    /\ UNCHANGED <<enabled, ready, divisor>>
SourceLabeledStep(label) == label = "advance" /\ SourceAdvance
EmittedLabeledStep(label) == label = "advance" /\ advance

SourceThenOutcome ==
    SourceAndChildOutcome(TRUE, ready, "none", divisor > 0,
        IF divisor > 0 THEN (1 % divisor) = 0 ELSE FALSE,
        IF divisor = 0 THEN "divisionByZero" ELSE "negativeModulo")
RenderedThenOutcome ==
    RenderedAndChildOutcome(TRUE, ready, "none", divisor > 0,
        IF divisor > 0 THEN (1 % divisor) = 0 ELSE FALSE,
        IF divisor = 0 THEN "divisionByZero" ELSE "negativeModulo")
SourceTreeOutcome ==
    SourceConditionalChildOutcome(TRUE, enabled, "none",
        SourceThenOutcome.defined, SourceThenOutcome.value,
        SourceThenOutcome.firstFailure, TRUE, ~ready, "none")
RenderedTreeOutcome ==
    RenderedConditionalChildOutcome(TRUE, enabled, "none",
        RenderedThenOutcome.defined, RenderedThenOutcome.value,
        RenderedThenOutcome.firstFailure, TRUE, ~ready, "none")

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM MixedTreeOutcomeComposes ==
    ASSUME enabled \in BOOLEAN, ready \in BOOLEAN, divisor \in -1..1
    PROVE /\ SourceThenOutcome = RenderedThenOutcome
          /\ SourceTreeOutcome = RenderedTreeOutcome
    PROOF
    <1>1. SourceThenOutcome = RenderedThenOutcome
        BY ShortCircuitAndPropagatesChildOutcome, SMT
            DEF SourceThenOutcome, RenderedThenOutcome
    <1>2. SourceTreeOutcome = RenderedTreeOutcome
        BY <1>1, ConditionalPropagatesSelectedChildOutcome, SMT
            DEF SourceTreeOutcome, RenderedTreeOutcome,
                SourceConditionalChildOutcome,
                RenderedConditionalChildOutcome
    <1>. QED BY <1>1, <1>2

THEOREM CompleteLabeledStepAgrees ==
    ASSUME enabled \in BOOLEAN, ready \in BOOLEAN,
           divisor \in -1..1, NEW label
    PROVE /\ (advance <=> SourceAdvance)
          /\ (EmittedLabeledStep(label) <=> SourceLabeledStep(label))
    BY SMT DEF advance, SourceAdvance, SourceEvaluationOK,
        SourceGuard, SourceDivisionByZeroFailure,
        SourceNegativeModuloFailure, EmittedLabeledStep,
        SourceLabeledStep

THEOREM CompleteFailureAndEnablednessAgree ==
    ASSUME enabled \in BOOLEAN, ready \in BOOLEAN,
           divisor \in -1..1, result \in Int
    PROVE /\ (SourceTreeOutcome.defined
                  <=> ~__SwiftTLAAnyEvaluationFailure0)
          /\ (SourceTreeOutcome.firstFailure = "divisionByZero"
                  <=> __SwiftTLADivisionByZeroFailure0)
          /\ (SourceTreeOutcome.firstFailure = "negativeModulo"
                  <=> __SwiftTLANegativeModuloDivisorFailure0)
          /\ (SourceTreeOutcome.defined /\ SourceTreeOutcome.value
                  <=> ENABLED advance)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ __SwiftTLANegativeModuloDivisorValue0 = divisor
    BY MixedTreeOutcomeComposes, CompleteLabeledStepAgrees,
        ExpandENABLED, SMT
        DEF SourceThenOutcome, SourceTreeOutcome,
            SourceAndChildOutcome, SourceConditionalChildOutcome,
            SourceDivisionByZeroFailure, SourceNegativeModuloFailure,
            SourceEvaluationOK, SourceGuard,
            __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
            __SwiftTLADivisionByZeroFailure0,
            __SwiftTLANegativeModuloDivisorFailure0,
            __SwiftTLADivisionByZeroDivisor0,
            __SwiftTLANegativeModuloDivisorValue0,
            advance, SourceAdvance

WrongEagerFailure == divisor = 0

THEOREM SkippedBranchFailureIsNotAnOutcome ==
    ASSUME enabled = FALSE, ready = FALSE, divisor = 0
    PROVE /\ ~__SwiftTLADivisionByZeroFailure0
          /\ WrongEagerFailure
          /\ ENABLED advance
    BY ExpandENABLED, SMT
        DEF __SwiftTLADivisionByZeroFailure0,
            WrongEagerFailure, advance

=====================================================================
