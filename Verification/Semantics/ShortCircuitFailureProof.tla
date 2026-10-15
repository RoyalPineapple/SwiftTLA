-------------------- MODULE ShortCircuitFailureProof --------------------
EXTENDS TLAPS, ShortCircuitFailureModel, LazyExpressionFailureRule,
        OrderedFailureSites

SourceInit == enabled \in BOOLEAN /\ divisor \in 0..1 /\ result = 0
SourceConjunction ==
    enabled /\ divisor = 1 /\ result' = 1
    /\ enabled' = enabled /\ divisor' = divisor
SourceDisjunction ==
    (enabled \/ divisor = 1) /\ result' = 2
    /\ enabled' = enabled /\ divisor' = divisor
SourceNext == SourceConjunction \/ SourceDisjunction
SourceLabeled(label) ==
    \/ label = "conjunction" /\ SourceConjunction
    \/ label = "disjunction" /\ SourceDisjunction
EmittedLabeled(label) ==
    \/ label = "conjunction" /\ conjunction
    \/ label = "disjunction" /\ disjunction
SourceConjunctionZeroFailure == enabled /\ divisor = 0
SourceConjunctionNegativeFailure == enabled /\ divisor < 0
SourceDisjunctionZeroFailure == ~enabled /\ divisor = 0
SourceDisjunctionNegativeFailure == ~enabled /\ divisor < 0
SourceEvaluationOK ==
    /\ ~SourceConjunctionZeroFailure
    /\ ~SourceConjunctionNegativeFailure
    /\ ~SourceDisjunctionZeroFailure
    /\ ~SourceDisjunctionNegativeFailure

AndGuards ==
    <<SelectedTrueGuard(enabled, divisor # 0),
      SelectedTrueGuard(enabled, divisor > 0)>>
OrGuards ==
    <<SelectedFalseGuard(enabled, divisor # 0),
      SelectedFalseGuard(enabled, divisor > 0)>>
AndHistory ==
    [index \in 0..2 |->
        IF index = 0 THEN TRUE
        ELSE IF index = 1 THEN AndGuards[1]
        ELSE AndGuards[1] /\ AndGuards[2]]
OrHistory ==
    [index \in 0..2 |->
        IF index = 0 THEN TRUE
        ELSE IF index = 1 THEN OrGuards[1]
        ELSE OrGuards[1] /\ OrGuards[2]]

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM CompleteLabeledStepsAgree ==
    ASSUME enabled \in BOOLEAN, divisor \in 0..1, NEW label
    PROVE /\ (conjunction <=> SourceConjunction)
          /\ (disjunction <=> SourceDisjunction)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY SMT DEF conjunction, disjunction, Next,
        SourceConjunction, SourceDisjunction, SourceNext,
        EmittedLabeled, SourceLabeled

ReachableShape == enabled \in BOOLEAN /\ divisor \in 0..1 /\ result \in 0..2

THEOREM InitialStatesAndStepsStayInReachableShape ==
    /\ (Init => ReachableShape)
    /\ (ReachableShape /\ Next => ReachableShape')
    BY CompleteLabeledStepsAgree, SMT
        DEF Init, ReachableShape, SourceConjunction,
            SourceDisjunction, SourceNext, Next

THEOREM EmittedFailuresAndCheckAgree ==
    ASSUME enabled \in BOOLEAN, divisor \in 0..1
    PROVE /\ (__SwiftTLADivisionByZeroFailure0
                  <=> SourceConjunctionZeroFailure)
          /\ (__SwiftTLANegativeModuloDivisorFailure0
                  <=> SourceConjunctionNegativeFailure)
          /\ (__SwiftTLADivisionByZeroFailure1
                  <=> SourceDisjunctionZeroFailure)
          /\ (__SwiftTLANegativeModuloDivisorFailure1
                  <=> SourceDisjunctionNegativeFailure)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ __SwiftTLADivisionByZeroDivisor1 = divisor
          /\ __SwiftTLANegativeModuloDivisorValue0 = divisor
          /\ __SwiftTLANegativeModuloDivisorValue1 = divisor
    BY SMT DEF __SwiftTLADivisionByZeroFailure0,
        __SwiftTLANegativeModuloDivisorFailure0,
        __SwiftTLADivisionByZeroFailure1,
        __SwiftTLANegativeModuloDivisorFailure1,
        __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAAnyEvaluationFailure1,
        __SwiftTLAEvaluationOK,
        __SwiftTLADivisionByZeroDivisor0,
        __SwiftTLADivisionByZeroDivisor1,
        __SwiftTLANegativeModuloDivisorValue0,
        __SwiftTLANegativeModuloDivisorValue1,
        SourceConjunctionZeroFailure, SourceConjunctionNegativeFailure,
        SourceDisjunctionZeroFailure, SourceDisjunctionNegativeFailure,
        SourceEvaluationOK

THEOREM AggregateDetectsExactlyTheDetailedFailures ==
    ASSUME enabled \in BOOLEAN
    PROVE /\ (__SwiftTLAAnyEvaluationFailure0 <=>
                 (__SwiftTLADivisionByZeroFailure0 \/
                  __SwiftTLANegativeModuloDivisorFailure0))
          /\ (__SwiftTLAAnyEvaluationFailure1 <=>
                 (__SwiftTLADivisionByZeroFailure1 \/
                  __SwiftTLANegativeModuloDivisorFailure1))
    BY SMT DEF __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAAnyEvaluationFailure1,
        __SwiftTLADivisionByZeroFailure0,
        __SwiftTLANegativeModuloDivisorFailure0,
        __SwiftTLADivisionByZeroFailure1,
        __SwiftTLANegativeModuloDivisorFailure1

THEOREM AggregateInstantiatesOrderedFailureRule ==
    ASSUME enabled \in BOOLEAN
    PROVE /\ (__SwiftTLAAnyEvaluationFailure0 <=>
                 SourceAnyFailure(AndGuards))
          /\ (__SwiftTLAAnyEvaluationFailure1 <=>
                 SourceAnyFailure(OrGuards))
    BY AnyOrderedFailureIsExactlyUndefinedness, SMT
        DEF __SwiftTLAAnyEvaluationFailure0,
            __SwiftTLAAnyEvaluationFailure1,
            AndGuards, OrGuards, SourcePrefixDefined,
            SelectedTrueGuard, SelectedFalseGuard

WrongDroppedAggregate == FALSE

THEOREM DroppingTheAggregateLosesAnObservedFailure ==
    ASSUME enabled = TRUE, divisor = 0
    PROVE __SwiftTLAAnyEvaluationFailure0 /\ ~WrongDroppedAggregate
    BY SMT DEF __SwiftTLAAnyEvaluationFailure0, WrongDroppedAggregate

THEOREM BothBooleanActionsInstantiateOrderedSites ==
    ASSUME enabled \in BOOLEAN, divisor \in 0..1
    PROVE /\ AndGuards \in Seq(BOOLEAN)
          /\ OrGuards \in Seq(BOOLEAN)
          /\ AndHistory \in [0..Len(AndGuards) -> BOOLEAN]
          /\ OrHistory \in [0..Len(OrGuards) -> BOOLEAN]
          /\ RenderedHistory(AndGuards, AndHistory)
          /\ RenderedHistory(OrGuards, OrHistory)
    BY SMT DEF AndGuards, OrGuards, AndHistory, OrHistory,
        RenderedHistory, SelectedTrueGuard, SelectedFalseGuard

THEOREM EmittedFailuresFollowGenericFirstFailure ==
    ASSUME enabled \in BOOLEAN, divisor \in 0..1
    PROVE /\ (__SwiftTLADivisionByZeroFailure0
                  <=> SourceFailureAt(AndGuards, 1))
          /\ (__SwiftTLANegativeModuloDivisorFailure0
                  <=> SourceFailureAt(AndGuards, 2))
          /\ (__SwiftTLADivisionByZeroFailure1
                  <=> SourceFailureAt(OrGuards, 1))
          /\ (__SwiftTLANegativeModuloDivisorFailure1
                  <=> SourceFailureAt(OrGuards, 2))
    BY BothBooleanActionsInstantiateOrderedSites,
        EveryRenderedFailureIsTheSourceFirstFailure, SMT
        DEF __SwiftTLADivisionByZeroFailure0,
            __SwiftTLANegativeModuloDivisorFailure0,
            __SwiftTLADivisionByZeroFailure1,
            __SwiftTLANegativeModuloDivisorFailure1,
            SourceFailureAt, AndGuards, OrGuards,
            AndHistory, OrHistory, RenderedFailureAt,
            SelectedTrueGuard, SelectedFalseGuard

THEOREM SuccessfulActionCanCoexistWithAnotherActionFailure ==
    ASSUME enabled = TRUE, divisor = 0
    PROVE /\ __SwiftTLADivisionByZeroFailure0
          /\ ENABLED disjunction
          /\ ~__SwiftTLAEvaluationOK
    BY CompleteLabeledStepsAgree, EmittedFailuresAndCheckAgree,
        ExpandENABLED, SMT
        DEF disjunction, SourceDisjunction,
            SourceConjunctionZeroFailure, SourceEvaluationOK,
            SourceConjunctionNegativeFailure,
            SourceDisjunctionZeroFailure, SourceDisjunctionNegativeFailure

WrongEagerAndFailure == divisor = 0
WrongEagerOrFailure == divisor = 0

THEOREM SkippedBooleanSidesDoNotFail ==
    /\ (enabled = FALSE /\ divisor = 0 =>
                 ~__SwiftTLADivisionByZeroFailure0
                 /\ WrongEagerAndFailure)
          /\ (enabled = TRUE /\ divisor = 0 =>
                 ~__SwiftTLADivisionByZeroFailure1
                 /\ WrongEagerOrFailure)
    BY SMT DEF __SwiftTLADivisionByZeroFailure0,
        __SwiftTLADivisionByZeroFailure1,
        WrongEagerAndFailure, WrongEagerOrFailure

======================================================================
