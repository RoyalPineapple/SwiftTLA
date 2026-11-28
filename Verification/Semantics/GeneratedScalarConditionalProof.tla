---------------- MODULE GeneratedScalarConditionalProof ----------------
EXTENDS GeneratedScalarConditionalProofModel, ConditionalOutcomeRules, OrderedScalarCopyRule, NativePendingWriteFold

ModelStateType == left \in Int /\ right \in Int /\ selected \in BOOLEAN

SourceInit == left \in {2, 4} /\ right = 3 /\ selected = FALSE

SourceChoose ==
    /\ UNCHANGED <<left, right>>
    /\ selected' = (left < right)

SourceLabeledStep(label) == label = "choose" /\ SourceChoose
RenderedLabeledStep(label) == label = "choose" /\ choose

\* The fresh native producer supplies actual ordered child identities and scalar write values.
\* ConditionalKernelTests checks the qualified library helper's selection rule.
CONSTANT NativeChooseChildren, NativeChoosePlans, NativeChooseFields

NativeChooseBefore == [left |-> left, right |-> right, selected |-> selected]
NativeChooseAfter == [left |-> left', right |-> right', selected |-> selected']
NativeChooseWrites(plan, captures) ==
    [index \in DOMAIN plan.writes |->
        <<plan.writes[index][1], CopyReferenceValue(NativeChooseBefore, captures, plan.writes[index][2])>>]
NativeChooseBranch(plan) ==
    \E captures :
        /\ CopyCaptureHistory(NativeChooseBefore, plan.captures, captures)
        /\ NativePendingMergesEmit(NativeChooseFields, NativeChooseBefore, NativeChooseAfter,
                Len(plan.writes), NativeChooseWrites(plan, captures))

ExpectedNativeChoosePlan(plan, value) ==
    /\ plan.captures = <<<<"literal", value>>>>
    /\ plan.guards = <<>>
    /\ plan.writes = <<<<"selected", <<"capture", 1>>>>,
                        <<"left", <<"state", "left">>>>,
                        <<"right", <<"state", "right">>>>>>

THEOREM NativeChoosePlanWritesAndPreservesTheEntireFrame ==
    ASSUME NEW plan, NEW value, NativeChooseFields = {"left", "right", "selected"},
           ExpectedNativeChoosePlan(plan, value)
    PROVE NativeChooseBranch(plan) <=> (UNCHANGED <<left, right>> /\ selected' = value)
    PROOF
    <1>count. Len(plan.writes) = 3
        BY ONLY ExpectedNativeChoosePlan(plan, value), SMT DEF ExpectedNativeChoosePlan
    <1>values. NativeChooseWrites(plan, <<value>>) =
        <<<<"selected", value>>, <<"left", left>>, <<"right", right>>>>
        BY ONLY ExpectedNativeChoosePlan(plan, value), SMT
            DEF ExpectedNativeChoosePlan, NativeChooseWrites, CopyReferenceValue, NativeChooseBefore
    <1>knownCapture. CopyCaptureHistory(NativeChooseBefore, plan.captures, <<value>>)
        BY ONLY ExpectedNativeChoosePlan(plan, value), SMT
            DEF ExpectedNativeChoosePlan, CopyCaptureHistory, CopyReferenceValue
    <1>resolved. \A captures :
        CopyCaptureHistory(NativeChooseBefore, plan.captures, captures) =>
            NativeChooseWrites(plan, captures) = NativeChooseWrites(plan, <<value>>)
        PROOF
        <2>. SUFFICES ASSUME NEW captures, CopyCaptureHistory(NativeChooseBefore, plan.captures, captures)
            PROVE NativeChooseWrites(plan, captures) = NativeChooseWrites(plan, <<value>>)
            OBVIOUS
        <2>value. captures[1] = value
            BY ONLY CopyCaptureHistory(NativeChooseBefore, plan.captures, captures),
                ExpectedNativeChoosePlan(plan, value), SMT
                DEF ExpectedNativeChoosePlan, CopyCaptureHistory, CopyReferenceValue
        <2>. QED BY ONLY <2>value, ExpectedNativeChoosePlan(plan, value), SMT
            DEF ExpectedNativeChoosePlan, NativeChooseWrites, CopyReferenceValue
    <1>targets. \A index \in 1..3 : NativeChooseWrites(plan, <<value>>)[index][1] \in NativeChooseFields
        BY ONLY (NativeChooseFields = {"left", "right", "selected"}), <1>values, SMT
    <1>fold. NativePendingMergesEmit(NativeChooseFields, NativeChooseBefore, NativeChooseAfter,
                       3, NativeChooseWrites(plan, <<value>>))
        <=> NativePendingWriteConstraints(NativeChooseFields, NativeChooseBefore, NativeChooseAfter,
                       3, NativeChooseWrites(plan, <<value>>))
        BY ONLY <1>targets, PendingMergeFoldMaterializesExactlyTheCompatibleWrites, SMT
    <1>constraints. NativePendingWriteConstraints(NativeChooseFields, NativeChooseBefore, NativeChooseAfter,
                       3, NativeChooseWrites(plan, <<value>>))
        <=> (UNCHANGED <<left, right>> /\ selected' = value)
        BY ONLY (NativeChooseFields = {"left", "right", "selected"}), <1>values, SetExtensionality, SMT
            DEF NativePendingWriteConstraints, PendingWriteKeys, NativeChooseBefore, NativeChooseAfter
    <1>. QED BY ONLY <1>count, <1>knownCapture, <1>resolved, <1>fold, <1>constraints, SMT DEF NativeChooseBranch

NativeChoose ==
    DefinedConditional(TRUE, left < right, NativeChooseBranch(NativeChoosePlans[NativeChooseChildren[1]]),
            NativeChooseBranch(NativeChoosePlans[NativeChooseChildren[2]]))
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
          /\ ((NativeChooseFields = {"left", "right", "selected"}
                 /\ ExpectedNativeChoosePlan(NativeChoosePlans[NativeChooseChildren[1]], TRUE)
                 /\ ExpectedNativeChoosePlan(NativeChoosePlans[NativeChooseChildren[2]], FALSE))
                => (NativeChooseLabeledStep(label) <=> SourceLabeledStep(label)))
    BY NativeChoosePlanWritesAndPreservesTheEntireFrame, SMT
        DEF ModelStateType, RenderedLabeledStep, SourceLabeledStep, choose, SourceChoose,
            NativeChooseLabeledStep, NativeChoose, DefinedConditional

THEOREM ConditionalPreservesModelType ==
    ModelStateType /\ choose => ModelStateType'
    BY SMT DEF ModelStateType, choose

===============================================================
