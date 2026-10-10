---- MODULE BooleanSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, flag

vars == <<pc, flag>>

select == (((pc = "select")) = TRUE /\ (LET __atomic_0 == (LET __BooleanSelection_choiceCandidates0 == {__binder_SpecParser_360_0 \in {FALSE, TRUE} : TRUE} IN (CHOOSE __binder_SpecParser_360_0 \in __BooleanSelection_choiceCandidates0 : (\A __BooleanSelection_choiceOther1 \in __BooleanSelection_choiceCandidates0 : (__binder_SpecParser_360_0 = FALSE \/ __BooleanSelection_choiceOther1 = TRUE)))) IN ((TRUE /\ flag' = __atomic_0) /\ pc' = "Done")))
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED flag /\ UNCHANGED pc))

Init ==
  /\ pc = "select"
  /\ flag = TRUE

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, flag>>

====
