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
__SwiftTLAAnyEvaluationFailure0 == (~((\E __CONDITION_MEMBER__ \in {TRUE} : (selector = 1))) \/ (IF (\E __CONDITION_MEMBER__ \in {TRUE} : (selector = 1)) THEN (IF (LET __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 == {__CONDITION_MEMBER__ \in {TRUE} : (selector = 1)} IN (CHOOSE __CONDITION_MEMBER__ \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (\A __ConditionalChoiceThenModuloFailureModel_choiceOther1 \in __ConditionalChoiceThenModuloFailureModel_choiceCandidates0 : (__CONDITION_MEMBER__ = FALSE \/ __ConditionalChoiceThenModuloFailureModel_choiceOther1 = TRUE)))) THEN ~((IF divisor # 0 THEN (IF divisor > 0 THEN TRUE ELSE FALSE) ELSE FALSE)) ELSE FALSE) ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ selector \in 0..1
  /\ divisor \in 0..1
  /\ result = 0
  /\ (IF (selector >= (-2 * 1000000000 - 147483648) /\ selector <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE selector \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (divisor >= (-2 * 1000000000 - 147483648) /\ divisor <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE divisor \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (result >= (-2 * 1000000000 - 147483648) /\ result <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE result \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == compute

Spec ==
  /\ Init
  /\ [][Next]_<<selector, divisor, result>>

====
