---- MODULE OrderedOverflowInitialDisabled ----
EXTENDS TLAPS

VARIABLES arithmeticPC, arithmeticCount

OverflowActions == INSTANCE OrderedOverflow
    WITH pc <- arithmeticPC, count <- arithmeticCount

THEOREM InitialOrderedOverflowHasNoSuccessor ==
    ASSUME OverflowActions!Init
    PROVE ~ENABLED OverflowActions!Next
    BY ONLY OverflowActions!Init, ExpandENABLED, SMT
        DEF OverflowActions!Init, OverflowActions!Next, OverflowActions!advance, OverflowActions!Terminating

====
