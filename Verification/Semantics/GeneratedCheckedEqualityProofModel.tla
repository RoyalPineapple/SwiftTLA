---- MODULE GeneratedCheckedEqualityProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, matched

vars == <<left, right, matched>>

compare == (IF (IF (left >= -1000000000 /\ left <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN left <= ((9 * 1000000000 + 223372036) * 1000000000 + 854775807) - (1) ELSE IF 1 < 0 THEN left >= ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808) - (1) ELSE TRUE)) THEN (LET __atomic_0 == ((left + 1) = right) IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\ matched' = __atomic_1) /\ (UNCHANGED left /\ UNCHANGED right)))) ELSE FALSE)
__SwiftTLAOverflowFailure0 == ~((IF (left >= -1000000000 /\ left <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN left <= ((9 * 1000000000 + 223372036) * 1000000000 + 854775807) - (1) ELSE IF 1 < 0 THEN left >= ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808) - (1) ELSE TRUE)))
__SwiftTLAOverflowOperands0 == <<left, 1>>
__SwiftTLAOverflowOperation0 == "addition"
__SwiftTLAAnyEvaluationFailure0 == ~((IF (left >= -1000000000 /\ left <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN left <= ((9 * 1000000000 + 223372036) * 1000000000 + 854775807) - (1) ELSE IF 1 < 0 THEN left >= ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808) - (1) ELSE TRUE)))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ left \in {((9 * 1000000000 + 223372036) * 1000000000 + 854775807), 2}
  /\ right = 3
  /\ matched = FALSE

Next == compare

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, matched>>

====
