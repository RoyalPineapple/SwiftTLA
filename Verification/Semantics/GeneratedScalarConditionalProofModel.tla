---- MODULE GeneratedScalarConditionalProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, selected

vars == <<left, right, selected>>

choose == (IF (left < right) THEN ((LET __atomic_0 == TRUE IN ((TRUE /\ selected' = __atomic_0) /\ (UNCHANGED left /\ UNCHANGED right)))) ELSE ((LET __atomic_1 == FALSE IN ((TRUE /\ selected' = __atomic_1) /\ (UNCHANGED left /\ UNCHANGED right)))))

Init ==
  /\ left \in {2, 4}
  /\ right = 3
  /\ selected = FALSE

Next == choose

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, selected>>

====
