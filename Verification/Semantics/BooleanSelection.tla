---- MODULE BooleanSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, flag

vars == <<pc, flag>>

select == (((pc = "select")) = TRUE /\ (IF (\E __binder_SpecParser_360_0 \in {FALSE, TRUE} : TRUE) THEN (LET __atomic_0 == (LET __BooleanSelection_choiceCandidates0 == {__binder_SpecParser_360_0 \in {FALSE, TRUE} : TRUE} IN (CHOOSE __binder_SpecParser_360_0 \in __BooleanSelection_choiceCandidates0 : (\A __BooleanSelection_choiceOther1 \in __BooleanSelection_choiceCandidates0 : (__binder_SpecParser_360_0 = FALSE \/ __BooleanSelection_choiceOther1 = TRUE)))) IN ((TRUE /\ flag' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __binder_SpecParser_360_0 \in {FALSE, TRUE} : TRUE)))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "select") THEN ~((\E __binder_SpecParser_360_0 \in {FALSE, TRUE} : TRUE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED flag /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

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
