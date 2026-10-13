---- MODULE ConditionalChoiceThenModuloFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES selector, divisor, result

vars == <<selector, divisor, result>>

compute == (IF (\E __CONDITION_MEMBER__ \in {TRUE} : (selector = 1)) THEN (IF (LET __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 == {__CONDITION_MEMBER__ \in {TRUE} : (selector = 1)} IN (CHOOSE __CONDITION_MEMBER__ \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (\A __ConditionalChoiceThenModuloFailureModel_choiceOther1 \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (__CONDITION_MEMBER__ = FALSE \/ __ConditionalChoiceThenModuloFailureModel_choiceOther1 = TRUE)))) THEN ((IF (IF divisor # 0 THEN (IF divisor > 0 THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_0 == (1 % divisor) IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED selector /\ UNCHANGED divisor))) ELSE FALSE)) ELSE ((LET __atomic_1 == 2 IN ((TRUE /\ result' = __atomic_1) /\ (UNCHANGED selector /\ UNCHANGED divisor))))) ELSE FALSE)
__SwiftTLAChoiceFailure0 == ~((\E __CONDITION_MEMBER__ \in {TRUE} : (selector = 1)))
__SwiftTLADivisionByZeroFailure0 == (IF (\E __CONDITION_MEMBER__ \in {TRUE} : (selector = 1)) THEN (IF (LET __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 == {__CONDITION_MEMBER__ \in {TRUE} : (selector = 1)} IN (CHOOSE __CONDITION_MEMBER__ \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (\A __ConditionalChoiceThenModuloFailureModel_choiceOther1 \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (__CONDITION_MEMBER__ = FALSE \/ __ConditionalChoiceThenModuloFailureModel_choiceOther1 = TRUE)))) THEN ~(divisor # 0) ELSE FALSE) ELSE FALSE)
__SwiftTLADivisionByZeroDivisor0 == divisor
__SwiftTLANegativeModuloDivisorFailure0 == (IF (\E __CONDITION_MEMBER__ \in {TRUE} : (selector = 1)) THEN (IF (LET __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 == {__CONDITION_MEMBER__ \in {TRUE} : (selector = 1)} IN (CHOOSE __CONDITION_MEMBER__ \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (\A __ConditionalChoiceThenModuloFailureModel_choiceOther1 \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (__CONDITION_MEMBER__ = FALSE \/ __ConditionalChoiceThenModuloFailureModel_choiceOther1 = TRUE)))) THEN (IF divisor # 0 THEN ~(divisor > 0) ELSE FALSE) ELSE FALSE) ELSE FALSE)
__SwiftTLANegativeModuloDivisorValue0 == divisor
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0) /\ ~(__SwiftTLADivisionByZeroFailure0) /\ ~(__SwiftTLANegativeModuloDivisorFailure0)

Init ==
  /\ selector \in 0..1
  /\ divisor \in 0..1
  /\ result = 0

Next == compute

Spec ==
  /\ Init
  /\ [][Next]_<<selector, divisor, result>>

====
