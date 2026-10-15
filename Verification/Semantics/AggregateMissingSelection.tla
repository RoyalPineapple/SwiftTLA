---- MODULE AggregateMissingSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES selected

select == (IF (IF (\E __PROOF_MEMBER__ \in {1} : FALSE) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == <<(LET __AggregateMissingSelection_choiceCandidates0 == {__PROOF_MEMBER__ \in {1} : FALSE} IN (CHOOSE __PROOF_MEMBER__ \in __AggregateMissingSelection_choiceCandidates0 : (\A __AggregateMissingSelection_choiceOther1 \in __AggregateMissingSelection_choiceCandidates0 : __PROOF_MEMBER__ <= __AggregateMissingSelection_choiceOther1))), 0>> IN (TRUE /\ selected' = __atomic_0)) ELSE FALSE)
__SwiftTLAChoiceFailure0 == ~((\E __PROOF_MEMBER__ \in {1} : FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0)

Init == selected = <<>>

Next == select

Spec ==
  /\ Init
  /\ [][Next]_selected

====
