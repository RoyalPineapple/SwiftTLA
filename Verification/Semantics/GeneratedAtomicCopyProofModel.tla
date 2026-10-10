---- MODULE GeneratedAtomicCopyProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES first, second

vars == <<first, second>>

copy == (LET __atomic_0 == second IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\ first' = __atomic_0) /\ second' = __atomic_1)))

Init ==
  /\ first = 0
  /\ second = 1

Next == copy

Spec ==
  /\ Init
  /\ [][Next]_<<first, second>>

====
