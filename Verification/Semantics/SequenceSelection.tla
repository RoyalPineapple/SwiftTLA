---- MODULE SequenceSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, selected

vars == <<pc, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __binder_SpecParser_340_0 \in {<<1, 0>>, <<1>>, <<2>>} : TRUE) THEN (LET __atomic_0 == (LET __SequenceSelection_choiceCandidates0 == {__binder_SpecParser_340_0 \in {<<1, 0>>, <<1>>, <<2>>} : TRUE} IN (CHOOSE __binder_SpecParser_340_0 \in __SequenceSelection_choiceCandidates0 : (\A __SequenceSelection_choiceOther1 \in __SequenceSelection_choiceCandidates0 : (CASE __binder_SpecParser_340_0 = <<1>> -> 0 [] __binder_SpecParser_340_0 = <<1, 0>> -> 1 [] __binder_SpecParser_340_0 = <<2>> -> 2) <= (CASE __SequenceSelection_choiceOther1 = <<1>> -> 0 [] __SequenceSelection_choiceOther1 = <<1, 0>> -> 1 [] __SequenceSelection_choiceOther1 = <<2>> -> 2)))) IN ((TRUE /\ selected' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __binder_SpecParser_340_0 \in {<<1, 0>>, <<1>>, <<2>>} : TRUE)))
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED selected /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0)

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
