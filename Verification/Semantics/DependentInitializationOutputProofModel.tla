---- MODULE DependentInitializationOutputProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, seed, choice

vars == <<pc, seed, choice>>

finish == (IF ((pc = "finish")) = TRUE THEN (LET __atomic_0 == choice IN (IF (IF TRUE THEN choice' = __atomic_0 ELSE FALSE) THEN (IF pc' = "Done" THEN UNCHANGED seed ELSE FALSE) ELSE FALSE)) ELSE FALSE)
Terminating == (IF (IF (IF ((pc = "Done")) = TRUE THEN UNCHANGED pc ELSE FALSE) THEN (IF UNCHANGED seed THEN UNCHANGED choice ELSE FALSE) ELSE FALSE) THEN UNCHANGED pc ELSE FALSE)

Init ==
  /\ pc = "finish"
  /\ seed \in 0..1
  /\ choice \in (IF (seed = 0) THEN {0} ELSE {0, 1})

Next ==
  \/ finish
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, seed, choice>>

====
