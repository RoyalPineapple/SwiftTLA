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

ConditionalWeakFair(action) ==
    (<>[]ENABLED <<action>>_vars) => []<><<action>>_vars
ConditionalStrongFair(action) ==
    ([]<>ENABLED <<action>>_vars) => []<><<action>>_vars

THEOREM EmittedConditionalWeakFairnessExpansion ==
    WF_vars(choose) <=> ConditionalWeakFair(choose)
    BY PTL DEF ConditionalWeakFair

THEOREM SourceConditionalWeakFairnessExpansion ==
    WF_vars(SourceConditionalChoose)
        <=> ConditionalWeakFair(SourceConditionalChoose)
    BY PTL DEF ConditionalWeakFair

THEOREM EmittedConditionalStrongFairnessExpansion ==
    SF_vars(choose) <=> ConditionalStrongFair(choose)
    BY PTL DEF ConditionalStrongFair

THEOREM SourceConditionalStrongFairnessExpansion ==
    SF_vars(SourceConditionalChoose)
        <=> ConditionalStrongFair(SourceConditionalChoose)
    BY PTL DEF ConditionalStrongFair

THEOREM EmittedConditionalActionAlwaysSame ==
    ASSUME []ConditionalTypeOK
    PROVE [](choose <=> SourceConditionalChoose)
    BY EmittedConditionalBothBranches, PTL DEF ConditionalTypeOK

THEOREM EmittedConditionalFairEnabledness ==
    ASSUME ConditionalTypeOK
    PROVE ENABLED <<choose>>_vars
        <=> ENABLED <<SourceConditionalChoose>>_vars
    BY EmittedConditionalBothBranches, ExpandENABLED, SMT
        DEF ConditionalTypeOK, choose, SourceConditionalChoose, vars

THEOREM EmittedConditionalFairEnabledAlwaysSame ==
    ASSUME []ConditionalTypeOK
    PROVE [](ENABLED <<choose>>_vars
        <=> ENABLED <<SourceConditionalChoose>>_vars)
    BY EmittedConditionalFairEnabledness, PTL DEF ConditionalTypeOK

THEOREM EmittedConditionalNextNonstuttering ==
    ASSUME ConditionalTypeOK
    PROVE <<Next>>_vars <=> <<choose>>_vars
    BY SMT DEF ConditionalTypeOK, Next, choose, Terminating, vars

THEOREM EmittedConditionalNextFairEnabledness ==
    ASSUME ConditionalTypeOK
    PROVE ENABLED <<Next>>_vars <=> ENABLED <<choose>>_vars
    BY EmittedConditionalNextNonstuttering, ExpandENABLED, SMT
        DEF ConditionalTypeOK, Next, choose, Terminating, vars

THEOREM EmittedConditionalNextWeakFairness ==
    ASSUME []ConditionalTypeOK
    PROVE WF_vars(Next) <=> WF_vars(choose)
    BY EmittedConditionalNextNonstuttering,
        EmittedConditionalNextFairEnabledness, PTL
        DEF ConditionalTypeOK

THEOREM EmittedConditionalWeakFairnessFormula ==
    ASSUME [](choose <=> SourceConditionalChoose),
           [](ENABLED <<choose>>_vars
             <=> ENABLED <<SourceConditionalChoose>>_vars)
    PROVE ConditionalWeakFair(choose)
        <=> ConditionalWeakFair(SourceConditionalChoose)
    BY PTL DEF ConditionalWeakFair

THEOREM EmittedConditionalWeakFairness ==
    ASSUME []ConditionalTypeOK
    PROVE WF_vars(choose) <=> WF_vars(SourceConditionalChoose)
    BY EmittedConditionalActionAlwaysSame,
        EmittedConditionalFairEnabledAlwaysSame,
        EmittedConditionalWeakFairnessFormula,
        EmittedConditionalWeakFairnessExpansion,
        SourceConditionalWeakFairnessExpansion

THEOREM EmittedConditionalNextWeakFairnessAgreesWithSource ==
    ASSUME []ConditionalTypeOK
    PROVE WF_vars(Next) <=> WF_vars(SourceConditionalChoose)
    BY EmittedConditionalNextWeakFairness, EmittedConditionalWeakFairness

THEOREM EmittedConditionalStrongFairnessFormula ==
    ASSUME [](choose <=> SourceConditionalChoose),
           [](ENABLED <<choose>>_vars
             <=> ENABLED <<SourceConditionalChoose>>_vars)
    PROVE ConditionalStrongFair(choose)
        <=> ConditionalStrongFair(SourceConditionalChoose)
    BY PTL DEF ConditionalStrongFair

THEOREM EmittedConditionalStrongFairness ==
    ASSUME []ConditionalTypeOK
    PROVE SF_vars(choose) <=> SF_vars(SourceConditionalChoose)
    BY EmittedConditionalActionAlwaysSame,
        EmittedConditionalFairEnabledAlwaysSame,
        EmittedConditionalStrongFairnessFormula,
        EmittedConditionalStrongFairnessExpansion,
        SourceConditionalStrongFairnessExpansion

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

CoreConditionalSpec ==
    /\ Init
    /\ [][Next]_<<pc, chooseFirst, value>>

THEOREM EmittedConditionalCoreTypeInvariant ==
    CoreConditionalSpec => []ConditionalTypeOK
    PROOF
    <1>1. ConditionalTypeOK /\ [Next]_<<pc, chooseFirst, value>>
            => ConditionalTypeOK'
        BY ConditionalStepPreservesType, SMT DEF ConditionalTypeOK
    <1>2. ConditionalTypeOK /\ [][Next]_<<pc, chooseFirst, value>>
            => []ConditionalTypeOK
        BY <1>1, PTL
    <1>. QED
        BY ConditionalInitialType, <1>2, PTL DEF CoreConditionalSpec

THEOREM EmittedConditionalTypeInvariant ==
    Spec => []ConditionalTypeOK
    BY EmittedConditionalCoreTypeInvariant, PTL
        DEF Spec, CoreConditionalSpec

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
    CoreConditionalSpec <=> SourceConditionalSpec
    PROOF
    <1>1. []ConditionalTypeOK =>
        ([][Next]_<<pc, chooseFirst, value>>
         <=> [][SourceConditionalNext]_<<pc, chooseFirst, value>>)
        BY EmittedConditionalNext, PTL DEF ConditionalTypeOK
    <1>2. CoreConditionalSpec => []ConditionalTypeOK
        BY EmittedConditionalCoreTypeInvariant
    <1>3. SourceConditionalSpec => []ConditionalTypeOK
        BY SourceConditionalTypeInvariant
    <1>. QED
        BY <1>1, <1>2, <1>3, EmittedConditionalInitial, PTL
            DEF CoreConditionalSpec, SourceConditionalSpec

THEOREM EmittedConditionalSequentialFairTemporalSpec ==
    Spec
        <=> (SourceConditionalSpec /\ WF_vars(SourceConditionalChoose))
    BY EmittedConditionalTemporalSpec, EmittedConditionalCoreTypeInvariant,
        EmittedConditionalNextWeakFairnessAgreesWithSource, PTL
        DEF Spec, CoreConditionalSpec, vars

THEOREM EmittedConditionalStrongFairTemporalSpec ==
    (Spec /\ SF_vars(choose))
        <=> (SourceConditionalSpec /\ WF_vars(SourceConditionalChoose)
             /\ SF_vars(SourceConditionalChoose))
    BY EmittedConditionalSequentialFairTemporalSpec,
        EmittedConditionalTypeInvariant,
        EmittedConditionalStrongFairness, PTL

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

RefinementInvariant ==
    /\ ConditionalTypeOK
    /\ (pc = "choose" => value = 0)

AbstractValueStep == value = 0 /\ value' \in {1, 2}
AbstractValueSpec == value = 0 /\ [][AbstractValueStep]_value

THEOREM EmittedRefinementInitial ==
    Init => RefinementInvariant
    BY EmittedConditionalInitial, SMT
        DEF RefinementInvariant, ConditionalTypeOK, SourceConditionalInit

THEOREM EmittedRefinementStepInvariant ==
    ASSUME RefinementInvariant, [Next]_vars
    PROVE RefinementInvariant'
    BY EmittedConditionalNext, SMT
        DEF RefinementInvariant, ConditionalTypeOK, SourceConditionalNext,
            SourceConditionalChoose, SourceConditionalTerminating, vars

THEOREM EmittedRefinementInvariant ==
    CoreConditionalSpec => []RefinementInvariant
    PROOF
    <1>1. RefinementInvariant /\ [Next]_vars => RefinementInvariant'
        BY EmittedRefinementStepInvariant
    <1>2. RefinementInvariant /\ [][Next]_vars => []RefinementInvariant
        BY <1>1, PTL
    <1>3. CoreConditionalSpec => Init
        BY DEF CoreConditionalSpec
    <1>4. CoreConditionalSpec => [][Next]_vars
        BY PTL DEF CoreConditionalSpec, vars
    <1>5. CoreConditionalSpec => RefinementInvariant
        BY <1>3, EmittedRefinementInitial
    <1>. QED
        BY <1>2, <1>4, <1>5, PTL

THEOREM EmittedRefinementStep ==
    ASSUME RefinementInvariant, [Next]_vars
    PROVE [AbstractValueStep]_value
    BY EmittedConditionalNext, SMT
        DEF RefinementInvariant, ConditionalTypeOK, SourceConditionalNext,
            SourceConditionalChoose, SourceConditionalTerminating,
            AbstractValueStep, vars

THEOREM EmittedConditionalValueRefinement ==
    Spec => AbstractValueSpec
    PROOF
    <1>1. []RefinementInvariant /\ [][Next]_vars
            => [][AbstractValueStep]_value
        BY EmittedRefinementStep, PTL
    <1>2. Spec => CoreConditionalSpec
        BY PTL DEF Spec, CoreConditionalSpec
    <1>3. Spec => []RefinementInvariant
        BY <1>2, EmittedRefinementInvariant
    <1>4. Spec => value = 0
        BY PTL DEF Spec, Init
    <1>5. Spec => [][Next]_vars
        BY PTL DEF Spec, vars
    <1>6. Spec => value = 0 /\ []RefinementInvariant
                    /\ [][Next]_vars
        BY <1>3, <1>4, <1>5
    <1>. QED
        BY <1>1, <1>6, PTL DEF AbstractValueSpec
=======================================================================
