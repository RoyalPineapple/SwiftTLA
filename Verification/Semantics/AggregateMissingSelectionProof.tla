--------------- MODULE AggregateMissingSelectionProof ---------------
EXTENDS TLAPS, AggregateMissingSelection

SourceInit == selected = <<>>
SourceSelect == \E member \in {1} :
    FALSE /\ selected' = <<member, 0>>
SourceFailure == ~(\E member \in {1} : FALSE)
SourceEvaluationOK == ~SourceFailure

CompiledInit == selected = <<>>
CompiledMatchExists == \E member \in {1} : FALSE
CompiledSelect == CompiledMatchExists /\ selected' = <<1, 0>>
CompiledFailure == ~CompiledMatchExists
ModeledSwiftSelect ==
    IF CompiledMatchExists THEN selected' = <<1, 0>> ELSE FALSE
ModeledSwiftFailure == ~CompiledMatchExists

SourceLabeledStep(label) == label = "select" /\ SourceSelect
CompiledLabeledStep(label) == label = "select" /\ CompiledSelect
ModeledSwiftLabeledStep(label) == label = "select" /\ ModeledSwiftSelect
EmittedLabeledStep(label) == label = "select" /\ select

THEOREM ChoiceHasNoMatch == ~CompiledMatchExists
    BY SMT DEF CompiledMatchExists

THEOREM SourceAndCompiledStepsAreDisabled ==
    ~SourceSelect /\ ~CompiledSelect
    BY ChoiceHasNoMatch, SMT DEF SourceSelect, CompiledSelect

THEOREM EmittedStepIsDisabled == ~select
    BY SMT DEF select

THEOREM CompleteAggregateMissingChoiceSlice ==
    ASSUME NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (CompiledInit <=> SourceInit)
          /\ (SourceLabeledStep(label) <=> CompiledLabeledStep(label))
          /\ (CompiledLabeledStep(label) <=> ModeledSwiftLabeledStep(label))
          /\ (CompiledLabeledStep(label) <=> EmittedLabeledStep(label))
          /\ (SourceFailure <=> CompiledFailure)
          /\ (CompiledFailure <=> ModeledSwiftFailure)
          /\ (CompiledFailure <=> __SwiftTLAChoiceFailure0)
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY SourceAndCompiledStepsAreDisabled, EmittedStepIsDisabled,
       SMT DEF Init, SourceInit, CompiledInit,
           SourceLabeledStep, CompiledLabeledStep,
           ModeledSwiftLabeledStep, ModeledSwiftSelect,
           EmittedLabeledStep,
           SourceFailure, CompiledFailure, CompiledMatchExists,
           ModeledSwiftFailure,
           __SwiftTLAChoiceFailure0, SourceEvaluationOK,
           __SwiftTLAEvaluationOK

THEOREM OmittingFailureCheckChangesOutcome ==
    Init => (TRUE # __SwiftTLAEvaluationOK)
    BY ChoiceHasNoMatch, SMT
       DEF Init, __SwiftTLAEvaluationOK, __SwiftTLAChoiceFailure0,
           CompiledMatchExists

=====================================================================
