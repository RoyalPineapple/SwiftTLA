---------------- MODULE OrderedIntTraversalPassConfiguredProof ----------------
EXTENDS OrderedIntTraversalPassProof, CallerInputPageBlock1

\* CallerInputPage1 CallerInputPage2 CallerInputPage3 CallerInputPage4 CallerInputPage5
SeedExpansionCFG == <<83, 80, 69, 67, 73, 70, 73, 67, 65, 84, 73, 79, 78, 32, 83, 112, 101, 99, 10, 67, 72, 69, 67, 75, 95, 68, 69, 65, 68, 76, 79, 67, 75, 32, 84, 82, 85, 69, 10, 73, 78, 86, 65, 82, 73, 65, 78, 84, 32, 95, 95, 83, 119, 105, 102, 116, 84, 76, 65, 69, 118, 97, 108, 117, 97, 116, 105, 111, 110, 79, 75, 10>>
ActualSeedExpansionCFG == [i \in 1..CallerInputSize |-> CallerInputByte[i - 1]]

THEOREM ActualSeedExpansionCFGSelectsSpecAndEvaluationChecking ==
    ActualSeedExpansionCFG = SeedExpansionCFG
PROOF
<1>domain. DOMAIN ActualSeedExpansionCFG = DOMAIN SeedExpansionCFG
    BY ONLY SMT DEF ActualSeedExpansionCFG, SeedExpansionCFG, CallerInputSize
<1>bytes. \A i \in DOMAIN SeedExpansionCFG : ActualSeedExpansionCFG[i] = SeedExpansionCFG[i]
    BY ONLY CallerInputPageBlock1AtFileOffsets, SMT
        DEF ActualSeedExpansionCFG, SeedExpansionCFG, CallerInputSize
<1>. QED BY ONLY <1>domain, <1>bytes, SMT DEF ActualSeedExpansionCFG, SeedExpansionCFG

THEOREM ConfiguredSeedUsesTheTypedExpansion ==
    ASSUME SeedExpansionInput
    PROVE /\ ActualSeedExpansionCFG = SeedExpansionCFG
          /\ (Next <=> SeedExpansion)
          /\ __SwiftTLAEvaluationOK
          /\ (Spec <=> Init /\ [][Next]_vars)
PROOF
<1>transition. Next <=> SeedExpansion
    BY ONLY SeedExpansionInput, ActualSeedExpansionPreservesThePendingReplacement, SMT DEF Next
<1>behavior. Spec <=> Init /\ [][Next]_vars
    BY ONLY DEF Spec, vars
<1>. QED BY ONLY SeedExpansionInput, <1>transition, <1>behavior,
    ActualSeedExpansionCFGSelectsSpecAndEvaluationChecking, ActualSeedExpansionDoesNotFailOnTypedInput

====
