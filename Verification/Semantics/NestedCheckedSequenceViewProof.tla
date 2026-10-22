---------------- MODULE NestedCheckedSequenceViewProof ----------------
EXTENDS TLAPS, NestedCheckedSequenceView

SourceState == numbers = <<1>>
SourceInit == pc = "inspect" /\ SourceState
SourceViewOK == numbers = <<>>
SourceInspect == pc = "inspect" /\ SourceViewOK /\ numbers = <<<<1>>>>
    /\ pc' = "Done" /\ UNCHANGED numbers
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, numbers>>
SourceNext == SourceInspect \/ SourceTerminating
SourceNoMatchingCase == pc = "inspect" /\ ~SourceViewOK
SourceEvaluationOK == ~SourceNoMatchingCase

THEOREM InitialStatePreserved == Init <=> SourceInit
    BY SMT DEF Init, SourceInit, SourceState

THEOREM CheckedViewFailurePreserved ==
    ASSUME SourceState
    PROVE /\ (__SwiftTLANoMatchingCaseFailure0 <=> SourceNoMatchingCase)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
    BY SMT DEF SourceState, __SwiftTLANoMatchingCaseFailure0,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
        SourceViewOK, SourceNoMatchingCase, SourceEvaluationOK

THEOREM CompleteLabeledStepsPreserved ==
    ASSUME SourceState
    PROVE /\ (inspect <=> SourceInspect)
          /\ (Terminating <=> SourceTerminating)
          /\ (Next <=> SourceNext)
    BY SMT DEF SourceState, inspect, Terminating, Next,
        SourceViewOK, SourceInspect, SourceTerminating, SourceNext

WrongUncheckedInspect == pc = "inspect" /\ pc' = "Done" /\ UNCHANGED numbers

THEOREM OmittingCheckedViewAddsAnEdge ==
    ASSUME Init
    PROVE ~ENABLED inspect /\ ENABLED WrongUncheckedInspect
    BY ExpandENABLED, SMT DEF Init, inspect, WrongUncheckedInspect

=====================================================================
