---------------- MODULE GeneratedCheckedEqualityProof ----------------
EXTENDS TLAPS, GeneratedCheckedEqualityProofModel

SwiftIntMax == ((9 * 1000000000 + 223372036) * 1000000000 + 854775807)
SwiftIntMin == ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)

WithinSwiftInt(value) ==
    SwiftIntMin <= value /\ value <= SwiftIntMax

SourceInit ==
    /\ left \in {SwiftIntMax, 2}
    /\ right = 3
    /\ matched = FALSE

ModelStateType ==
    /\ left \in {SwiftIntMax, 2}
    /\ right = 3
    /\ matched \in BOOLEAN

SourceCompare ==
    /\ WithinSwiftInt(left + 1)
    /\ left' = left
    /\ right' = right
    /\ matched' = (left + 1 = right)

SourceOverflow == ~WithinSwiftInt(left + 1)
SourceEvaluationOK == ~SourceOverflow
SourceLabeledStep(label) == label = "compare" /\ SourceCompare
RenderedLabeledStep(label) == label = "compare" /\ compare

THEOREM InitialStatesMatch ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit, SwiftIntMax

THEOREM InitialStatesHaveModelType ==
    Init => ModelStateType
    BY SMT DEF Init, ModelStateType, SwiftIntMax

THEOREM EmittedActionAndFailureMatchSource ==
    ASSUME ModelStateType, NEW label
    PROVE /\ RenderedLabeledStep(label) <=> SourceLabeledStep(label)
          /\ (__SwiftTLAOverflowFailure0 <=> SourceOverflow)
          /\ (__SwiftTLAAnyEvaluationFailure0 <=> SourceOverflow)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
          /\ __SwiftTLAOverflowOperands0 = <<left, 1>>
          /\ __SwiftTLAOverflowOperation0 = "addition"
    BY SMT DEF ModelStateType, RenderedLabeledStep,
        SourceLabeledStep, compare, SourceCompare, WithinSwiftInt,
        SwiftIntMax, SwiftIntMin, __SwiftTLAOverflowFailure0,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
        __SwiftTLAOverflowOperands0, __SwiftTLAOverflowOperation0,
        SourceOverflow, SourceEvaluationOK

THEOREM EmittedActionPreservesModelType ==
    ModelStateType /\ compare => ModelStateType'
    BY SMT DEF ModelStateType, compare, SwiftIntMax

THEOREM OverflowInitialStateHasNoStep ==
    Init /\ left = SwiftIntMax
    => /\ ~compare
       /\ __SwiftTLAOverflowFailure0
       /\ ~__SwiftTLAEvaluationOK
    PROOF
    <1>1. Init /\ left = SwiftIntMax => ModelStateType
        BY InitialStatesHaveModelType, SMT
    <1>2. Init /\ left = SwiftIntMax => SourceOverflow
        BY SMT DEF SourceOverflow, WithinSwiftInt, SwiftIntMax
    <1>. QED BY <1>1, <1>2, SMT DEF compare,
        __SwiftTLAOverflowFailure0, __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAEvaluationOK, SwiftIntMax, SwiftIntMin

===============================================================
