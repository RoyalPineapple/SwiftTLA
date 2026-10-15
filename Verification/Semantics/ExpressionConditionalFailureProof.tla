--------------- MODULE ExpressionConditionalFailureProof ---------------
EXTENDS TLAPS, ExpressionConditionalFailureModel, LazyExpressionFailureRule,
        OrderedFailureSites

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
SiteGuards ==
    <<SelectedTrueGuard(mode = 1, FALSE),
      SelectedFalseGuard(mode = 1, divisor # 0),
      SelectedFalseGuard(mode = 1, divisor > 0)>>
SiteHistory ==
    [index \in 0..3 |->
        IF index = 0 THEN TRUE
        ELSE IF index = 1 THEN SiteGuards[1]
        ELSE IF index = 2 THEN SiteGuards[1] /\ SiteGuards[2]
        ELSE SiteGuards[1] /\ SiteGuards[2] /\ SiteGuards[3]]

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
        __SwiftTLANegativeModuloDivisorFailure0,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
        __SwiftTLADivisionByZeroDivisor0,
        __SwiftTLANegativeModuloDivisorValue0,
        SourceChoiceFailure, SourceZeroFailure, SourceNegativeFailure,
        SourceEvaluationOK

THEOREM AggregateDetectsExactlyTheDetailedFailures ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE __SwiftTLAAnyEvaluationFailure0 <=>
          (__SwiftTLAChoiceFailure0 \/
           __SwiftTLADivisionByZeroFailure0 \/
           __SwiftTLANegativeModuloDivisorFailure0)
    BY SMT DEF __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAChoiceFailure0,
        __SwiftTLADivisionByZeroFailure0,
        __SwiftTLANegativeModuloDivisorFailure0

THEOREM AggregateInstantiatesOrderedFailureRule ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE __SwiftTLAAnyEvaluationFailure0 <=> SourceAnyFailure(SiteGuards)
    BY AnyOrderedFailureIsExactlyUndefinedness, SMT
        DEF __SwiftTLAAnyEvaluationFailure0,
            SiteGuards, SourcePrefixDefined,
            SelectedTrueGuard, SelectedFalseGuard

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

THEOREM EmittedSitesFormOrderedHistory ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE /\ SiteGuards \in Seq(BOOLEAN)
          /\ SiteHistory \in [0..Len(SiteGuards) -> BOOLEAN]
          /\ RenderedHistory(SiteGuards, SiteHistory)
    BY SMT DEF SiteGuards, SiteHistory, RenderedHistory,
        SelectedTrueGuard, SelectedFalseGuard

THEOREM EmittedFailuresUseOrderedSites ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE /\ (__SwiftTLAChoiceFailure0 <=>
                  RenderedFailureAt(SiteGuards, SiteHistory, 1))
          /\ (__SwiftTLADivisionByZeroFailure0 <=>
                  RenderedFailureAt(SiteGuards, SiteHistory, 2))
          /\ (__SwiftTLANegativeModuloDivisorFailure0 <=>
                  RenderedFailureAt(SiteGuards, SiteHistory, 3))
          /\ (__SwiftTLAEvaluationOK = SiteHistory[3])
    BY SMT DEF __SwiftTLAChoiceFailure0, __SwiftTLADivisionByZeroFailure0,
        __SwiftTLANegativeModuloDivisorFailure0,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
        RenderedFailureAt, SiteGuards, SiteHistory,
        SelectedTrueGuard, SelectedFalseGuard

THEOREM EmittedFailuresComposeWithGenericRule ==
    ASSUME mode \in 0..1, divisor \in 0..1
    PROVE /\ (__SwiftTLAChoiceFailure0 <=>
                  SourceFailureAt(SiteGuards, 1))
          /\ (__SwiftTLADivisionByZeroFailure0 <=>
                  SourceFailureAt(SiteGuards, 2))
          /\ (__SwiftTLANegativeModuloDivisorFailure0 <=>
                  SourceFailureAt(SiteGuards, 3))
          /\ (__SwiftTLAEvaluationOK =
                  SourcePrefixDefined(SiteGuards, 3))
    BY EmittedSitesFormOrderedHistory, EmittedFailuresUseOrderedSites,
        EveryRenderedFailureIsTheSourceFirstFailure,
        OrderedGuardHistoryPreservesDefinedness, SMT
        DEF SiteGuards, SiteHistory

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
