---------------- MODULE GeneratedScalarConditionalProof ----------------
EXTENDS GeneratedScalarConditionalProofModel, ConditionalOutcomeRules

ModelStateType == left \in Int /\ right \in Int /\ selected \in BOOLEAN

SourceInit == left \in {2, 4} /\ right = 3 /\ selected = FALSE

SourceChoose ==
    /\ UNCHANGED <<left, right>>
    /\ selected' = (left < right)

SourceLabeledStep(label) == label = "choose" /\ SourceChoose
RenderedLabeledStep(label) == label = "choose" /\ choose

\* The fresh native producer supplies actual ordered child identities and scalar write values.
\* ConditionalKernelTests checks the qualified library helper's selection rule.
CONSTANT NativeChooseChildren, NativeChooseValues
NativeChooseChild(child) == selected' = NativeChooseValues[child]
NativeChoose ==
    /\ UNCHANGED <<left, right>>
    /\ DefinedConditional(TRUE, left < right,
            NativeChooseChild(NativeChooseChildren[1]), NativeChooseChild(NativeChooseChildren[2]))
NativeChooseLabeledStep(label) == label = "choose" /\ NativeChoose

THEOREM InitialStatesMatch ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM InitialStatesHaveModelType ==
    Init => ModelStateType
    BY SMT DEF Init, ModelStateType

THEOREM ConditionalPreservesCompleteLabeledStep ==
    ASSUME ModelStateType, NEW label
    PROVE /\ (RenderedLabeledStep(label) <=> SourceLabeledStep(label))
          /\ ((NativeChooseValues[NativeChooseChildren[1]] = TRUE
                 /\ NativeChooseValues[NativeChooseChildren[2]] = FALSE)
                => (NativeChooseLabeledStep(label) <=> SourceLabeledStep(label)))
    BY SMT DEF ModelStateType, RenderedLabeledStep, SourceLabeledStep, choose, SourceChoose,
        NativeChooseLabeledStep, NativeChoose, NativeChooseChild, DefinedConditional

THEOREM ConditionalPreservesModelType ==
    ModelStateType /\ choose => ModelStateType'
    BY SMT DEF ModelStateType, choose

===============================================================
