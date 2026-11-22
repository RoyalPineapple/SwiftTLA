---------------- MODULE OrderedIntTraversalNativeRule ----------------
EXTENDS OrderedIntTraversalPassProof, FiniteSets

LOCAL ArraySets == INSTANCE FiniteSetTheorems
LOCAL ArrayPrefix == INSTANCE SequencePrefixRule

\* The checked visitor reads Array.count, calls sequenceElement at count,
\* then calls sequencePrefix at count - 1 and sequenceAppend three times.
\* The array storage uses the reviewed zero-based Swift representation.
NativeTraversalCells(stack) ==
    [offset \in 0..(Len(stack) - 1) |-> stack[offset + 1]]

NativeTraversalCount(stack) == Cardinality(DOMAIN NativeTraversalCells(stack))

NativeTraversalLast(stack) == NativeTraversalCells(stack)[NativeTraversalCount(stack) - 1]

NativeTraversalEnabled(stack) ==
    IF NativeTraversalCount(stack) = 0 THEN FALSE ELSE ~NativeTraversalLast(stack)[2]

NativeTraversalExpandedPending(stack, left, right) ==
    LET previous == ArrayPrefix!SourceSequencePrefix(stack, NativeTraversalCount(stack) - 1)
        frame == NativeTraversalLast(stack)
    IN Append(Append(Append(previous, <<frame[1], TRUE>>), <<right, FALSE>>), <<left, FALSE>>)

NativeTraversalStep(stack, left, right, nextStack, nextLeft, nextRight) ==
    IF NativeTraversalEnabled(stack)
    THEN /\ nextStack = NativeTraversalExpandedPending(stack, left, right)
         /\ nextLeft = left
         /\ nextRight = right
    ELSE FALSE

LOCAL THEOREM NativeTraversalCountUsesEveryArrayIndex ==
    ASSUME NEW stack \in Seq(SeedFrames)
    PROVE NativeTraversalCount(stack) = Len(stack)
PROOF
<1>length. Len(stack) \in Nat
    BY ONLY (stack \in Seq(SeedFrames)), LenProperties, SMT
<1>indices. DOMAIN NativeTraversalCells(stack) = 0..(Len(stack) - 1)
    BY ONLY SMT DEF NativeTraversalCells
<1>size. Cardinality(0..(Len(stack) - 1)) = Len(stack)
    BY ONLY <1>length, ArraySets!FS_Interval, SMT
<1>. QED BY ONLY <1>indices, <1>size, SMT DEF NativeTraversalCount

THEOREM NativeSeedTraversalAgreesWithSeedReplacement ==
    ASSUME NEW stack \in Seq(SeedFrames),
           NEW left \in SeedIntValues, NEW right \in SeedIntValues
    PROVE /\ (NativeTraversalEnabled(stack) <=> SeedExpansionEnabled(stack))
          /\ (SeedExpansionEnabled(stack) =>
               NativeTraversalExpandedPending(stack, left, right) = SeedExpandedPending(stack, left, right))
PROOF
<1>count. /\ NativeTraversalCount(stack) = Len(stack) /\ Len(stack) \in Nat
    BY ONLY (stack \in Seq(SeedFrames)), NativeTraversalCountUsesEveryArrayIndex, LenProperties, SMT
<1>last. Len(stack) > 0 => NativeTraversalLast(stack) = stack[Len(stack)]
    BY ONLY <1>count, SMT DEF NativeTraversalLast, NativeTraversalCells
<1>enabled. NativeTraversalEnabled(stack) <=> SeedExpansionEnabled(stack)
    BY ONLY <1>count, <1>last, SMT DEF NativeTraversalEnabled, SeedExpansionEnabled
<1>replacement.
    ASSUME SeedExpansionEnabled(stack)
    PROVE NativeTraversalExpandedPending(stack, left, right) = SeedExpandedPending(stack, left, right)
    <2>nonempty. Len(stack) > 0
        BY ONLY (SeedExpansionEnabled(stack)), <1>count, SMT DEF SeedExpansionEnabled
    <2>bounds. /\ NativeTraversalCount(stack) - 1 \in Int
               /\ NativeTraversalCount(stack) - 1 <= Len(stack)
        BY ONLY <1>count, SMT
    <2>prefix.
        ArrayPrefix!SourceSequencePrefix(stack, NativeTraversalCount(stack) - 1) =
            SubSeq(stack, 1, Len(stack) - 1)
        BY ONLY (stack \in Seq(SeedFrames)), <1>count, <2>bounds,
            ArrayPrefix!SequencePrefixValuePreserved, SMT
    <2>calls. NativeTraversalExpandedPending(stack, left, right) =
                SeedPhysicalPendingReplacement(stack, left, right)
        BY ONLY <1>last, <2>nonempty, <2>prefix, SMT
            DEF NativeTraversalExpandedPending, SeedPhysicalPendingReplacement
    <2>. QED BY ONLY (stack \in Seq(SeedFrames)), (left \in SeedIntValues), (right \in SeedIntValues),
        <2>nonempty, <2>calls, SeedPhysicalPendingReplacementMatchesTheSource, Isa
<1>. QED BY ONLY <1>enabled, <1>replacement, Isa

THEOREM NativeAndRenderedSeedVisitTheSameExpansion ==
    ASSUME SeedExpansionInput
    PROVE expand <=> NativeTraversalStep(pending, leftChild, rightChild, pending', leftChild', rightChild')
PROOF
<1>operands.
    /\ (NativeTraversalEnabled(pending) <=> SeedAuthoredExpansionEnabled(pending))
    /\ (SeedAuthoredExpansionEnabled(pending) =>
        NativeTraversalExpandedPending(pending, leftChild, rightChild) =
            SeedAuthoredPendingReplacement(pending, leftChild, rightChild))
    BY ONLY SeedExpansionInput, NativeSeedTraversalAgreesWithSeedReplacement,
        SeedAuthoredExpansionUsesTheBoundFieldsAndPushes, SMT DEF SeedExpansionInput
<1>native. NativeTraversalStep(pending, leftChild, rightChild, pending', leftChild', rightChild')
              <=> SeedExpansion
    BY ONLY <1>operands, SMT DEF SeedExpansion, NativeTraversalStep
<1>. QED BY ONLY SeedExpansionInput, <1>native, ActualSeedExpansionPreservesThePendingReplacement, Isa

\* The checked successor collector calls the visitor with the internal append
\* callback. Its catch appends exactly a reached model failure. The remaining
\* reached operations are nonthrowing under the reviewed Swift interpretation.
NativeTraversalReachedFailures(stack) ==
    LET count == NativeTraversalCount(stack)
        prefixCount == count - 1
    IN IF count <= 0 THEN <<>>
       ELSE IF count \notin 1..Len(stack)
            THEN <<<<"indexOutOfBounds", count, Len(stack)>>>>
       ELSE IF NativeTraversalLast(stack)[2] THEN <<>>
       ELSE IF prefixCount \notin SeedIntValues
            THEN <<<<"integerOverflow", "subtraction", <<count, 1>>>>>>
       ELSE IF prefixCount > Len(stack)
            THEN <<<<"indexOutOfBounds", prefixCount, Len(stack)>>>>
       ELSE <<>>

THEOREM NativeSeedTraversalDoesNotReachAModelFailure ==
    ASSUME SeedExpansionInput
    PROVE NativeTraversalReachedFailures(pending) = <<>>
PROOF
<1>count. /\ NativeTraversalCount(pending) = Len(pending)
          /\ Len(pending) \in Nat
    BY ONLY SeedExpansionInput, NativeTraversalCountUsesEveryArrayIndex, LenProperties, SMT DEF SeedExpansionInput
<1>enabled. NativeTraversalEnabled(pending) <=> SeedExpansionEnabled(pending)
    BY ONLY SeedExpansionInput, NativeSeedTraversalAgreesWithSeedReplacement, SMT DEF SeedExpansionInput
<1>safe. SeedTraversalHelperCallsAreSafe
    BY ONLY SeedExpansionInput, ActualSeedExpansionDoesNotFailOnTypedInput
<1>access. NativeTraversalCount(pending) > 0 =>
                  NativeTraversalCount(pending) \in 1..Len(pending)
    BY ONLY <1>count, <1>safe, SMT DEF SeedTraversalHelperCallsAreSafe
<1>prefix. NativeTraversalEnabled(pending) =>
                /\ NativeTraversalCount(pending) - 1 \in SeedIntValues
                /\ NativeTraversalCount(pending) - 1 <= Len(pending)
    BY ONLY <1>count, <1>enabled, <1>safe, SMT DEF SeedTraversalHelperCallsAreSafe
<1>. QED BY ONLY <1>count, <1>access, <1>prefix, SMT DEF NativeTraversalReachedFailures, NativeTraversalEnabled

NativeSeedInit ==
    /\ pending = NativeStackInitialization.pending
    /\ leftChild = NativeStackInitialization.leftChild
    /\ rightChild = NativeStackInitialization.rightChild

THEOREM NativeSeedInitializationIsTheConfiguredInitialization ==
    /\ NativeStackInitialization = AuthoredStackInitialization
    /\ (NativeSeedInit <=> SeedAuthoredInit)
    /\ (NativeSeedInit <=> Init)
    /\ (NativeSeedInit => SeedExpansionInput)
PROOF
<1>decoded. NativeStackInitialization = SeedBootstrapInitialization
    BY ONLY SMT DEF NativeStackInitialization, SeedBootstrapInitialization
<1>record. NativeStackInitialization = AuthoredStackInitialization
    BY ONLY <1>decoded, ActualSeedInitMatchesTheAuthoredInitializers, SMT
<1>state. NativeSeedInit <=> SeedAuthoredInit
    BY ONLY <1>record, SMT DEF NativeSeedInit, SeedAuthoredInit
<1>. QED BY ONLY <1>record, <1>state, ActualSeedInitMatchesTheAuthoredInitializers, SMT
====
