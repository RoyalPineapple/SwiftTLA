---- MODULE BranchingBooleanFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES enabled, ready, divisor, result

vars == <<enabled, ready, divisor, result>>

advance == ((IF (IF (IF enabled THEN (IF ready THEN divisor # 0 ELSE TRUE) ELSE TRUE) THEN (IF (IF enabled THEN (IF ready THEN divisor > 0 ELSE TRUE) ELSE TRUE) THEN TRUE ELSE FALSE) ELSE FALSE) THEN ((IF enabled THEN (IF ready THEN ((1 % divisor) = 0) ELSE FALSE) ELSE (~(IF ready THEN TRUE ELSE FALSE)))) = TRUE ELSE FALSE) /\ (LET __atomic_0 == 1 IN (((TRUE /\ result' = __atomic_0) /\ (UNCHANGED enabled /\ UNCHANGED ready)) /\ UNCHANGED divisor)))
__SwiftTLADivisionByZeroFailure0 == ~((IF enabled THEN (IF ready THEN divisor # 0 ELSE TRUE) ELSE TRUE))
__SwiftTLADivisionByZeroDivisor0 == divisor
__SwiftTLANegativeModuloDivisorFailure0 == (IF (IF enabled THEN (IF ready THEN divisor # 0 ELSE TRUE) ELSE TRUE) THEN ~((IF enabled THEN (IF ready THEN divisor > 0 ELSE TRUE) ELSE TRUE)) ELSE FALSE)
__SwiftTLANegativeModuloDivisorValue0 == divisor
__SwiftTLAAnyEvaluationFailure0 == ~((IF (IF enabled THEN (IF ready THEN divisor # 0 ELSE TRUE) ELSE TRUE) THEN (IF (IF enabled THEN (IF ready THEN divisor > 0 ELSE TRUE) ELSE TRUE) THEN TRUE ELSE FALSE) ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ enabled \in {FALSE, TRUE}
  /\ ready \in {FALSE, TRUE}
  /\ divisor \in 0..1
  /\ result = 0
  /\ (IF (divisor >= (-2 * 1000000000 - 147483648) /\ divisor <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE divisor \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (result >= (-2 * 1000000000 - 147483648) /\ result <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE result \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == advance

Spec ==
  /\ Init
  /\ [][Next]_<<enabled, ready, divisor, result>>

====
