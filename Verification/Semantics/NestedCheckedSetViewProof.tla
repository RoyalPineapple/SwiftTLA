---------------- MODULE NestedCheckedSetViewProof ----------------
EXTENDS TLAPS, NestedCheckedSetView

SourceState == members \subseteq Int
SourceInit == pc = "inspect" /\ members = {1}
SourceViewOK == members = {}
SourceInspect == pc = "inspect" /\ SourceViewOK
    /\ pc' = "Done" /\ UNCHANGED members
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, members>>
SourceNext == SourceInspect \/ SourceTerminating
SourceNoMatchingCase == pc = "inspect" /\ ~SourceViewOK
SourceEvaluationOK == ~SourceNoMatchingCase

THEOREM EmptyAndNonemptyInputsAreTyped ==
    /\ {} \subseteq Int
    /\ {1} \subseteq Int
    BY SMT

THEOREM EmptySetCardinality == Cardinality({}) = 0
    BY SMT DEF Cardinality

THEOREM InitialStatePreserved == Init <=> SourceInit
    BY SMT DEF Init, SourceInit

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
    BY EmptySetCardinality, SMT DEF SourceState, inspect, Terminating, Next,
        SourceViewOK, SourceInspect, SourceTerminating, SourceNext

WrongUncheckedInspect == pc = "inspect" /\ pc' = "Done" /\ UNCHANGED members

THEOREM OmittingCheckedViewAddsAnEdge ==
    ASSUME Init
    PROVE ~ENABLED inspect /\ ENABLED WrongUncheckedInspect
    BY ExpandENABLED, SMT DEF Init, inspect, WrongUncheckedInspect

=====================================================================
