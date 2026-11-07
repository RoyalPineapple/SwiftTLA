---- MODULE GeneratedScalarConditionalProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, selected

vars == <<left, right, selected>>

choose == (IF (left < right) THEN ((LET __atomic_0 == TRUE IN ((TRUE /\ selected' = __atomic_0) /\ (UNCHANGED left /\ UNCHANGED right)))) ELSE ((LET __atomic_1 == FALSE IN ((TRUE /\ selected' = __atomic_1) /\ (UNCHANGED left /\ UNCHANGED right)))))

Init ==
  /\ left \in {2, 4}
  /\ right = 3
  /\ selected = FALSE
  /\ (IF (left >= (-2 * 1000000000 - 147483648) /\ left <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE left \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (right >= (-2 * 1000000000 - 147483648) /\ right <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE right \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == choose

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, selected>>

====
