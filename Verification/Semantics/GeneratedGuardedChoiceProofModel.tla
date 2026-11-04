---- MODULE GeneratedGuardedChoiceProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES selected

choose == (((selected = 0)) = TRUE /\ (\E __atomic_0 \in 1..2: (LET __atomic_1 == __atomic_0 IN (TRUE /\ selected' = __atomic_1))))

Init ==
  /\ selected = 0
  /\ (IF (selected >= (-2 * 1000000000 - 147483648) /\ selected <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE selected \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == choose

Spec ==
  /\ Init
  /\ [][Next]_selected

====
