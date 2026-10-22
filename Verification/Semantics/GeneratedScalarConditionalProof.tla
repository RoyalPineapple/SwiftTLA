---------------- MODULE GeneratedScalarConditionalProof ----------------
EXTENDS TLAPS, GeneratedScalarConditionalProofModel

ModelStateType == left \in Int /\ right \in Int /\ selected \in BOOLEAN

SourceInit == left \in {2, 4} /\ right = 3 /\ selected = FALSE

SourceChoose ==
    /\ UNCHANGED <<left, right>>
    /\ selected' = (left < right)

SourceLabeledStep(label) == label = "choose" /\ SourceChoose
RenderedLabeledStep(label) == label = "choose" /\ choose

THEOREM InitialStatesMatch ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM InitialStatesHaveModelType ==
    Init => ModelStateType
    BY SMT DEF Init, ModelStateType

THEOREM ConditionalPreservesCompleteLabeledStep ==
    ASSUME ModelStateType, NEW label
    PROVE RenderedLabeledStep(label) <=> SourceLabeledStep(label)
    BY SMT DEF ModelStateType, RenderedLabeledStep,
        SourceLabeledStep, choose, SourceChoose

THEOREM ConditionalPreservesModelType ==
    ModelStateType /\ choose => ModelStateType'
    BY SMT DEF ModelStateType, choose

===============================================================
