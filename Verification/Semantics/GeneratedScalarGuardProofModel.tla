---- MODULE GeneratedScalarGuardProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, advanced

vars == <<left, right, advanced>>

advance == (((left < right)) = TRUE /\ (LET __atomic_0 == TRUE IN ((TRUE /\ advanced' = __atomic_0) /\ (UNCHANGED left /\ UNCHANGED right))))

Init ==
  /\ left \in {2, 4}
  /\ right = 3
  /\ advanced = FALSE
  /\ (IF (left >= (-2 * 1000000000 - 147483648) /\ left <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE left \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (right >= (-2 * 1000000000 - 147483648) /\ right <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE right \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == advance

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, advanced>>

====
