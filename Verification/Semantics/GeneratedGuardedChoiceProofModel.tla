---- MODULE GeneratedGuardedChoiceProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES selected

choose == (((selected = 0)) = TRUE /\ (\E __atomic_0 \in 1..2: (LET __atomic_1 == __atomic_0 IN (TRUE /\ selected' = __atomic_1))))

Init == selected = 0

Next == choose

Spec ==
  /\ Init
  /\ [][Next]_selected

====
