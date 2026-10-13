--------------- MODULE ExpressionConditionalFailureProof ---------------
EXTENDS TLAPS, ExpressionConditionalFailureModel, LazyExpressionFailureRule

SourceInit == mode \in 0..1 /\ divisor \in 0..1 /\ result = 0
SourceCompute ==
    mode = 0 /\ divisor = 1 /\ result' = 0
    /\ mode' = mode /\ divisor' = divisor
SourceChoiceFailure == mode = 1
SourceZeroFailure == mode = 0 /\ divisor = 0
SourceNegativeFailure == mode = 0 /\ divisor < 0
SourceEvaluationOK ==
    ~SourceChoiceFailure /\ ~SourceZeroFailure /\ ~SourceNegativeFailure
SourceLabeled(label) == label = "compute" /\ SourceCompute
EmittedLabeled(label) == label = "compute" /\ compute

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM CompleteLabeledStepsAgree ==
    ASSUME mode \in 0..1, divisor \in 0..1, NEW label
    PROVE /\ (compute <=> SourceCompute)
          /\ (Next <=> SourceCompute)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY SMT DEF compute, SourceCompute, Next,
        EmittedLabeled, SourceLabeled

THEOREM InitialSetIsClosedUnderNext ==
    ASSUME Init
    PROVE Next => Init'
    BY CompleteLabeledStepsAgree, SMT
        DEF Init, SourceCompute, Next

THEOREM EmittedFailuresAndCheckAgree ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE /\ (__SwiftTLAChoiceFailure0 <=> SourceChoiceFailure)
          /\ (__SwiftTLADivisionByZeroFailure0 <=> SourceZeroFailure)
          /\ (__SwiftTLANegativeModuloDivisorFailure0 <=> SourceNegativeFailure)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ __SwiftTLANegativeModuloDivisorValue0 = divisor
    BY SMT DEF __SwiftTLAChoiceFailure0, __SwiftTLADivisionByZeroFailure0,
        __SwiftTLANegativeModuloDivisorFailure0, __SwiftTLAEvaluationOK,
        __SwiftTLADivisionByZeroDivisor0,
        __SwiftTLANegativeModuloDivisorValue0,
        SourceChoiceFailure, SourceZeroFailure, SourceNegativeFailure,
        SourceEvaluationOK

THEOREM LazyExpressionRuleInstance ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE /\ (SourceChoiceFailure <=>
                  ~SelectedTrueGuard(mode = 1, FALSE))
          /\ (SourceZeroFailure <=>
                  SelectedTrueGuard(mode = 1, FALSE)
                  /\ ~SelectedFalseGuard(mode = 1, divisor # 0))
          /\ (SourceNegativeFailure <=>
                  SelectedTrueGuard(mode = 1, FALSE)
                  /\ SelectedFalseGuard(mode = 1, divisor # 0)
                  /\ ~SelectedFalseGuard(mode = 1, divisor > 0))
    BY SMT DEF SourceChoiceFailure, SourceZeroFailure,
        SourceNegativeFailure, SelectedTrueGuard, SelectedFalseGuard

THEOREM SuccessfulCheckIffActionEnabled ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE __SwiftTLAEvaluationOK <=> ENABLED compute
    BY CompleteLabeledStepsAgree, EmittedFailuresAndCheckAgree,
        ExpandENABLED, SMT
        DEF compute, SourceCompute, SourceEvaluationOK,
            SourceChoiceFailure, SourceZeroFailure, SourceNegativeFailure

WrongEagerChoiceFailure == mode = 0

THEOREM EagerUnselectedChoiceWouldRejectValidStep ==
    ASSUME mode = 0, divisor = 1
    PROVE /\ ENABLED compute
          /\ ~__SwiftTLAChoiceFailure0
          /\ WrongEagerChoiceFailure
    BY CompleteLabeledStepsAgree, EmittedFailuresAndCheckAgree,
        ExpandENABLED, SMT
        DEF compute, SourceCompute, SourceChoiceFailure, WrongEagerChoiceFailure

======================================================================
