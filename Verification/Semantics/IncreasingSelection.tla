---- MODULE IncreasingSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES position

advance == (LET __atomic_0 == (LET __IncreasingSelection_choiceCandidates0 == {__binder_SpecParser_383_0 \in {1, 2, 3} : (__binder_SpecParser_383_0 > position)} IN (CHOOSE __binder_SpecParser_383_0 \in __IncreasingSelection_choiceCandidates0 : (\A __IncreasingSelection_choiceOther1 \in __IncreasingSelection_choiceCandidates0 : __binder_SpecParser_383_0 <= __IncreasingSelection_choiceOther1))) IN (TRUE /\ position' = __atomic_0))

Init == position = 0

Next == advance

Spec ==
  /\ Init
  /\ [][Next]_position

====
