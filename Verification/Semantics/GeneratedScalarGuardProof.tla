---------------- MODULE GeneratedScalarGuardProof ----------------
EXTENDS TLAPS, GeneratedScalarGuardProofModel

ModelStateType == left \in Int /\ right \in Int /\ advanced \in BOOLEAN

SourceInit == left \in {2, 4} /\ right = 3 /\ advanced = FALSE

SourceAdvance ==
    /\ left < right
    /\ UNCHANGED <<left, right>>
    /\ advanced' = TRUE

SourceLabeledStep(label) == label = "advance" /\ SourceAdvance
RenderedLabeledStep(label) == label = "advance" /\ advance

THEOREM InitialStatesMatch ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM InitialStatesHaveModelType ==
    Init => ModelStateType
    BY SMT DEF Init, ModelStateType

THEOREM GuardPreservesCompleteLabeledStep ==
    ASSUME ModelStateType, NEW label
    PROVE RenderedLabeledStep(label) <=> SourceLabeledStep(label)
    BY SMT DEF ModelStateType, RenderedLabeledStep,
        SourceLabeledStep, advance, SourceAdvance

THEOREM GuardedStepPreservesModelType ==
    ModelStateType /\ advance => ModelStateType'
    BY SMT DEF ModelStateType, advance

===============================================================
