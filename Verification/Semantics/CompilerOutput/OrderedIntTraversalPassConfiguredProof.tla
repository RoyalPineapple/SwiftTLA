---------------- MODULE OrderedIntTraversalPassConfiguredProof ----------------
EXTENDS OrderedIntTraversalNativeRule, CallerInputPageBlock1

\* CallerInputPage1 CallerInputPage2 CallerInputPage3
SeedExpansionCFG == <<83, 80, 69, 67, 73, 70, 73, 67, 65, 84, 73, 79, 78, 32, 83, 112, 101, 99, 10, 67, 72, 69, 67, 75, 95, 68, 69, 65, 68, 76, 79, 67, 75, 32, 84, 82, 85, 69, 10>>
ActualSeedExpansionCFG == [i \in 1..CallerInputSize |-> CallerInputByte[i - 1]]

THEOREM ActualSeedExpansionCFGSelectsSpecAndDeadlockOnly ==
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
          /\ (Next <=> NativeTraversalStep(pending, leftChild, rightChild, pending', leftChild', rightChild'))
          /\ SeedAuthoredExpansionFailures = <<>>
          /\ SeedRenderedExpansionFailures = <<>>
          /\ NativeTraversalReachedFailures(pending) = <<>>
          /\ SeedTraversalHelperCallsAreSafe
          /\ (Init <=> SeedAuthoredInit)
          /\ (NativeSeedInit <=> Init)
          /\ (Spec <=> SeedAuthoredInit /\ [][Next]_vars)
          /\ (Spec <=> NativeSeedInit /\ [][Next]_vars)
PROOF
<1>transition. Next <=> SeedExpansion
    BY ONLY SeedExpansionInput, ActualSeedExpansionPreservesThePendingReplacement, SMT DEF Next
<1>nativeTransition. Next <=> NativeTraversalStep(pending, leftChild, rightChild, pending', leftChild', rightChild')
    BY ONLY SeedExpansionInput, NativeAndRenderedSeedVisitTheSameExpansion, SMT DEF Next
<1>rendered. Spec <=> Init /\ [][Next]_vars
    BY ONLY DEF Spec, vars
<1>behavior. Spec <=> SeedAuthoredInit /\ [][Next]_vars
    BY ONLY <1>rendered, ActualSeedInitMatchesTheAuthoredInitializers
<1>nativeBehavior. Spec <=> NativeSeedInit /\ [][Next]_vars
    BY ONLY <1>rendered, NativeSeedInitializationIsTheConfiguredInitialization
<1>. QED BY ONLY SeedExpansionInput, <1>transition, <1>nativeTransition, <1>behavior, <1>nativeBehavior,
    ActualSeedInitMatchesTheAuthoredInitializers, NativeSeedInitializationIsTheConfiguredInitialization,
    ActualSeedExpansionCFGSelectsSpecAndDeadlockOnly, ActualSeedExpansionDoesNotFailOnTypedInput,
    NativeSeedTraversalDoesNotReachAModelFailure

====
