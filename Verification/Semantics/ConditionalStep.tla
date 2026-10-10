----------------------- MODULE ConditionalStep -----------------------
EXTENDS TLAPS, ConditionalStepProofModel

SourceConditionalInit ==
    /\ pc = "choose"
    /\ chooseFirst \in BOOLEAN
    /\ value = 0

SourceConditionalChoose ==
    /\ pc = "choose"
    /\ pc' = "Done"
    /\ chooseFirst' = ~chooseFirst
    /\ value' = IF ~chooseFirst THEN 1 ELSE 2

SourceConditionalTerminating ==
    /\ pc = "Done"
    /\ UNCHANGED <<pc, chooseFirst, value>>

SourceConditionalNext == SourceConditionalChoose \/ SourceConditionalTerminating

THEOREM EmittedConditionalInitial ==
    Init <=> SourceConditionalInit
    BY SMT DEF Init, SourceConditionalInit

THEOREM EmittedConditionalBothBranches ==
    ASSUME chooseFirst \in BOOLEAN
    PROVE choose <=> SourceConditionalChoose
    BY SMT DEF choose, SourceConditionalChoose

THEOREM EmittedConditionalTerminating ==
    Terminating <=> SourceConditionalTerminating
    BY SMT DEF Terminating, SourceConditionalTerminating

THEOREM EmittedConditionalNext ==
    ASSUME chooseFirst \in BOOLEAN
    PROVE Next <=> SourceConditionalNext
    BY EmittedConditionalBothBranches, EmittedConditionalTerminating
        DEF Next, SourceConditionalNext

ConditionalTypeOK ==
    /\ pc \in {"choose", "Done"}
    /\ chooseFirst \in BOOLEAN
    /\ value \in {0, 1, 2}

THEOREM EmittedConditionalEnabledness ==
    ASSUME ConditionalTypeOK
    PROVE ENABLED choose <=> ENABLED SourceConditionalChoose
    BY EmittedConditionalBothBranches, ExpandENABLED, SMT
        DEF ConditionalTypeOK, choose, SourceConditionalChoose

THEOREM EmittedConditionalDeadlockAgreement ==
    ASSUME ConditionalTypeOK
    PROVE ~ENABLED Next <=> ~ENABLED SourceConditionalNext
    BY EmittedConditionalNext, ExpandENABLED, SMT
        DEF ConditionalTypeOK, Next, choose, Terminating,
            SourceConditionalNext, SourceConditionalChoose,
            SourceConditionalTerminating

THEOREM ConditionalInitialType ==
    Init => ConditionalTypeOK
    BY EmittedConditionalInitial,
        SMT DEF SourceConditionalInit, ConditionalTypeOK

THEOREM ConditionalStepPreservesType ==
    ASSUME ConditionalTypeOK, Next
    PROVE ConditionalTypeOK'
    BY EmittedConditionalNext, SMT DEF ConditionalTypeOK,
        SourceConditionalNext, SourceConditionalChoose,
        SourceConditionalTerminating

THEOREM EmittedConditionalTypeInvariant ==
    Spec => []ConditionalTypeOK
    PROOF
    <1>1. ConditionalTypeOK /\ [Next]_<<pc, chooseFirst, value>>
            => ConditionalTypeOK'
        BY ConditionalStepPreservesType, SMT DEF ConditionalTypeOK
    <1>2. ConditionalTypeOK /\ [][Next]_<<pc, chooseFirst, value>>
            => []ConditionalTypeOK
        BY <1>1, PTL
    <1>. QED
        BY ConditionalInitialType, <1>2, PTL DEF Spec

SourceConditionalSpec ==
    /\ SourceConditionalInit
    /\ [][SourceConditionalNext]_<<pc, chooseFirst, value>>

THEOREM SourceConditionalTypeInvariant ==
    SourceConditionalSpec => []ConditionalTypeOK
    PROOF
    <1>1. ConditionalTypeOK /\ [SourceConditionalNext]_<<pc, chooseFirst, value>>
            => ConditionalTypeOK'
        BY SMT DEF ConditionalTypeOK, SourceConditionalNext,
            SourceConditionalChoose, SourceConditionalTerminating
    <1>2. ConditionalTypeOK /\ [][SourceConditionalNext]_<<pc, chooseFirst, value>>
            => []ConditionalTypeOK
        BY <1>1, PTL
    <1>. QED
        BY <1>2, EmittedConditionalInitial, ConditionalInitialType
            DEF SourceConditionalSpec

THEOREM EmittedConditionalTemporalSpec ==
    Spec <=> SourceConditionalSpec
    PROOF
    <1>1. []ConditionalTypeOK =>
        ([][Next]_<<pc, chooseFirst, value>>
         <=> [][SourceConditionalNext]_<<pc, chooseFirst, value>>)
        BY EmittedConditionalNext, PTL DEF ConditionalTypeOK
    <1>2. Spec => []ConditionalTypeOK
        BY EmittedConditionalTypeInvariant
    <1>3. SourceConditionalSpec => []ConditionalTypeOK
        BY SourceConditionalTypeInvariant
    <1>. QED
        BY <1>1, <1>2, <1>3, EmittedConditionalInitial, PTL
            DEF Spec, SourceConditionalSpec

ConditionalStates ==
    [pc: {"choose", "Done"}, chooseFirst: BOOLEAN, value: {0, 1, 2}]
ConditionalBefore ==
    [pc |-> pc, chooseFirst |-> chooseFirst, value |-> value]
ConditionalAfter ==
    [pc |-> pc', chooseFirst |-> chooseFirst', value |-> value']
ConditionalSuccessor(state) ==
    IF state.pc = "choose"
    THEN [pc |-> "Done", chooseFirst |-> ~state.chooseFirst,
          value |-> IF ~state.chooseFirst THEN 1 ELSE 2]
    ELSE state
ConditionalStepRelation(before, after) ==
    /\ before \in ConditionalStates
    /\ after = ConditionalSuccessor(before)

THEOREM ConditionalSuccessorIsTotal ==
    \A state \in ConditionalStates :
        /\ ConditionalSuccessor(state) \in ConditionalStates
        /\ ConditionalStepRelation(state, ConditionalSuccessor(state))
    BY SMT DEF ConditionalStates, ConditionalSuccessor,
        ConditionalStepRelation

THEOREM ConditionalHasNoRelationalDeadlock ==
    \A state \in ConditionalStates :
        \E successor \in ConditionalStates :
            ConditionalStepRelation(state, successor)
    BY ConditionalSuccessorIsTotal

THEOREM EmittedConditionalExactRelation ==
    ASSUME ConditionalTypeOK
    PROVE Next
          <=> ConditionalStepRelation(ConditionalBefore, ConditionalAfter)
    BY EmittedConditionalNext, SMT DEF ConditionalStepRelation,
        ConditionalSuccessor, ConditionalStates, ConditionalTypeOK,
        ConditionalBefore, ConditionalAfter, SourceConditionalNext,
        SourceConditionalChoose, SourceConditionalTerminating
=======================================================================
