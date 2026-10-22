---------------- MODULE GeneratedPredicateCaptureProof ----------------
EXTENDS TLAPS, GeneratedPredicateCaptureProofModel

ModelStateType == left \in Int /\ right \in Int /\ matched \in BOOLEAN

SourceInit == left = 2 /\ right = 3 /\ matched = FALSE

SourceCompare ==
    /\ UNCHANGED <<left, right>>
    /\ matched' = IF left >= right THEN TRUE ELSE FALSE

SourceLabeledStep(label) == label = "compare" /\ SourceCompare
RenderedLabeledStep(label) == label = "compare" /\ compare

THEOREM InitialStatesMatch ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM InitialStatesHaveModelType ==
    Init => ModelStateType
    BY SMT DEF Init, ModelStateType

THEOREM EmittedPredicatePreservesCompleteLabeledStep ==
    ASSUME ModelStateType, NEW label
    PROVE RenderedLabeledStep(label) <=> SourceLabeledStep(label)
    BY SMT DEF ModelStateType, RenderedLabeledStep,
        SourceLabeledStep, compare, SourceCompare

THEOREM EmittedPredicatePreservesModelType ==
    ModelStateType /\ compare => ModelStateType'
    BY SMT DEF ModelStateType, compare

===============================================================
