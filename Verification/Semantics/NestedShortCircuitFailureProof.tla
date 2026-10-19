---------------- MODULE NestedShortCircuitFailureProof ----------------
EXTENDS TLAPS, NestedShortCircuitFailureModel, LazyExpressionFailureRule

SourceInit ==
    enabled \in BOOLEAN /\ ready \in BOOLEAN /\ divisor \in 0..1 /\ result = 0
SourceAdvance ==
    enabled /\ (ready \/ divisor = 1) /\ result' = 1
    /\ UNCHANGED <<enabled, ready, divisor>>
SourceLabeledStep(label) == label = "advance" /\ SourceAdvance
EmittedLabeledStep(label) == label = "advance" /\ advance
SourceDivisionByZeroFailure == enabled /\ ~ready /\ divisor = 0
SourceNegativeModuloFailure == enabled /\ ~ready /\ divisor < 0
SourceEvaluationOK ==
    ~SourceDivisionByZeroFailure /\ ~SourceNegativeModuloFailure

SourceInnerOutcome ==
    SourceOrChildOutcome(TRUE, ready, "none", divisor > 0, TRUE,
        IF divisor = 0 THEN "divisionByZero" ELSE "negativeModulo")
EmittedInnerOutcome ==
    RenderedOrChildOutcome(TRUE, ready, "none", divisor > 0, TRUE,
        IF divisor = 0 THEN "divisionByZero" ELSE "negativeModulo")
SourceOuterOutcome ==
    SourceAndChildOutcome(TRUE, enabled, "none",
        SourceInnerOutcome.defined, SourceInnerOutcome.value,
        SourceInnerOutcome.firstFailure)
EmittedOuterOutcome ==
    RenderedAndChildOutcome(TRUE, enabled, "none",
        EmittedInnerOutcome.defined, EmittedInnerOutcome.value,
        EmittedInnerOutcome.firstFailure)

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM NestedOutcomeComposes ==
    ASSUME enabled \in BOOLEAN, ready \in BOOLEAN, divisor \in -1..1
    PROVE /\ SourceInnerOutcome = EmittedInnerOutcome
          /\ SourceOuterOutcome = EmittedOuterOutcome
    PROOF
    <1>1. SourceInnerOutcome = EmittedInnerOutcome
        BY ShortCircuitOrPropagatesChildOutcome, SMT
            DEF SourceInnerOutcome, EmittedInnerOutcome
    <1>2. SourceOuterOutcome = EmittedOuterOutcome
        BY <1>1, ShortCircuitAndPropagatesChildOutcome, SMT
            DEF SourceOuterOutcome, EmittedOuterOutcome,
                SourceAndChildOutcome, RenderedAndChildOutcome
    <1>. QED BY <1>1, <1>2

THEOREM CompleteLabeledStepAgrees ==
    ASSUME enabled \in BOOLEAN, ready \in BOOLEAN,
           divisor \in -1..1, NEW label
    PROVE /\ (advance <=> SourceAdvance)
          /\ (EmittedLabeledStep(label) <=> SourceLabeledStep(label))
    BY SMT DEF advance, SourceAdvance,
        EmittedLabeledStep, SourceLabeledStep

THEOREM CompleteFailureAndEnablednessAgree ==
    ASSUME enabled \in BOOLEAN, ready \in BOOLEAN,
           divisor \in -1..1, result \in Int
    PROVE /\ (SourceOuterOutcome.defined
                  <=> ~__SwiftTLAAnyEvaluationFailure0)
          /\ (SourceOuterOutcome.firstFailure = "divisionByZero"
                  <=> __SwiftTLADivisionByZeroFailure0)
          /\ (SourceOuterOutcome.firstFailure = "negativeModulo"
                  <=> __SwiftTLANegativeModuloDivisorFailure0)
          /\ (SourceOuterOutcome.defined /\ SourceOuterOutcome.value
                  <=> ENABLED advance)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ __SwiftTLANegativeModuloDivisorValue0 = divisor
    BY NestedOutcomeComposes, CompleteLabeledStepAgrees,
        ExpandENABLED, SMT
        DEF SourceInnerOutcome, SourceOuterOutcome,
            SourceOrChildOutcome, SourceAndChildOutcome,
            SourceDivisionByZeroFailure, SourceNegativeModuloFailure,
            SourceEvaluationOK, __SwiftTLAAnyEvaluationFailure0,
            __SwiftTLAEvaluationOK,
            __SwiftTLADivisionByZeroFailure0,
            __SwiftTLANegativeModuloDivisorFailure0,
            __SwiftTLADivisionByZeroDivisor0,
            __SwiftTLANegativeModuloDivisorValue0,
            advance, SourceAdvance

WrongEagerFailure == divisor = 0

THEOREM SkippedNestedFailureIsNotAnOutcome ==
    ASSUME enabled = TRUE, ready = TRUE, divisor = 0
    PROVE /\ ~__SwiftTLADivisionByZeroFailure0
          /\ WrongEagerFailure
          /\ ENABLED advance
    BY ExpandENABLED, SMT
        DEF __SwiftTLADivisionByZeroFailure0,
            WrongEagerFailure, advance

=====================================================================
