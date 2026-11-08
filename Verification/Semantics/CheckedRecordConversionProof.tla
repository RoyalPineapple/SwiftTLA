---------------- MODULE CheckedRecordConversionProof ----------------
EXTENDS TLAPS, CheckedRecordConversion

SourceInit == pc = "valid" /\ record = [count |-> 0]
SourceValid == pc = "valid" /\ record["count"] = 0 /\ pc' = "change" /\ UNCHANGED record
SourceChange == pc = "change" /\ pc' = "invalid"
    /\ record' = [record EXCEPT !["count"] = 1]
SourceInvalid == pc = "invalid" /\ record["count"] = 0 /\ pc' = "Done" /\ UNCHANGED record
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, record>>
SourceNext == SourceValid \/ SourceChange \/ SourceInvalid \/ SourceTerminating

SourceNoMatchingCase == (pc = "valid" \/ pc = "invalid") /\ record["count"] # 0
SourceEvaluationOK == ~SourceNoMatchingCase

THEOREM InitialStatePreserved == Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM CheckedViewFailurePreserved ==
    ASSUME DOMAIN record = {"count"}
    PROVE /\ (__SwiftTLANoMatchingCaseFailure0 <=>
                pc = "valid" /\ record["count"] # 0)
          /\ (__SwiftTLANoMatchingCaseFailure2 <=>
                pc = "invalid" /\ record["count"] # 0)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
    BY SMT DEF __SwiftTLANoMatchingCaseFailure0,
        __SwiftTLANoMatchingCaseFailure2,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAAnyEvaluationFailure2,
        __SwiftTLAEvaluationOK, SourceNoMatchingCase, SourceEvaluationOK

THEOREM CompleteLabeledStepsPreserved ==
    ASSUME DOMAIN record = {"count"}
    PROVE /\ (valid <=> SourceValid)
          /\ (change <=> SourceChange)
          /\ (invalid <=> SourceInvalid)
          /\ (Terminating <=> SourceTerminating)
          /\ (Next <=> SourceNext)
    BY SMT DEF valid, change, invalid, Terminating, Next,
        SourceValid, SourceChange, SourceInvalid, SourceTerminating, SourceNext

WrongUncheckedInvalid == pc = "invalid" /\ pc' = "Done" /\ UNCHANGED record

THEOREM OmittingCheckedViewAddsAnEdge ==
    ASSUME pc = "invalid", record = [count |-> 1]
    PROVE ~ENABLED invalid /\ ENABLED WrongUncheckedInvalid
    BY ExpandENABLED, SMT DEF invalid, WrongUncheckedInvalid

=====================================================================
