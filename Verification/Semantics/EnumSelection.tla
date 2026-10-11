---- MODULE EnumSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, selected

vars == <<pc, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __binder_SpecParser_517_0 \in {"alpha", "zed"} : TRUE) THEN (LET __atomic_0 == (LET __EnumSelection_choiceCandidates0 == {__binder_SpecParser_517_0 \in {"alpha", "zed"} : TRUE} IN (CHOOSE __binder_SpecParser_517_0 \in __EnumSelection_choiceCandidates0 : (\A __EnumSelection_choiceOther1 \in __EnumSelection_choiceCandidates0 : (CASE __binder_SpecParser_517_0 = "alpha" -> 0 [] __binder_SpecParser_517_0 = "zed" -> 1) <= (CASE __EnumSelection_choiceOther1 = "alpha" -> 0 [] __EnumSelection_choiceOther1 = "zed" -> 1)))) IN ((TRUE /\ selected' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __binder_SpecParser_517_0 \in {"alpha", "zed"} : TRUE)))
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED selected /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0)

Init ==
  /\ pc = "select"
  /\ selected = "zed"

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, selected>>

====
