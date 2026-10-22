---- MODULE DynamicSequenceSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, candidates, selected

vars == <<pc, candidates, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __PROOF_MEMBER__ \in candidates : TRUE) THEN (LET __atomic_0 == (LET __DynamicSequenceSelection_choiceCandidates0 == {__PROOF_MEMBER__ \in candidates : TRUE} IN (CHOOSE __PROOF_MEMBER__ \in __DynamicSequenceSelection_choiceCandidates0 : (\A __DynamicSequenceSelection_choiceOther1 \in __DynamicSequenceSelection_choiceCandidates0 : (__PROOF_MEMBER__ = __DynamicSequenceSelection_choiceOther1 \/ (\E __DynamicSequenceSelection_choiceIndex2 \in 1..Len(__PROOF_MEMBER__) : IF __DynamicSequenceSelection_choiceIndex2 <= Len(__DynamicSequenceSelection_choiceOther1) THEN ((\A __DynamicSequenceSelection_choicePrefix3 \in 1..(__DynamicSequenceSelection_choiceIndex2 - 1) : __PROOF_MEMBER__[__DynamicSequenceSelection_choicePrefix3] = __DynamicSequenceSelection_choiceOther1[__DynamicSequenceSelection_choicePrefix3]) /\ __PROOF_MEMBER__[__DynamicSequenceSelection_choiceIndex2] < __DynamicSequenceSelection_choiceOther1[__DynamicSequenceSelection_choiceIndex2]) ELSE FALSE) \/ (IF Len(__PROOF_MEMBER__) < Len(__DynamicSequenceSelection_choiceOther1) THEN (\A __DynamicSequenceSelection_choicePrefix3 \in 1..Len(__PROOF_MEMBER__) : __PROOF_MEMBER__[__DynamicSequenceSelection_choicePrefix3] = __DynamicSequenceSelection_choiceOther1[__DynamicSequenceSelection_choicePrefix3]) ELSE FALSE))))) IN ((TRUE /\ selected' = __atomic_0) /\ (pc' = "Done" /\ UNCHANGED candidates))) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __PROOF_MEMBER__ \in candidates : TRUE)))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "select") THEN ~((\E __PROOF_MEMBER__ \in candidates : TRUE)) ELSE FALSE)
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED candidates /\ UNCHANGED selected)) /\ UNCHANGED pc)
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "select"
  /\ candidates = {<<1, 0>>, <<1>>, <<2>>}
  /\ selected = <<2>>

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, candidates, selected>>

====
