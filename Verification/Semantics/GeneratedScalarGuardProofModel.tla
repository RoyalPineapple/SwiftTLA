---- MODULE GeneratedScalarGuardProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, advanced

vars == <<left, right, advanced>>

advance == (((left < right)) = TRUE /\ (LET __atomic_0 == TRUE IN ((TRUE /\ advanced' = __atomic_0) /\ (UNCHANGED left /\ UNCHANGED right))))

Init ==
  /\ left \in {2, 4}
  /\ right = 3
  /\ advanced = FALSE

Next == advance

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, advanced>>

====
