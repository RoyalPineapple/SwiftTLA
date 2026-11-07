---------------- MODULE NestedCheckedRecordViewProof ----------------
EXTENDS TLAPS, NestedCheckedRecordView

SourceInit == pc = "inspect" /\ record = [nested |-> 1]
SourceInspect == pc = "inspect" /\ FALSE /\ pc' = "Done" /\ UNCHANGED record
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, record>>
SourceNext == SourceInspect \/ SourceTerminating
SourceNoMatchingCase == pc = "inspect"
SourceEvaluationOK == ~SourceNoMatchingCase

THEOREM InitialStatePreserved == Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM CheckedViewFailurePreserved ==
    /\ (__SwiftTLANoMatchingCaseFailure0 <=> SourceNoMatchingCase)
    /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
    BY SMT DEF __SwiftTLANoMatchingCaseFailure0,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
        SourceNoMatchingCase, SourceEvaluationOK

THEOREM CompleteLabeledStepsPreserved ==
    /\ (inspect <=> SourceInspect)
    /\ (Terminating <=> SourceTerminating)
    /\ (Next <=> SourceNext)
    BY SMT DEF inspect, Terminating, Next,
        SourceInspect, SourceTerminating, SourceNext

WrongUncheckedInspect == pc = "inspect" /\ pc' = "Done" /\ UNCHANGED record

THEOREM OmittingCheckedViewAddsAnEdge ==
    ASSUME Init
    PROVE ~ENABLED inspect /\ ENABLED WrongUncheckedInspect
    BY ExpandENABLED, SMT DEF Init, inspect, WrongUncheckedInspect

=====================================================================
