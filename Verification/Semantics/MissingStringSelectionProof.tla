----------------- MODULE MissingStringSelectionProof -----------------
EXTENDS TLAPS, MissingStringSelection

SourceInit == pc = "select" /\ selected = "none"
SourceSelect ==
    pc = "select"
    /\ \E member \in {"alpha"} :
        FALSE /\ selected' = member /\ pc' = "Done"
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, selected>>
SourceNext == SourceSelect \/ SourceTerminating
SourceFailure ==
    pc = "select" /\ ~(\E member \in {"alpha"} : FALSE)
SourceEvaluationOK == ~SourceFailure

CompiledMatchExists == \E member \in {"alpha"} : FALSE
CompiledSelect ==
    pc = "select" /\ CompiledMatchExists
    /\ selected' = "alpha" /\ pc' = "Done"
CompiledFailure == pc = "select" /\ ~CompiledMatchExists
CompiledNext == CompiledSelect \/ SourceTerminating

SourceLabeledSelect(label) == label = "select" /\ SourceSelect
CompiledLabeledSelect(label) == label = "select" /\ CompiledSelect
EmittedLabeledSelect(label) == label = "select" /\ select
SourceLabeledTerminating(label) ==
    label = "Terminating" /\ SourceTerminating
CompiledLabeledTerminating(label) ==
    label = "Terminating" /\ SourceTerminating
EmittedLabeledTerminating(label) ==
    label = "Terminating" /\ Terminating

THEOREM CompiledStringChoiceHasNoMatch ==
    ~CompiledMatchExists
    BY SMT DEF CompiledMatchExists

THEOREM SourceStringSelectionIsDisabled ==
    ~SourceSelect
    BY SMT DEF SourceSelect

THEOREM EmittedStringSelectionInitialState ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM EmittedStringSelectionIsDisabled ==
    ~select
    BY SMT DEF select

THEOREM CompiledStringSelectionIsDisabled ==
    ~CompiledSelect
    BY CompiledStringChoiceHasNoMatch, SMT DEF CompiledSelect

THEOREM EmittedStringSelectionFailure ==
    __SwiftTLAChoiceFailure0 <=> CompiledFailure
    BY CompiledStringChoiceHasNoMatch, SMT
        DEF __SwiftTLAChoiceFailure0, CompiledFailure

THEOREM CompiledStringFailureMatchesSource ==
    CompiledFailure <=> SourceFailure
    BY CompiledStringChoiceHasNoMatch, SMT
        DEF CompiledFailure, SourceFailure

THEOREM EmittedStringAggregateFailure ==
    __SwiftTLAAnyEvaluationFailure0 <=> SourceFailure
    BY SMT DEF __SwiftTLAAnyEvaluationFailure0, SourceFailure

THEOREM EmittedStringEvaluationCheck ==
    __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedStringAggregateFailure,
        SMT DEF __SwiftTLAEvaluationOK, SourceEvaluationOK

THEOREM EmittedStringTerminatingMatchesSource ==
    Terminating <=> SourceTerminating
    BY SMT DEF Terminating, SourceTerminating

THEOREM CompiledStringCompleteNext ==
    CompiledNext <=> SourceNext
    BY SourceStringSelectionIsDisabled,
        CompiledStringSelectionIsDisabled,
        SMT DEF CompiledNext, SourceNext

THEOREM EmittedStringCompleteNext ==
    Next <=> SourceNext
    BY SourceStringSelectionIsDisabled,
        EmittedStringSelectionIsDisabled,
        EmittedStringTerminatingMatchesSource,
        SMT DEF Next, SourceNext, SourceSelect

THEOREM CompleteMissingStringSelectionSlice ==
    ASSUME NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (CompiledNext <=> SourceNext)
          /\ (Next <=> SourceNext)
          /\ (SourceLabeledSelect(label)
                  <=> CompiledLabeledSelect(label))
          /\ (CompiledLabeledSelect(label)
                  <=> EmittedLabeledSelect(label))
          /\ (SourceLabeledTerminating(label)
                  <=> CompiledLabeledTerminating(label))
          /\ (CompiledLabeledTerminating(label)
                  <=> EmittedLabeledTerminating(label))
          /\ (SourceFailure <=> CompiledFailure)
          /\ (CompiledFailure <=> __SwiftTLAChoiceFailure0)
          /\ (SourceFailure <=> __SwiftTLAAnyEvaluationFailure0)
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY EmittedStringSelectionInitialState, CompiledStringCompleteNext,
        EmittedStringCompleteNext,
        SourceStringSelectionIsDisabled, CompiledStringSelectionIsDisabled,
        EmittedStringSelectionIsDisabled,
        CompiledStringFailureMatchesSource, EmittedStringSelectionFailure,
        EmittedStringAggregateFailure,
        EmittedStringEvaluationCheck, EmittedStringTerminatingMatchesSource,
        SMT DEF SourceLabeledSelect, CompiledLabeledSelect,
            EmittedLabeledSelect, SourceLabeledTerminating,
            CompiledLabeledTerminating, EmittedLabeledTerminating,
            SourceSelect

THEOREM OmittedFailureCheckWouldDisagree ==
    SourceInit => (TRUE # __SwiftTLAEvaluationOK)
    BY EmittedStringEvaluationCheck, SMT
        DEF SourceInit, SourceEvaluationOK, SourceFailure

=======================================================================
