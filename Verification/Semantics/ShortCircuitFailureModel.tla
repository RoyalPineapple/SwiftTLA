---- MODULE ShortCircuitFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES enabled, divisor, result

vars == <<enabled, divisor, result>>

conjunction == ((IF (IF (IF enabled THEN divisor # 0 ELSE TRUE) THEN (IF (IF enabled THEN divisor > 0 ELSE TRUE) THEN TRUE ELSE FALSE) ELSE FALSE) THEN ((IF enabled THEN ((1 % divisor) = 0) ELSE FALSE)) = TRUE ELSE FALSE) /\ (LET __atomic_0 == 1 IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED enabled /\ UNCHANGED divisor))))
__SwiftTLADivisionByZeroFailure0 == ~((IF enabled THEN divisor # 0 ELSE TRUE))
__SwiftTLADivisionByZeroDivisor0 == divisor
__SwiftTLANegativeModuloDivisorFailure0 == (IF (IF enabled THEN divisor # 0 ELSE TRUE) THEN ~((IF enabled THEN divisor > 0 ELSE TRUE)) ELSE FALSE)
__SwiftTLANegativeModuloDivisorValue0 == divisor
__SwiftTLAAnyEvaluationFailure0 == ~((IF (IF enabled THEN divisor # 0 ELSE TRUE) THEN (IF (IF enabled THEN divisor > 0 ELSE TRUE) THEN TRUE ELSE FALSE) ELSE FALSE))
disjunction == ((IF (IF (IF enabled THEN TRUE ELSE divisor # 0) THEN (IF (IF enabled THEN TRUE ELSE divisor > 0) THEN TRUE ELSE FALSE) ELSE FALSE) THEN ((IF enabled THEN TRUE ELSE ((1 % divisor) = 0))) = TRUE ELSE FALSE) /\ (LET __atomic_0 == 2 IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED enabled /\ UNCHANGED divisor))))
__SwiftTLADivisionByZeroFailure1 == ~((IF enabled THEN TRUE ELSE divisor # 0))
__SwiftTLADivisionByZeroDivisor1 == divisor
__SwiftTLANegativeModuloDivisorFailure1 == (IF (IF enabled THEN TRUE ELSE divisor # 0) THEN ~((IF enabled THEN TRUE ELSE divisor > 0)) ELSE FALSE)
__SwiftTLANegativeModuloDivisorValue1 == divisor
__SwiftTLAAnyEvaluationFailure1 == ~((IF (IF enabled THEN TRUE ELSE divisor # 0) THEN (IF (IF enabled THEN TRUE ELSE divisor > 0) THEN TRUE ELSE FALSE) ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0) /\ ~(__SwiftTLAAnyEvaluationFailure1)

Init ==
  /\ enabled \in {FALSE, TRUE}
  /\ divisor \in 0..1
  /\ result = 0

Next ==
  \/ conjunction
  \/ disjunction

Spec ==
  /\ Init
  /\ [][Next]_<<enabled, divisor, result>>

====
