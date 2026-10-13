--------------- MODULE ConditionalChoiceThenModuloFailureProof ---------------
EXTENDS TLAPS, ConditionalChoiceThenModuloFailureModel, ConditionalOutcomeRules

SourceInit == selector \in 0..1 /\ divisor \in 0..1 /\ result = 0
HasMatch == selector = 1
SourceCompute ==
    HasMatch /\ divisor = 1 /\ result' = 0
    /\ selector' = selector /\ divisor' = divisor
SourceChoiceFailure == ~HasMatch
SourceZeroFailure == HasMatch /\ divisor = 0
SourceNegativeFailure == HasMatch /\ divisor < 0
SourceEvaluationOK ==
    ~SourceChoiceFailure /\ ~SourceZeroFailure /\ ~SourceNegativeFailure
SourceLabeled(label) == label = "compute" /\ SourceCompute
EmittedLabeled(label) == label = "compute" /\ compute

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM CompleteLabeledStepsAgree ==
    ASSUME selector \in 0..1, divisor \in 0..1, NEW label
    PROVE /\ (compute <=> SourceCompute)
          /\ (Next <=> SourceCompute)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY SMT DEF compute, SourceCompute, HasMatch, Next,
        EmittedLabeled, SourceLabeled

THEOREM InitialSetIsClosedUnderNext ==
    ASSUME Init
    PROVE Next => Init'
    BY CompleteLabeledStepsAgree, SMT
        DEF Init, SourceCompute, HasMatch, Next

THEOREM OrderedFailureAndCheckAgree ==
    ASSUME selector \in 0..1, divisor \in 0..1
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
        SourceEvaluationOK, HasMatch

THEOREM ConditionalRuleInstance ==
    ASSUME selector \in 0..1, divisor \in 0..1
    PROVE /\ (compute <=> DefinedConditional(
                   HasMatch, TRUE, SourceCompute, FALSE))
          /\ (__SwiftTLAChoiceFailure0 <=>
                   RenderedConditionFailure(HasMatch))
          /\ (__SwiftTLADivisionByZeroFailure0 <=>
                   RenderedYesFailure(HasMatch, TRUE, divisor = 0))
    BY CompleteLabeledStepsAgree, OrderedFailureAndCheckAgree, SMT
        DEF DefinedConditional, RenderedConditionFailure,
            RenderedYesFailure, SourceCompute, HasMatch,
            SourceChoiceFailure, SourceZeroFailure

WrongElse ==
    selector = 0 /\ divisor = 1 /\ result' = 2
    /\ selector' = selector /\ divisor' = divisor

THEOREM UnguardedElseWouldAddAnEdge ==
    ASSUME selector = 0, divisor = 1
    PROVE /\ ENABLED WrongElse
          /\ ~ENABLED compute
    BY CompleteLabeledStepsAgree, ExpandENABLED, SMT
        DEF WrongElse, SourceCompute, HasMatch, compute

======================================================================
