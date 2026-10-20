---------------- MODULE GeneratedStringGuardProof ----------------
EXTENDS TLAPS, GeneratedStringGuardProofModel

SourceInit ==
    /\ left = "alpha"
    /\ right = "alpha"
    /\ advanced = FALSE

SourceAdvance ==
    /\ left = right
    /\ left = "alpha"
    /\ left # "beta"
    /\ advanced' = TRUE
    /\ UNCHANGED <<left, right>>

SourceNext == SourceAdvance

THEOREM EmittedInitialState ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM EmittedCompleteLabeledStep ==
    advance <=> SourceAdvance
    BY SMT DEF advance, SourceAdvance

THEOREM EmittedCompleteNext ==
    Next <=> SourceNext
    BY EmittedCompleteLabeledStep DEF Next, SourceNext

THEOREM EmittedEnabledness ==
    ENABLED advance <=> ENABLED SourceAdvance
    BY EmittedCompleteLabeledStep, ExpandENABLED, SMT
        DEF advance, SourceAdvance

WrongGuardAdvance ==
    /\ left # right
    /\ left = "alpha"
    /\ left # "beta"
    /\ advanced' = TRUE
    /\ UNCHANGED <<left, right>>

THEOREM InvertingEqualityRejectsInitialStep ==
    ASSUME SourceInit
    PROVE ~ENABLED WrongGuardAdvance /\ ENABLED SourceAdvance
    BY ExpandENABLED, SMT
        DEF SourceInit, WrongGuardAdvance, SourceAdvance

WrongInequalityAdvance ==
    /\ left = right
    /\ left = "alpha"
    /\ left = "beta"
    /\ advanced' = TRUE
    /\ UNCHANGED <<left, right>>

THEOREM InvertingInequalityRejectsInitialStep ==
    ASSUME SourceInit
    PROVE ~ENABLED WrongInequalityAdvance /\ ENABLED SourceAdvance
    BY ExpandENABLED, SMT
        DEF SourceInit, WrongInequalityAdvance, SourceAdvance

=====================================================================
