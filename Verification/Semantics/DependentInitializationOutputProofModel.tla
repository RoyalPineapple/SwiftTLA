---- MODULE DependentInitializationOutputProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, seed, choice

vars == <<pc, seed, choice>>

finish == (((pc = "finish")) = TRUE /\ (LET __atomic_0 == choice IN ((TRUE /\ choice' = __atomic_0) /\ (pc' = "Done" /\ UNCHANGED seed))))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED seed /\ UNCHANGED choice)) /\ UNCHANGED pc)

Init ==
  /\ pc = "finish"
  /\ seed \in 0..1
  /\ choice \in (IF (seed = 0) THEN {0} ELSE {0, 1})
  /\ (IF (seed >= (-2 * 1000000000 - 147483648) /\ seed <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE seed \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (choice >= (-2 * 1000000000 - 147483648) /\ choice <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE choice \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next ==
  \/ finish
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, seed, choice>>

====
