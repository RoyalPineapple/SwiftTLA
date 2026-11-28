---- MODULE GeneratedPredicateCaptureProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, matched

vars == <<left, right, matched>>

compare == (LET __atomic_0 == (~(left < right)) IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\ matched' = __atomic_1) /\ (UNCHANGED left /\ UNCHANGED right))))

Init ==
  /\ left = 2
  /\ right = 3
  /\ matched = FALSE
  /\ (IF (left >= (-2 * 1000000000 - 147483648) /\ left <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE left \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (right >= (-2 * 1000000000 - 147483648) /\ right <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE right \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == compare

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, matched>>

====
