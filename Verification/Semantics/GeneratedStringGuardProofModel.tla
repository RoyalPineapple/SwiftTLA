---- MODULE GeneratedStringGuardProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, advanced

vars == <<left, right, advanced>>

advance == (((IF (IF (left = right) THEN (left = "alpha") ELSE FALSE) THEN (left /= "beta") ELSE FALSE)) = TRUE /\ (LET __atomic_0 == TRUE IN ((TRUE /\ advanced' = __atomic_0) /\ (UNCHANGED left /\ UNCHANGED right))))

Init ==
  /\ left \in {"alpha", "beta"}
  /\ right = "alpha"
  /\ advanced = FALSE

Next == advance

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, advanced>>

====
