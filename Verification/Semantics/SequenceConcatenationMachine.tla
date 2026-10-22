---- MODULE SequenceConcatenationMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES front, back

vars == <<front, back>>

combine == (((Len(front) = 1)) = TRUE /\ (LET __atomic_0 == (front \o back) IN ((TRUE /\ front' = __atomic_0) /\ UNCHANGED back)))

bounded == (IF (Len(front) <= 3) THEN (Len(back) = 2) ELSE FALSE)

Init ==
  /\ front = <<1>>
  /\ back = <<2, 2>>

Next == combine

Spec ==
  /\ Init
  /\ [][Next]_<<front, back>>

====
