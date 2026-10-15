---- MODULE DynamicBooleanSequenceSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, candidates, selected

vars == <<pc, candidates, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __PROOF_MEMBER__ \in candidates : TRUE) THEN (LET __atomic_0 == (LET __DynamicBooleanSequenceSelection_choiceCandidates0 == {__PROOF_MEMBER__ \in candidates : TRUE} IN (CHOOSE __PROOF_MEMBER__ \in __DynamicBooleanSequenceSelection_choiceCandidates0 : (\A __DynamicBooleanSequenceSelection_choiceOther1 \in __DynamicBooleanSequenceSelection_choiceCandidates0 : (__PROOF_MEMBER__ = __DynamicBooleanSequenceSelection_choiceOther1 \/ (\E __DynamicBooleanSequenceSelection_choiceIndex2 \in 1..Len(__PROOF_MEMBER__) : IF __DynamicBooleanSequenceSelection_choiceIndex2 <= Len(__DynamicBooleanSequenceSelection_choiceOther1) THEN ((\A __DynamicBooleanSequenceSelection_choicePrefix3 \in 1..(__DynamicBooleanSequenceSelection_choiceIndex2 - 1) : __PROOF_MEMBER__[__DynamicBooleanSequenceSelection_choicePrefix3] = __DynamicBooleanSequenceSelection_choiceOther1[__DynamicBooleanSequenceSelection_choicePrefix3]) /\ (__PROOF_MEMBER__[__DynamicBooleanSequenceSelection_choiceIndex2] = FALSE /\ __DynamicBooleanSequenceSelection_choiceOther1[__DynamicBooleanSequenceSelection_choiceIndex2] = TRUE)) ELSE FALSE) \/ (IF Len(__PROOF_MEMBER__) < Len(__DynamicBooleanSequenceSelection_choiceOther1) THEN (\A __DynamicBooleanSequenceSelection_choicePrefix3 \in 1..Len(__PROOF_MEMBER__) : __PROOF_MEMBER__[__DynamicBooleanSequenceSelection_choicePrefix3] = __DynamicBooleanSequenceSelection_choiceOther1[__DynamicBooleanSequenceSelection_choicePrefix3]) ELSE FALSE))))) IN ((TRUE /\ selected' = __atomic_0) /\ (pc' = "Done" /\ UNCHANGED candidates))) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __PROOF_MEMBER__ \in candidates : TRUE)))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED candidates /\ UNCHANGED selected)) /\ UNCHANGED pc)
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0)

Init ==
  /\ pc = "select"
  /\ candidates = {<<FALSE, TRUE>>, <<FALSE>>, <<TRUE>>}
  /\ selected = <<TRUE>>

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, candidates, selected>>

====
