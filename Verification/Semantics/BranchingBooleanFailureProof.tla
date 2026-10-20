---------------- MODULE BranchingBooleanFailureProof ----------------
EXTENDS TLAPS, BranchingBooleanFailureModel, BooleanTreeOutcomeComposition

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
SourceElseAndOutcome ==
    SourceAndChildOutcome(TRUE, ready, "none", TRUE, TRUE, "none")
RenderedElseAndOutcome ==
    RenderedAndChildOutcome(TRUE, ready, "none", TRUE, TRUE, "none")
SourceElseOutcome ==
    SourceNotChildOutcome(SourceElseAndOutcome.defined,
        SourceElseAndOutcome.value, SourceElseAndOutcome.firstFailure)
RenderedElseOutcome ==
    RenderedNotChildOutcome(RenderedElseAndOutcome.defined,
        RenderedElseAndOutcome.value, RenderedElseAndOutcome.firstFailure)
SourceTreeOutcome ==
    SourceConditionalChildOutcome(TRUE, enabled, "none",
        SourceThenOutcome.defined, SourceThenOutcome.value,
        SourceThenOutcome.firstFailure, SourceElseOutcome.defined,
        SourceElseOutcome.value, SourceElseOutcome.firstFailure)
RenderedTreeOutcome ==
    RenderedConditionalChildOutcome(TRUE, enabled, "none",
        RenderedThenOutcome.defined, RenderedThenOutcome.value,
        RenderedThenOutcome.firstFailure, RenderedElseOutcome.defined,
        RenderedElseOutcome.value, RenderedElseOutcome.firstFailure)

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM MixedTreeOutcomeComposes ==
    ASSUME enabled \in BOOLEAN, ready \in BOOLEAN, divisor \in -1..1
    PROVE /\ SourceThenOutcome = RenderedThenOutcome
          /\ SourceElseAndOutcome = RenderedElseAndOutcome
          /\ SourceElseOutcome = RenderedElseOutcome
          /\ SourceTreeOutcome = RenderedTreeOutcome
    PROOF
    <1>1. SourceThenOutcome = RenderedThenOutcome
        BY ShortCircuitAndPropagatesChildOutcome, SMT
            DEF SourceThenOutcome, RenderedThenOutcome
    <1>2. SourceElseAndOutcome = RenderedElseAndOutcome
        BY ShortCircuitAndPropagatesChildOutcome, SMT
            DEF SourceElseAndOutcome, RenderedElseAndOutcome
    <1>3. SourceThenOutcome \in Outcomes
          /\ SourceElseAndOutcome \in Outcomes
        BY SMT DEF SourceThenOutcome, SourceElseAndOutcome,
            SourceAndChildOutcome, Outcomes
    <1>4. SourceElseOutcome = RenderedElseOutcome
        BY <1>2, <1>3, NegationPropagatesChildOutcome, SMT
            DEF SourceElseOutcome, RenderedElseOutcome,
                SourceNotChildOutcome, RenderedNotChildOutcome, Outcomes
    <1>5. SourceElseOutcome \in Outcomes
        BY <1>3, SourceNotOutcomeIsComplete, SMT
            DEF SourceElseOutcome
    <1>6. SourceTreeOutcome = RenderedTreeOutcome
        <2>1. SourceConditionalChildOutcome(TRUE, enabled, "none",
                    SourceThenOutcome.defined, SourceThenOutcome.value,
                    SourceThenOutcome.firstFailure,
                    SourceElseOutcome.defined, SourceElseOutcome.value,
                    SourceElseOutcome.firstFailure)
                 = RenderedConditionalChildOutcome(TRUE, enabled, "none",
                    SourceThenOutcome.defined, SourceThenOutcome.value,
                    SourceThenOutcome.firstFailure,
                    SourceElseOutcome.defined, SourceElseOutcome.value,
                    SourceElseOutcome.firstFailure)
            BY <1>3, <1>5,
                ConditionalPropagatesSelectedChildOutcome, SMT
                DEF Outcomes
        <2>. QED BY <1>1, <1>4, <2>1, SMT
            DEF SourceTreeOutcome, RenderedTreeOutcome
    <1>. QED BY <1>1, <1>2, <1>4, <1>6

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
        DEF SourceThenOutcome, SourceElseAndOutcome,
            SourceElseOutcome, SourceTreeOutcome,
            SourceAndChildOutcome, SourceConditionalChildOutcome,
            SourceNotChildOutcome,
            SourceDivisionByZeroFailure, SourceNegativeModuloFailure,
            SourceEvaluationOK, SourceGuard,
            __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
            __SwiftTLADivisionByZeroFailure0,
            __SwiftTLANegativeModuloDivisorFailure0,
            __SwiftTLADivisionByZeroDivisor0,
            __SwiftTLANegativeModuloDivisorValue0,
            advance, SourceAdvance

WrongEagerFailure == divisor = 0
WrongWithoutNegation == ready

THEOREM SkippedBranchFailureIsNotAnOutcome ==
    ASSUME enabled = FALSE, ready = FALSE, divisor = 0
    PROVE /\ ~__SwiftTLADivisionByZeroFailure0
          /\ WrongEagerFailure
          /\ ~WrongWithoutNegation
          /\ ENABLED advance
    BY ExpandENABLED, SMT
        DEF __SwiftTLADivisionByZeroFailure0,
            WrongEagerFailure, WrongWithoutNegation, advance

=====================================================================
