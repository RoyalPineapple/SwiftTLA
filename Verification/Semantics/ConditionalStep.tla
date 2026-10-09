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
=======================================================================
