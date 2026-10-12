---- MODULE CheckedGuardOverflow ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, count

vars == <<pc, count>>

advance == ((((pc = "advance")) = TRUE /\ (IF (IF (count >= -1000000000 /\ count <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN count <= ((9 * 1000000000 + 223372036) * 1000000000 + 854775807) - (1) ELSE IF 1 < 0 THEN count >= ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808) - (1) ELSE TRUE)) THEN (((count + 1) > 0)) = TRUE ELSE FALSE)) /\ (LET __atomic_0 == 0 IN ((TRUE /\ count' = __atomic_0) /\ pc' = "Done")))
__SwiftTLAOverflowFailure0 == (((pc = "advance")) = TRUE /\ ~((IF (count >= -1000000000 /\ count <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN count <= ((9 * 1000000000 + 223372036) * 1000000000 + 854775807) - (1) ELSE IF 1 < 0 THEN count >= ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808) - (1) ELSE TRUE))))
__SwiftTLAOverflowOperands0 == <<count, 1>>
__SwiftTLAOverflowOperation0 == "addition"
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED count /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAOverflowFailure0)

Init ==
  /\ pc = "advance"
  /\ count \in {((9 * 1000000000 + 223372036) * 1000000000 + 854775807), 1}

Next ==
  \/ advance
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, count>>

====
