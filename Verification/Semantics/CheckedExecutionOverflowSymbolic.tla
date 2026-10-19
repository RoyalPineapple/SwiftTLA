---- MODULE CheckedExecutionOverflowSymbolic ----
EXTENDS Integers, FiniteSets, Sequences

CONSTANTS SwiftIntMin, SwiftIntMax

VARIABLES pc, count

vars == <<pc, count>>

advance == (((pc = "advance")) = TRUE /\ (IF (IF (count >= -1000000000 /\ count <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN count <= SwiftIntMax - (1) ELSE IF 1 < 0 THEN count >= SwiftIntMin - (1) ELSE TRUE)) THEN (LET __atomic_0 == (count + 1) IN ((TRUE /\ count' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
__SwiftTLAOverflowFailure0 == (((pc = "advance")) = TRUE /\ ~((IF (count >= -1000000000 /\ count <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN count <= SwiftIntMax - (1) ELSE IF 1 < 0 THEN count >= SwiftIntMin - (1) ELSE TRUE))))
__SwiftTLAOverflowOperands0 == <<count, 1>>
__SwiftTLAOverflowOperation0 == "addition"
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "advance") THEN ~((IF (count >= -1000000000 /\ count <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000) THEN TRUE ELSE (IF 1 > 0 THEN count <= SwiftIntMax - (1) ELSE IF 1 < 0 THEN count >= SwiftIntMin - (1) ELSE TRUE))) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED count /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "advance"
  /\ count = SwiftIntMax

Next ==
  \/ advance
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, count>>

====
