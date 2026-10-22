---- MODULE GeneratedPredicateCaptureProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES left, right, matched

vars == <<left, right, matched>>

compare == (LET __atomic_0 == (~(left < right)) IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\ matched' = __atomic_1) /\ (UNCHANGED left /\ UNCHANGED right))))

Init ==
  /\ left = 2
  /\ right = 3
  /\ matched = FALSE

Next == compare

Spec ==
  /\ Init
  /\ [][Next]_<<left, right, matched>>

====
