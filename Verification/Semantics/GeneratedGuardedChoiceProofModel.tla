---- MODULE GeneratedGuardedChoiceProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES selected

choose == (IF ((selected = 0)) = TRUE THEN (\E __atomic_0 \in 1..2: (LET __atomic_1 == __atomic_0 IN (IF TRUE THEN selected' = __atomic_1 ELSE FALSE))) ELSE FALSE)

Init == selected = 0

Next == choose

Spec ==
  /\ Init
  /\ [][Next]_selected

====
