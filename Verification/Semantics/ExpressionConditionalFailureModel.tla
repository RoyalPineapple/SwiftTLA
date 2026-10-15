---- MODULE ExpressionConditionalFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES mode, divisor, result

vars == <<mode, divisor, result>>

compute == (IF (IF (IF (mode = 1) THEN (\E __PROOF_MEMBER__ \in {1} : FALSE) ELSE TRUE) THEN (IF (IF (mode = 1) THEN TRUE ELSE divisor # 0) THEN (IF (IF (mode = 1) THEN TRUE ELSE divisor > 0) THEN TRUE ELSE FALSE) ELSE FALSE) ELSE FALSE) THEN (LET __atomic_0 == (IF (mode = 1) THEN (LET __ExpressionConditionalFailureModel_choiceCandidates0 == {__PROOF_MEMBER__ \in {1} : FALSE} IN (CHOOSE __PROOF_MEMBER__ \in __ExpressionConditionalFailureModel_choiceCandidates0 : (\A __ExpressionConditionalFailureModel_choiceOther1 \in __ExpressionConditionalFailureModel_choiceCandidates0 : __PROOF_MEMBER__ <= __ExpressionConditionalFailureModel_choiceOther1))) ELSE (1 % divisor)) IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED mode /\ UNCHANGED divisor))) ELSE FALSE)
__SwiftTLAChoiceFailure0 == ~((IF (mode = 1) THEN (\E __PROOF_MEMBER__ \in {1} : FALSE) ELSE TRUE))
__SwiftTLADivisionByZeroFailure0 == (IF (IF (mode = 1) THEN (\E __PROOF_MEMBER__ \in {1} : FALSE) ELSE TRUE) THEN ~((IF (mode = 1) THEN TRUE ELSE divisor # 0)) ELSE FALSE)
__SwiftTLADivisionByZeroDivisor0 == divisor
__SwiftTLANegativeModuloDivisorFailure0 == (IF (IF (mode = 1) THEN (\E __PROOF_MEMBER__ \in {1} : FALSE) ELSE TRUE) THEN (IF (IF (mode = 1) THEN TRUE ELSE divisor # 0) THEN ~((IF (mode = 1) THEN TRUE ELSE divisor > 0)) ELSE FALSE) ELSE FALSE)
__SwiftTLANegativeModuloDivisorValue0 == divisor
__SwiftTLAAnyEvaluationFailure0 == ~((IF (IF (mode = 1) THEN (\E __PROOF_MEMBER__ \in {1} : FALSE) ELSE TRUE) THEN (IF (IF (mode = 1) THEN TRUE ELSE divisor # 0) THEN (IF (IF (mode = 1) THEN TRUE ELSE divisor > 0) THEN TRUE ELSE FALSE) ELSE FALSE) ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ mode \in 0..1
  /\ divisor \in 0..1
  /\ result = 0

Next == compute

Spec ==
  /\ Init
  /\ [][Next]_<<mode, divisor, result>>

====
