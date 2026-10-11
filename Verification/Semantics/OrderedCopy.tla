---- MODULE OrderedCopy ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, x, y

vars == <<pc, x, y>>

copy == (((pc = "copy")) = TRUE /\ (IF (IF (x >= -1000000000 /\ x <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN x <= 9223372036854775807 - (1) ELSE IF 1 < 0 THEN x >= -9223372036854775808 - (1) ELSE TRUE)) THEN (LET __atomic_0 == (x + 1) IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\ x' = __atomic_0) /\ (y' = __atomic_1 /\ pc' = "repeatWrites")))) ELSE FALSE))
__SwiftTLAOverflowFailure0 == (((pc = "copy")) = TRUE /\ ~((IF (x >= -1000000000 /\ x <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN x <= 9223372036854775807 - (1) ELSE IF 1 < 0 THEN x >= -9223372036854775808 - (1) ELSE TRUE))))
__SwiftTLAOverflowOperands0 == <<x, 1>>
__SwiftTLAOverflowOperation0 == "addition"
repeatWrites == (((pc = "repeatWrites")) = TRUE /\ (IF (IF (x >= -1000000000 /\ x <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN x <= 9223372036854775807 - (1) ELSE IF 1 < 0 THEN x >= -9223372036854775808 - (1) ELSE TRUE)) THEN (LET __atomic_2 == (x + 1) IN (IF (IF (__atomic_2 >= -1000000000 /\ __atomic_2 <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN __atomic_2 <= 9223372036854775807 - (1) ELSE IF 1 < 0 THEN __atomic_2 >= -9223372036854775808 - (1) ELSE TRUE)) THEN (LET __atomic_3 == (__atomic_2 + 1) IN ((TRUE /\ x' = __atomic_3) /\ (pc' = "Done" /\ UNCHANGED y))) ELSE FALSE)) ELSE FALSE))
__SwiftTLAOverflowFailure1 == (((pc = "repeatWrites")) = TRUE /\ ~((IF (x >= -1000000000 /\ x <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN x <= 9223372036854775807 - (1) ELSE IF 1 < 0 THEN x >= -9223372036854775808 - (1) ELSE TRUE))))
__SwiftTLAOverflowOperands1 == <<x, 1>>
__SwiftTLAOverflowOperation1 == "addition"
__SwiftTLAOverflowFailure1_1 == (((pc = "repeatWrites")) = TRUE /\ (IF (IF (x >= -1000000000 /\ x <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN x <= 9223372036854775807 - (1) ELSE IF 1 < 0 THEN x >= -9223372036854775808 - (1) ELSE TRUE)) THEN (LET __atomic_2 == (x + 1) IN ~((IF (__atomic_2 >= -1000000000 /\ __atomic_2 <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN __atomic_2 <= 9223372036854775807 - (1) ELSE IF 1 < 0 THEN __atomic_2 >= -9223372036854775808 - (1) ELSE TRUE)))) ELSE FALSE))
__SwiftTLAOverflowOperands1_1 == (LET __atomic_2 == (x + 1) IN <<__atomic_2, 1>>)
__SwiftTLAOverflowOperation1_1 == "addition"
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED x /\ UNCHANGED y)) /\ UNCHANGED pc)
__SwiftTLAEvaluationOK == ~(__SwiftTLAOverflowFailure0) /\ ~(__SwiftTLAOverflowFailure1) /\ ~(__SwiftTLAOverflowFailure1_1)

Init ==
  /\ pc = "copy"
  /\ x = 1
  /\ y = 0

Next ==
  \/ copy
  \/ repeatWrites
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, x, y>>

====
