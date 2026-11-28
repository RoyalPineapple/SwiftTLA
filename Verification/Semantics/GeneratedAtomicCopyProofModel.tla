---- MODULE GeneratedAtomicCopyProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES first, second

vars == <<first, second>>

copy == (LET __atomic_0 == second IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\ first' = __atomic_0) /\ second' = __atomic_1)))

Init ==
  /\ first = 0
  /\ second = 1
  /\ (IF (first >= (-2 * 1000000000 - 147483648) /\ first <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE first \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (second >= (-2 * 1000000000 - 147483648) /\ second <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE second \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == copy

Spec ==
  /\ Init
  /\ [][Next]_<<first, second>>

====
