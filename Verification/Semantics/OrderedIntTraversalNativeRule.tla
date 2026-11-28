---------------- MODULE OrderedIntTraversalNativeRule ----------------
EXTENDS OrderedIntTraversalPassProof, FiniteSets

LOCAL ArraySets == INSTANCE FiniteSetTheorems
LOCAL ArrayPrefix == INSTANCE SequencePrefixRule
LOCAL ArrayEdits == INSTANCE SequenceExpressionConstructorRules
    WITH Elements <- SeedFrames, FailureValues <- {}, NoFailure <- <<>>

\* Swift Array.append retains the old cells and stores the operand at the old count.
\* SourceAppendValue expresses those cells at the corresponding one-based indices.
LOCAL NativeAppend(sequence, element) == ArrayEdits!SourceAppendValue(sequence, element)

\* The checked visitor reads Array.count, calls sequenceElement at count,
\* then calls sequencePrefix at count - 1 and sequenceAppend three times.
\* The array storage uses the reviewed zero-based Swift representation.
NativeTraversalCells(stack) ==
    [offset \in 0..(Len(stack) - 1) |-> stack[offset + 1]]

NativeTraversalCount(stack) == Cardinality(DOMAIN NativeTraversalCells(stack))

LOCAL NativeStackExpansionUsesAuthoredOperands ==
    NativeStackExpansion =
        [countFloor |-> AuthoredStackExpansion.countFloor, lastIndex |-> AuthoredStackExpansion.lastIndex,
         prefixDrop |-> AuthoredStackExpansion.prefixDrop,
         localExpandedPosition |-> AuthoredStackExpansion.localExpandedPosition,
         pushes |-> AuthoredStackExpansion.pushes]

LOCAL THEOREM ActualNativeExpansionBindsTheAuthoredOperands ==
    NativeStackExpansionUsesAuthoredOperands
    BY ONLY SMT DEF NativeStackExpansionUsesAuthoredOperands, NativeStackExpansion, AuthoredStackExpansion

LOCAL NativeTraversalIndex(stack) ==
    CASE NativeStackExpansion.lastIndex = "count" -> NativeTraversalCount(stack)

LOCAL NativeTraversalElementInBounds(stack, index) ==
    index >= NativeStackElementMinimum /\ index <= Len(stack)

LOCAL NativeTraversalElement(stack, index) ==
    NativeTraversalCells(stack)[index - NativeStackElementOffset]

NativeTraversalLast(stack) == NativeTraversalElement(stack, NativeTraversalIndex(stack))

NativeTraversalEnabled(stack) ==
    IF NativeTraversalCount(stack) <= NativeStackExpansion.countFloor THEN FALSE
    ELSE ~NativeTraversalLast(stack)[NativeStackExpansion.localExpandedPosition]

LOCAL NativeTraversalPushes(stack, left, right) ==
    [step \in DOMAIN NativeStackExpansion.pushes |->
        LET row == NativeStackExpansion.pushes[step]
            origin == CASE row.source = "local" -> NativeTraversalLast(stack)[row.position]
                        [] row.source = "leftChild" -> left
                        [] row.source = "rightChild" -> right
        IN <<origin, row.expanded>>]

LOCAL NativeTraversalPrefixLength(stack) ==
    LET requested == NativeTraversalCount(stack) - NativeStackExpansion.prefixDrop
    IN IF requested < NativeStackPrefixFloor THEN NativeStackPrefixFloor ELSE requested

NativeTraversalExpandedPending(stack, left, right) ==
    LET previous == ArrayPrefix!SourceSequencePrefix(stack, NativeTraversalPrefixLength(stack))
        pushes == NativeTraversalPushes(stack, left, right)
    IN NativeAppend(NativeAppend(NativeAppend(previous, pushes[1]), pushes[2]), pushes[3])

NativeTraversalReturnedField(stack, left, right, field) ==
    LET writes == <<NativeTraversalExpandedPending(stack, left, right), left, right>>
    IN writes[NativeStackReturnedSlots[field]]

NativeTraversalStep(stack, left, right, nextStack, nextLeft, nextRight) ==
    IF NativeTraversalEnabled(stack)
    THEN /\ nextStack = NativeTraversalReturnedField(stack, left, right, 1)
         /\ nextLeft = NativeTraversalReturnedField(stack, left, right, 2)
         /\ nextRight = NativeTraversalReturnedField(stack, left, right, 3)
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
    <2>bounds. 0 \in Int /\ Len(stack) - 1 \in Int
        BY ONLY <1>length, SMT
    <2>interval.
        /\ ArraySets!IsFiniteSet(0..(Len(stack) - 1))
        /\ ArraySets!Cardinality(0..(Len(stack) - 1)) =
               (IF 0 > Len(stack) - 1 THEN 0 ELSE (Len(stack) - 1) - 0 + 1)
        BY ONLY <2>bounds, ArraySets!FS_Interval
    <2>arithmetic. (IF 0 > Len(stack) - 1 THEN 0 ELSE (Len(stack) - 1) - 0 + 1) = Len(stack)
        BY ONLY <1>length, SMT
    <2>cardinality. Cardinality(0..(Len(stack) - 1)) = ArraySets!Cardinality(0..(Len(stack) - 1))
        BY ONLY DEF Cardinality, ArraySets!Cardinality
    <2>. QED BY ONLY <2>interval, <2>arithmetic, <2>cardinality, SMT
<1>. QED BY ONLY <1>indices, <1>size, SMT DEF NativeTraversalCount

LOCAL THEOREM NativeStackOperationsUseTheCheckedGuardAndIndex ==
    /\ NativeStackExpansion.countFloor = 0
    /\ NativeStackExpansion.lastIndex = "count"
    /\ NativeStackExpansion.prefixDrop = 1
    /\ NativeStackExpansion.localExpandedPosition = 2
    BY ONLY ActualNativeExpansionBindsTheAuthoredOperands, SeedAuthoredExpansionUsesTheBoundFieldsAndPushes,
        SMT DEF NativeStackExpansionUsesAuthoredOperands

LOCAL THEOREM NativeTraversalElementReadsAValidIndex ==
    ASSUME NEW stack \in Seq(SeedFrames), NEW index \in 1..Len(stack)
    PROVE /\ NativeTraversalElementInBounds(stack, index)
          /\ NativeTraversalElement(stack, index) = stack[index]
PROOF
<1>guard. NativeTraversalElementInBounds(stack, index)
    BY ONLY (index \in 1..Len(stack)), SMT DEF NativeTraversalElementInBounds, NativeStackElementMinimum
<1>offset. index - NativeStackElementOffset \in 0..(Len(stack) - 1)
    BY ONLY (index \in 1..Len(stack)), SMT DEF NativeStackElementOffset
<1>value. NativeTraversalElement(stack, index) = stack[index]
    BY ONLY <1>offset, SMT DEF NativeTraversalElement, NativeTraversalCells, NativeStackElementOffset
<1>. QED BY ONLY <1>guard, <1>value, PTL

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
    BY ONLY (stack \in Seq(SeedFrames)), <1>count, NativeStackOperationsUseTheCheckedGuardAndIndex,
        NativeTraversalElementReadsAValidIndex, SMT DEF NativeTraversalLast, NativeTraversalIndex
<1>enabled. NativeTraversalEnabled(stack) <=> SeedExpansionEnabled(stack)
    BY ONLY <1>count, <1>last, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT
        DEF NativeTraversalEnabled, SeedExpansionEnabled
<1>replacement.
    ASSUME SeedExpansionEnabled(stack)
    PROVE NativeTraversalExpandedPending(stack, left, right) = SeedExpandedPending(stack, left, right)
    <2>nonempty. Len(stack) > 0
        BY ONLY (SeedExpansionEnabled(stack)), <1>count, SMT DEF SeedExpansionEnabled
    <2>bounds. /\ NativeTraversalCount(stack) - 1 \in Int
               /\ NativeTraversalCount(stack) - 1 <= Len(stack)
        BY ONLY <1>count, SMT
    <2>runtimeLength. NativeTraversalPrefixLength(stack) = Len(stack) - 1
        BY ONLY <1>count, <2>nonempty, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT
            DEF NativeTraversalPrefixLength, NativeStackPrefixFloor
    <2>prefix.
        ArrayPrefix!SourceSequencePrefix(stack, NativeTraversalPrefixLength(stack)) = SubSeq(stack, 1, Len(stack) - 1)
        BY ONLY (stack \in Seq(SeedFrames)), <1>count, <2>bounds, <2>runtimeLength,
            ArrayPrefix!SequencePrefixValuePreserved, SMT
    <2>pushes.
        LET pushes == NativeTraversalPushes(stack, left, right)
        IN /\ pushes[1] = <<stack[Len(stack)][1], TRUE>>
           /\ pushes[2] = <<right, FALSE>>
           /\ pushes[3] = <<left, FALSE>>
        BY ONLY <1>last, <2>nonempty, ActualNativeExpansionBindsTheAuthoredOperands, SMT
            DEF NativeStackExpansionUsesAuthoredOperands, NativeTraversalPushes, AuthoredStackExpansion
    <2>. DEFINE prefix == SubSeq(stack, 1, Len(stack) - 1)
                pushes == NativeTraversalPushes(stack, left, right)
                first == Append(prefix, pushes[1])
                second == Append(first, pushes[2])
    <2>prefixType. prefix \in Seq(SeedFrames)
        BY ONLY (stack \in Seq(SeedFrames)), <2>nonempty, LenProperties, SubSeqProperties, SMT
            DEF prefix
    <2>frames. /\ pushes[1] \in SeedFrames
               /\ pushes[2] \in SeedFrames
               /\ pushes[3] \in SeedFrames
        BY ONLY (stack \in Seq(SeedFrames)), (left \in SeedIntValues), (right \in SeedIntValues),
            <2>nonempty, <2>pushes, LenProperties, ElementOfSeq, SMT DEF pushes, SeedFrames
    <2>first. /\ NativeAppend(prefix, pushes[1]) = first
              /\ first \in Seq(SeedFrames)
        BY ONLY <2>prefixType, <2>frames, ArrayEdits!AppendRetainsEveryIndex, AppendProperties, SMT
            DEF first, NativeAppend
    <2>second. /\ NativeAppend(first, pushes[2]) = second
               /\ second \in Seq(SeedFrames)
        BY ONLY <2>first, <2>frames, ArrayEdits!AppendRetainsEveryIndex, AppendProperties, SMT
            DEF second, NativeAppend
    <2>third. NativeAppend(second, pushes[3]) = Append(second, pushes[3])
        BY ONLY <2>second, <2>frames, ArrayEdits!AppendRetainsEveryIndex, SMT DEF NativeAppend
    <2>calls. NativeTraversalExpandedPending(stack, left, right) =
                SeedPhysicalPendingReplacement(stack, left, right)
        BY ONLY <2>prefix, <2>pushes, <2>first, <2>second, <2>third, SMT
            DEF NativeTraversalExpandedPending, SeedPhysicalPendingReplacement, prefix, pushes, first, second
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
    BY ONLY <1>operands, SMT DEF SeedExpansion, NativeTraversalStep,
        NativeTraversalReturnedField, NativeStackReturnedSlots
<1>. QED BY ONLY SeedExpansionInput, <1>native, ActualSeedExpansionPreservesThePendingReplacement, Isa

\* The checked successor collector calls the visitor with the internal append
\* callback. Its catch appends exactly a reached model failure. The remaining
\* reached operations are nonthrowing under the reviewed Swift interpretation.
NativeTraversalReachedFailures(stack) ==
    LET count == NativeTraversalCount(stack)
        index == NativeTraversalIndex(stack)
        drop == NativeStackExpansion.prefixDrop
        prefixCount == count - drop
    IN IF count <= NativeStackExpansion.countFloor THEN <<>>
       ELSE IF ~NativeTraversalElementInBounds(stack, index)
            THEN <<<<"indexOutOfBounds", index, Len(stack)>>>>
       ELSE IF NativeTraversalLast(stack)[NativeStackExpansion.localExpandedPosition] THEN <<>>
       ELSE IF prefixCount \notin SeedIntValues
            THEN <<<<"integerOverflow", "subtraction", <<count, drop>>>>>>
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
<1>access. NativeTraversalCount(pending) > NativeStackExpansion.countFloor =>
                  NativeTraversalIndex(pending) \in 1..Len(pending)
    BY ONLY <1>count, <1>safe, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT
        DEF SeedTraversalHelperCallsAreSafe, NativeTraversalIndex
<1>prefix. NativeTraversalEnabled(pending) =>
                /\ NativeTraversalCount(pending) - NativeStackExpansion.prefixDrop \in SeedIntValues
                /\ NativeTraversalCount(pending) - NativeStackExpansion.prefixDrop <= Len(pending)
    BY ONLY <1>count, <1>enabled, <1>safe, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT
        DEF SeedTraversalHelperCallsAreSafe
<1>. DEFINE count == NativeTraversalCount(pending)
            floor == NativeStackExpansion.countFloor
            expanded == NativeTraversalLast(pending)[NativeStackExpansion.localExpandedPosition]
            prefixCount == count - NativeStackExpansion.prefixDrop
<1>belowFloor. CASE count <= floor
    BY ONLY <1>belowFloor, SMT DEF count, floor, NativeTraversalReachedFailures
<1>aboveFloor. CASE count > floor
    <2>access. NativeTraversalElementInBounds(pending, NativeTraversalIndex(pending))
        BY ONLY SeedExpansionInput, <1>aboveFloor, <1>access, NativeTraversalElementReadsAValidIndex, SMT
            DEF count, floor, SeedExpansionInput
    <2>shape. /\ pending \in Seq(SeedFrames) /\ Len(pending) \in 1..Len(pending)
        BY ONLY SeedExpansionInput, <1>count, <1>aboveFloor, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT
            DEF SeedExpansionInput, count, floor
    <2>last. NativeTraversalLast(pending) = pending[Len(pending)]
        BY ONLY <2>shape, <1>count, NativeStackOperationsUseTheCheckedGuardAndIndex,
            NativeTraversalElementReadsAValidIndex, SMT DEF NativeTraversalLast, NativeTraversalIndex
    <2>frame. pending[Len(pending)] \in SeedFrames
        BY ONLY <2>shape, ElementOfSeq, SMT
    <2>boolean. expanded \in BOOLEAN
        BY ONLY <2>last, <2>frame, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT
            DEF expanded, SeedFrames
    <2>expanded. CASE expanded
        BY ONLY <1>aboveFloor, <2>access, <2>expanded, SMT DEF count, floor, expanded, NativeTraversalReachedFailures
    <2>unexpanded. CASE ~expanded
        <3>above. ~(count <= floor)
            BY ONLY <1>count, <1>aboveFloor, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT DEF count, floor
        <3>enabled. NativeTraversalEnabled(pending)
            BY ONLY <3>above, <2>unexpanded, SMT DEF count, floor, expanded, NativeTraversalEnabled
        <3>prefix. /\ prefixCount \in SeedIntValues /\ prefixCount <= Len(pending)
            BY ONLY <3>enabled, <1>prefix, SMT DEF prefixCount, count
        <3>checks. /\ ~(count <= floor) /\ ~(prefixCount > Len(pending))
            BY ONLY <1>count, <1>aboveFloor, <3>prefix, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT
                DEF count, floor, prefixCount
        <3>. QED BY ONLY <3>checks, <2>access, <2>unexpanded, <3>prefix, SMT
            DEF count, floor, expanded, prefixCount, NativeTraversalReachedFailures
    <2>. QED BY ONLY <2>boolean, <2>expanded, <2>unexpanded, SMT
<1>bounds. count <= floor \/ count > floor
    BY ONLY <1>count, NativeStackOperationsUseTheCheckedGuardAndIndex, SMT DEF count, floor
<1>. QED BY ONLY <1>bounds, <1>belowFloor, <1>aboveFloor, SMT

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
