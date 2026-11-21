---- MODULE OrderedOverflowDirectInitialDisabled ----
EXTENDS OrderedOverflow, TLAPS

THEOREM ActualOrderedOverflowInitialHasNoSuccessor ==
    ASSUME Init
    PROVE ~ENABLED Next
    BY ONLY Init, ExpandENABLED, SMT DEF Init, Next, advance, Terminating

====
