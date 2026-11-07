---------------- MODULE IncompatibleCheckedRecordViewProof ----------------
EXTENDS TLAPS, IncompatibleCheckedRecordView

SourceInit == pc = "inspect" /\ count = 1
SourceInspect == pc = "inspect" /\ FALSE /\ pc' = "Done" /\ UNCHANGED count
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, count>>
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

WrongUncheckedInspect == pc = "inspect" /\ pc' = "Done" /\ UNCHANGED count

THEOREM OmittingCheckedViewAddsAnEdge ==
    ASSUME Init
    PROVE ~ENABLED inspect /\ ENABLED WrongUncheckedInspect
    BY ExpandENABLED, SMT DEF Init, inspect, WrongUncheckedInspect

=====================================================================
