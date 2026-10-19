---- MODULE SequenceSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, selected

vars == <<pc, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __SELECT_MEMBER__ \in {<<1, 0>>, <<1>>, <<2>>} : TRUE) THEN (LET __atomic_0 == (LET __SequenceSelection_choiceCandidates0 == {__SELECT_MEMBER__ \in {<<1, 0>>, <<1>>, <<2>>} : TRUE} IN (CHOOSE __SELECT_MEMBER__ \in __SequenceSelection_choiceCandidates0 : (\A __SequenceSelection_choiceOther1 \in __SequenceSelection_choiceCandidates0 : (CASE __SELECT_MEMBER__ = <<1>> -> 0 [] __SELECT_MEMBER__ = <<1, 0>> -> 1 [] __SELECT_MEMBER__ = <<2>> -> 2) <= (CASE __SequenceSelection_choiceOther1 = <<1>> -> 0 [] __SequenceSelection_choiceOther1 = <<1, 0>> -> 1 [] __SequenceSelection_choiceOther1 = <<2>> -> 2)))) IN ((TRUE /\ selected' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __SELECT_MEMBER__ \in {<<1, 0>>, <<1>>, <<2>>} : TRUE)))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "select") THEN ~((\E __SELECT_MEMBER__ \in {<<1, 0>>, <<1>>, <<2>>} : TRUE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED selected /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "select"
  /\ selected = <<2>>

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, selected>>

====
