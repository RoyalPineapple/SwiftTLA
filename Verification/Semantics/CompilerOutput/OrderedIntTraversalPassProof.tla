---------------- MODULE OrderedIntTraversalPassProof ----------------
EXTENDS OrderedIntTraversalPass, OrderedIntTraversalPassSource, TLAPS, SequenceTheorems_proofs

SeedIntMax == ((9 * 1000000000 + 223372036) * 1000000000 + 854775807)
SeedIntMin == ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)
SeedIntValues == SeedIntMin..SeedIntMax
SeedFrames == SeedIntValues \X BOOLEAN

LOCAL SeedPairShape(frame) ==
    /\ DOMAIN frame = 1..2
    /\ frame[1] \in Int
    /\ frame[2] \in BOOLEAN

LOCAL SeedCheckedPair(frame) == CASE SeedPairShape(frame) -> frame

LOCAL THEOREM SeedTypedFrameSuppliesTheCheckedPair ==
    ASSUME NEW frame \in SeedFrames
    PROVE /\ SeedPairShape(frame)
          /\ SeedCheckedPair(frame) = frame
PROOF
<1>shape. SeedPairShape(frame)
    BY ONLY (frame \in SeedFrames), SMT DEF SeedFrames, SeedIntValues, SeedPairShape
<1>. QED BY ONLY <1>shape, SMT DEF SeedCheckedPair

SeedExpansionInput ==
    /\ pending \in Seq(SeedFrames)
    /\ Len(pending) + 2 <= SeedIntMax
    /\ leftChild \in SeedIntValues
    /\ rightChild \in SeedIntValues

SeedAuthoredInit ==
    /\ pending = AuthoredStackInitialization.pending
    /\ leftChild = AuthoredStackInitialization.leftChild
    /\ rightChild = AuthoredStackInitialization.rightChild

SeedBootstrapInitialization ==
    [pending |-> <<>>, leftChild |-> 0, rightChild |-> 0, elementTypes |-> <<"Int", "Bool">>]

THEOREM ActualSeedInitMatchesTheAuthoredInitializers ==
    /\ AuthoredStackInitialization = SeedBootstrapInitialization
    /\ (Init <=> SeedAuthoredInit)
    /\ (SeedAuthoredInit => SeedExpansionInput)
PROOF
<1>source. AuthoredStackInitialization = SeedBootstrapInitialization
    BY ONLY AuthoredStackInitializationMatchesTypedIR, SMT DEF TypedStackInitialization, SeedBootstrapInitialization
<1>values. SeedAuthoredInit <=> pending = <<>> /\ leftChild = 0 /\ rightChild = 0
    BY ONLY <1>source, SMT DEF SeedAuthoredInit, SeedBootstrapInitialization
<1>physical. Init <=> SeedAuthoredInit
    BY ONLY <1>values, SMT DEF Init
<1>typed. SeedAuthoredInit => SeedExpansionInput
    BY ONLY <1>values, SeqDef, SMT DEF SeedExpansionInput, SeedFrames, SeedIntValues, SeedIntMin, SeedIntMax
<1>. QED BY ONLY <1>source, <1>physical, <1>typed

SeedExpansionEnabled(stack) ==
    IF Len(stack) = 0 THEN FALSE ELSE ~stack[Len(stack)][2]

SeedExpansionPrefix(stack) ==
    [index \in 1..(Len(stack) - 1) |-> stack[index]]

SeedExpansionSuffix(origin, left, right) ==
    <<<<origin, TRUE>>, <<right, FALSE>>, <<left, FALSE>>>>

SeedExpandedPending(stack, left, right) ==
    SeedExpansionPrefix(stack) \o SeedExpansionSuffix(stack[Len(stack)][1], left, right)

SeedPhysicalPendingReplacement(stack, left, right) ==
    Append(Append(Append(SubSeq(stack, 1, Len(stack) - 1),
        <<stack[Len(stack)][1], TRUE>>), <<right, FALSE>>), <<left, FALSE>>)

LOCAL SeedAuthoredPushOrigin(push, stack, left, right) ==
    IF push.source = "local" THEN stack[Len(stack)][push.position]
    ELSE IF push.source = AuthoredStackExpansion.left THEN left ELSE right

LOCAL SeedAuthoredPushes(stack, left, right) ==
    [index \in DOMAIN AuthoredStackExpansion.pushes |->
        <<SeedAuthoredPushOrigin(AuthoredStackExpansion.pushes[index], stack, left, right),
          AuthoredStackExpansion.pushes[index].expanded>>]

SeedAuthoredPendingReplacement(stack, left, right) ==
    [index \in 1..(Len(stack) - AuthoredStackExpansion.prefixDrop) |-> stack[index]]
    \o SeedAuthoredPushes(stack, left, right)

SeedAuthoredExpansionEnabled(stack) ==
    IF Len(stack) <= AuthoredStackExpansion.countFloor THEN FALSE
    ELSE ~stack[Len(stack)][AuthoredStackExpansion.localExpandedPosition]

SeedExpansion ==
    IF SeedAuthoredExpansionEnabled(pending)
    THEN /\ pending' = SeedAuthoredPendingReplacement(pending, leftChild, rightChild)
         /\ UNCHANGED <<leftChild, rightChild>>
    ELSE FALSE

LOCAL SeedRenderedLastDefined(stack) ==
    IF Len(stack) \in DOMAIN stack THEN TRUE ELSE FALSE

LOCAL SeedRenderedSubtractDefined(size) ==
    IF size >= -1000000000 /\ size <= 1000000000 /\ 1 >= -1000000000 /\ 1 <= 1000000000
    THEN TRUE
    ELSE IF 1 > 0 THEN size >= SeedIntMin + 1
         ELSE IF 1 < 0 THEN size <= SeedIntMax + 1 ELSE TRUE

LOCAL SeedRenderedReplacementDefined(stack, frame, left, right) ==
    IF SeedRenderedSubtractDefined(Len(stack))
    THEN IF Len(stack) - 1 <= Len(stack)
         THEN IF SeedPairShape(<<frame[1], TRUE>>)
              THEN IF SeedPairShape(<<right, FALSE>>)
                   THEN IF SeedPairShape(<<left, FALSE>>) THEN TRUE ELSE FALSE
                   ELSE FALSE
              ELSE FALSE
         ELSE FALSE
    ELSE FALSE

LOCAL SeedRenderedReplacement(stack, frame, left, right) ==
    Append(Append(Append(SubSeq(stack, 1, Len(stack) - 1),
        SeedCheckedPair(<<frame[1], TRUE>>)),
        SeedCheckedPair(<<right, FALSE>>)),
        SeedCheckedPair(<<left, FALSE>>))

LOCAL SeedRenderedExpansion ==
    /\ ((Len(pending) > 0) = TRUE)
    /\ IF SeedRenderedLastDefined(pending)
       THEN LET frame == pending[Len(pending)]
            IN /\ ((~frame[2]) = TRUE)
               /\ IF SeedRenderedReplacementDefined(pending, frame, leftChild, rightChild)
                  THEN LET replacement == SeedRenderedReplacement(pending, frame, leftChild, rightChild)
                       IN ((TRUE /\ pending' = replacement) /\ (UNCHANGED leftChild /\ UNCHANGED rightChild))
                  ELSE FALSE
       ELSE FALSE

LOCAL THEOREM ActualSeedActionUsesTheRenderedChecks == expand <=> SeedRenderedExpansion
    BY ONLY DEF expand, SeedRenderedExpansion, SeedRenderedLastDefined, SeedRenderedReplacementDefined,
        SeedRenderedSubtractDefined, SeedRenderedReplacement, SeedCheckedPair, SeedPairShape, SeedIntMin, SeedIntMax

SeedAuthoredExpansionFailures ==
    IF Len(pending) <= AuthoredStackExpansion.countFloor THEN <<>>
    ELSE IF Len(pending) \notin DOMAIN pending THEN <<"lastIndex">>
    ELSE IF pending[Len(pending)][AuthoredStackExpansion.localExpandedPosition] THEN <<>>
    ELSE LET length == Len(pending) - AuthoredStackExpansion.prefixDrop
         IN IF length \notin SeedIntValues THEN <<"prefixArithmetic">>
            ELSE IF length > Len(pending) THEN <<"prefixIndex">> ELSE <<>>

\* These observations classify the reached tests in expand.
SeedRenderedExpansionFailures ==
    IF ~(Len(pending) > 0) THEN <<>>
    ELSE IF ~SeedRenderedLastDefined(pending) THEN <<"lastIndex">>
    ELSE IF pending[Len(pending)][2] THEN <<>>
    ELSE IF ~SeedRenderedReplacementDefined(pending, pending[Len(pending)], leftChild, rightChild)
         THEN <<"replacement">> ELSE <<>>

SeedTraversalHelperCallsAreSafe ==
    /\ (Len(pending) > 0 => Len(pending) \in 1..Len(pending))
    /\ (SeedExpansionEnabled(pending) =>
           /\ Len(pending) - 1 \in 0..Len(pending)
           /\ Len(pending) - 1 \in SeedIntValues
           /\ Len(pending) + 2 <= SeedIntMax)

LOCAL SeedOperandRows ==
    <<[source |-> "local", position |-> 1, expanded |-> TRUE],
      [source |-> "rightChild", position |-> 0, expanded |-> FALSE],
      [source |-> "leftChild", position |-> 0, expanded |-> FALSE]>>

THEOREM SeedAuthoredExpansionUsesTheBoundFieldsAndPushes ==
    /\ AuthoredStackExpansion.label = "expand"
    /\ AuthoredStackExpansion.stack = "pending"
    /\ AuthoredStackExpansion.write = "pending"
    /\ AuthoredStackExpansion.left = "leftChild"
    /\ AuthoredStackExpansion.right = "rightChild"
    /\ AuthoredStackExpansion.lastIndex = "count"
    /\ AuthoredStackExpansion.frame = {"leftChild", "rightChild"}
    /\ AuthoredStackExpansion.countFloor = 0
    /\ AuthoredStackExpansion.prefixDrop = 1
    /\ AuthoredStackExpansion.localExpandedPosition = 2
    /\ \A stack \in Seq(SeedFrames) :
           /\ SeedAuthoredExpansionEnabled(stack) = SeedExpansionEnabled(stack)
           /\ \A left, right \in SeedIntValues :
                 SeedAuthoredPendingReplacement(stack, left, right) = SeedExpandedPending(stack, left, right)
PROOF
<1>roles. /\ AuthoredStackExpansion.label = "expand"
          /\ AuthoredStackExpansion.stack = "pending"
          /\ AuthoredStackExpansion.write = "pending"
          /\ AuthoredStackExpansion.left = "leftChild"
          /\ AuthoredStackExpansion.right = "rightChild"
          /\ AuthoredStackExpansion.lastIndex = "count"
          /\ AuthoredStackExpansion.frame = {"leftChild", "rightChild"}
          /\ AuthoredStackExpansion.countFloor = 0
          /\ AuthoredStackExpansion.localExpandedPosition = 2
          /\ AuthoredStackExpansion.prefixDrop = 1
          /\ AuthoredStackExpansion.pushes = SeedOperandRows
    BY ONLY AuthoredStackExpansionMatchesTypedIR, IsaM("simp") DEF TypedStackExpansion, SeedOperandRows
<1>guard. \A stack \in Seq(SeedFrames) :
    SeedAuthoredExpansionEnabled(stack) = SeedExpansionEnabled(stack)
    BY ONLY <1>roles, LenProperties, SMT DEF SeedAuthoredExpansionEnabled, SeedExpansionEnabled
<1>values. \A stack \in Seq(SeedFrames), left, right \in SeedIntValues :
    SeedAuthoredPendingReplacement(stack, left, right) = SeedExpandedPending(stack, left, right)
    <2>. TAKE stack \in Seq(SeedFrames), left, right \in SeedIntValues
    <2>. DEFINE pushes == SeedAuthoredPushes(stack, left, right)
                meaning == SeedExpansionSuffix(stack[Len(stack)][1], left, right)
    <2>domain. /\ DOMAIN pushes = 1..3
               /\ DOMAIN meaning = 1..3
        BY ONLY <1>roles, IsaM("simp") DEF pushes, meaning, SeedAuthoredPushes, SeedExpansionSuffix, SeedOperandRows
    <2>positions. \A index \in 1..3 : pushes[index] = meaning[index]
        BY ONLY <1>roles, <2>domain, SMT
            DEF pushes, meaning, SeedAuthoredPushes, SeedAuthoredPushOrigin, SeedExpansionSuffix, SeedOperandRows
    <2>suffix. pushes = meaning
        BY ONLY <1>roles, <2>domain, <2>positions, SMT DEF pushes, meaning, SeedAuthoredPushes, SeedExpansionSuffix
    <2>. QED BY ONLY <1>roles, <2>suffix, SMT
        DEF pushes, meaning, SeedAuthoredPendingReplacement, SeedExpandedPending, SeedExpansionPrefix
<1>. QED BY ONLY <1>roles, <1>guard, <1>values, SMT

THEOREM SeedPendingExpansionRetainsPrefixAndPushOrder ==
    ASSUME NEW stack \in Seq(SeedFrames), Len(stack) > 0,
           NEW left \in SeedIntValues, NEW right \in SeedIntValues
    PROVE LET result == SeedExpandedPending(stack, left, right)
          IN /\ result \in Seq(SeedFrames)
             /\ Len(result) = Len(stack) + 2
             /\ \A index \in 1..(Len(stack) - 1) : result[index] = stack[index]
             /\ result[Len(stack)] = <<stack[Len(stack)][1], TRUE>>
             /\ result[Len(stack) + 1] = <<right, FALSE>>
             /\ result[Len(stack) + 2] = <<left, FALSE>>
PROOF
<1>. DEFINE size == Len(stack)
            prefix == SeedExpansionPrefix(stack)
            suffix == SeedExpansionSuffix(stack[size][1], left, right)
<1>stack. /\ size \in Nat
          /\ DOMAIN stack = 1..size
          /\ stack[size] \in SeedFrames
    BY ONLY (stack \in Seq(SeedFrames)), (Len(stack) > 0), LenProperties, ElementOfSeq,
        SMT DEF size
<1>prefix. /\ prefix \in Seq(SeedFrames)
           /\ Len(prefix) = size - 1
           /\ \A index \in 1..(size - 1) : prefix[index] = stack[index]
    <2>function. prefix \in [1..(size - 1) -> SeedFrames]
        BY ONLY <1>stack, (stack \in Seq(SeedFrames)), (Len(stack) > 0), ElementOfSeq,
            SMT DEF prefix, size, SeedExpansionPrefix
    <2>. QED BY ONLY <2>function, <1>stack, (Len(stack) > 0), SeqDef, LenProperties,
        SMT DEF prefix, size, SeedExpansionPrefix
<1>suffix. /\ suffix \in Seq(SeedFrames)
           /\ Len(suffix) = 3
           /\ suffix[1] = <<stack[size][1], TRUE>>
           /\ suffix[2] = <<right, FALSE>>
           /\ suffix[3] = <<left, FALSE>>
    BY ONLY <1>stack, (left \in SeedIntValues), (right \in SeedIntValues), SeqDef,
        SMT DEF suffix, SeedExpansionSuffix, SeedFrames
<1>. QED BY ONLY <1>prefix, <1>suffix, ConcatProperties, SMT DEF SeedExpandedPending, size, prefix, suffix

THEOREM SeedPhysicalPendingReplacementMatchesTheSource ==
    ASSUME NEW stack \in Seq(SeedFrames), Len(stack) > 0,
           NEW left \in SeedIntValues, NEW right \in SeedIntValues
    PROVE SeedPhysicalPendingReplacement(stack, left, right) = SeedExpandedPending(stack, left, right)
PROOF
<1>. DEFINE size == Len(stack)
            popped == SeedExpansionPrefix(stack)
            parent == <<stack[size][1], TRUE>>
            rightFrame == <<right, FALSE>>
            leftFrame == <<left, FALSE>>
            first == Append(popped, parent)
            second == Append(first, rightFrame)
<1>stack. /\ size \in Nat
          /\ size - 1 \in 0..size
          /\ stack[size] \in SeedFrames
    BY ONLY (stack \in Seq(SeedFrames)), (Len(stack) > 0), LenProperties, ElementOfSeq, SMT DEF size
<1>prefix. /\ SubSeq(stack, 1, size - 1) = popped
           /\ popped \in Seq(SeedFrames)
    <2>function. popped \in [1..(size - 1) -> SeedFrames]
        BY ONLY <1>stack, (stack \in Seq(SeedFrames)), ElementOfSeq, SMT DEF popped, size, SeedExpansionPrefix
    <2>same. SubSeq(stack, 1, size - 1) = popped
        BY ONLY <1>stack, (stack \in Seq(SeedFrames)), SubSeqRestrict, SMT
            DEF popped, SeedExpansionPrefix, Restrict, size
    <2>. QED BY ONLY <2>function, <2>same, <1>stack, SeqDef, SMT DEF size
<1>frames. /\ parent \in SeedFrames
           /\ rightFrame \in SeedFrames
           /\ leftFrame \in SeedFrames
    BY ONLY <1>stack, (left \in SeedIntValues), (right \in SeedIntValues), SMT
        DEF parent, rightFrame, leftFrame, SeedFrames
<1>appended. /\ first \in Seq(SeedFrames)
             /\ second \in Seq(SeedFrames)
             /\ first = popped \o <<parent>>
             /\ second = first \o <<rightFrame>>
             /\ Append(second, leftFrame) = second \o <<leftFrame>>
    BY ONLY <1>prefix, <1>frames, AppendProperties, AppendIsConcat, SMT DEF first, second
<1>suffix. /\ <<parent>> \in Seq(SeedFrames)
           /\ <<rightFrame>> \in Seq(SeedFrames)
           /\ <<leftFrame>> \in Seq(SeedFrames)
           /\ (<<parent>> \o <<rightFrame>>) \o <<leftFrame>> = SeedExpansionSuffix(stack[size][1], left, right)
    BY ONLY <1>frames, SeqDef, SMT DEF parent, rightFrame, leftFrame, SeedExpansionSuffix
<1>. QED BY ONLY <1>prefix, <1>appended, <1>suffix, ConcatProperties, ConcatAssociative, SMT
    DEF SeedPhysicalPendingReplacement, SeedExpandedPending, size, popped, parent, rightFrame, leftFrame, first, second

LOCAL THEOREM SeedExpansionInputSuppliesTheReachedBoundsAndPairViews ==
    ASSUME SeedExpansionInput, Len(pending) > 0
    PROVE /\ Len(pending) \in DOMAIN pending
          /\ Len(pending) - 1 \in 0..Len(pending)
          /\ Len(pending) - 1 \in SeedIntValues
          /\ \A frame \in {<<pending[Len(pending)][1], TRUE>>, <<rightChild, FALSE>>, <<leftChild, FALSE>>} :
                /\ SeedPairShape(frame)
                /\ SeedCheckedPair(frame) = frame
PROOF
<1>bounds. /\ Len(pending) \in DOMAIN pending
           /\ Len(pending) - 1 \in 0..Len(pending)
           /\ Len(pending) - 1 \in SeedIntValues
    BY ONLY SeedExpansionInput, Len(pending) > 0, LenProperties, SMT
        DEF SeedExpansionInput, SeedIntValues, SeedIntMin, SeedIntMax
<1>last. pending[Len(pending)] \in SeedFrames
    BY ONLY SeedExpansionInput, <1>bounds, ElementOfSeq, SMT DEF SeedExpansionInput
<1>frames. {<<pending[Len(pending)][1], TRUE>>, <<rightChild, FALSE>>, <<leftChild, FALSE>>} \subseteq SeedFrames
    BY ONLY <1>last, SeedExpansionInput, SMT DEF SeedExpansionInput, SeedFrames
<1>. QED BY ONLY <1>bounds, <1>frames, SeedTypedFrameSuppliesTheCheckedPair, SMT

LOCAL THEOREM SeedReachedRenderedChecksAndReplacementAreDefined ==
    ASSUME SeedExpansionInput, Len(pending) > 0
    PROVE /\ SeedRenderedLastDefined(pending)
          /\ SeedRenderedReplacementDefined(pending, pending[Len(pending)], leftChild, rightChild)
          /\ SeedRenderedReplacement(pending, pending[Len(pending)], leftChild, rightChild) =
                SeedPhysicalPendingReplacement(pending, leftChild, rightChild)
PROOF
<1>reached. /\ Len(pending) \in DOMAIN pending
            /\ Len(pending) - 1 \in 0..Len(pending)
            /\ Len(pending) - 1 \in SeedIntValues
            /\ \A frame \in {<<pending[Len(pending)][1], TRUE>>, <<rightChild, FALSE>>, <<leftChild, FALSE>>} :
                  /\ SeedPairShape(frame)
                  /\ SeedCheckedPair(frame) = frame
    BY ONLY SeedExpansionInput, Len(pending) > 0, SeedExpansionInputSuppliesTheReachedBoundsAndPairViews
<1>subtract. SeedRenderedSubtractDefined(Len(pending))
    BY ONLY <1>reached, Len(pending) > 0, SMT DEF SeedRenderedSubtractDefined, SeedIntValues, SeedIntMin
<1>tests. /\ SeedRenderedLastDefined(pending)
          /\ SeedRenderedReplacementDefined(pending, pending[Len(pending)], leftChild, rightChild)
    BY ONLY <1>reached, <1>subtract, SMT DEF SeedRenderedLastDefined, SeedRenderedReplacementDefined
<1>value. SeedRenderedReplacement(pending, pending[Len(pending)], leftChild, rightChild) =
              SeedPhysicalPendingReplacement(pending, leftChild, rightChild)
    BY ONLY <1>reached, SMT DEF SeedRenderedReplacement, SeedPhysicalPendingReplacement
<1>. QED BY ONLY <1>tests, <1>value

THEOREM ActualSeedExpansionPreservesThePendingReplacement ==
    ASSUME SeedExpansionInput
    PROVE expand <=> SeedExpansion
PROOF
<1>shape. /\ Len(pending) \in Nat
          /\ DOMAIN pending = 1..Len(pending)
    BY ONLY SeedExpansionInput, LenProperties, SMT DEF SeedExpansionInput
<1>authored. SeedExpansion <=>
    IF SeedExpansionEnabled(pending)
    THEN /\ pending' = SeedExpandedPending(pending, leftChild, rightChild)
         /\ UNCHANGED <<leftChild, rightChild>>
    ELSE FALSE
    BY ONLY SeedExpansionInput, SeedAuthoredExpansionUsesTheBoundFieldsAndPushes, SMT
        DEF SeedExpansionInput, SeedExpansion
<1>empty. CASE Len(pending) = 0
    BY ONLY <1>empty, <1>authored, ActualSeedActionUsesTheRenderedChecks, SMT
        DEF SeedRenderedExpansion, SeedExpansionEnabled
<1>nonempty. CASE Len(pending) > 0
    <2>reached. /\ SeedRenderedLastDefined(pending)
                /\ SeedRenderedReplacementDefined(pending, pending[Len(pending)], leftChild, rightChild)
                /\ SeedRenderedReplacement(pending, pending[Len(pending)], leftChild, rightChild) =
                      SeedPhysicalPendingReplacement(pending, leftChild, rightChild)
        BY ONLY SeedExpansionInput, <1>nonempty, SeedReachedRenderedChecksAndReplacementAreDefined
    <2>replacement. SeedPhysicalPendingReplacement(pending, leftChild, rightChild) =
                     SeedExpandedPending(pending, leftChild, rightChild)
        BY ONLY SeedExpansionInput, <1>nonempty, SeedPhysicalPendingReplacementMatchesTheSource, SMT DEF SeedExpansionInput
    <2>. QED BY ONLY <1>nonempty, <1>authored, <2>reached, <2>replacement,
        ActualSeedActionUsesTheRenderedChecks, SMT DEF SeedRenderedExpansion, SeedExpansionEnabled
<1>. QED BY ONLY <1>shape, <1>empty, <1>nonempty, SMT

THEOREM ActualSeedExpansionDoesNotFailOnTypedInput ==
    ASSUME SeedExpansionInput
    PROVE /\ SeedAuthoredExpansionFailures = <<>>
          /\ SeedRenderedExpansionFailures = <<>>
          /\ SeedTraversalHelperCallsAreSafe
PROOF
<1>shape. /\ Len(pending) \in Nat
          /\ DOMAIN pending = 1..Len(pending)
    BY ONLY SeedExpansionInput, LenProperties, SMT DEF SeedExpansionInput
<1>source. /\ AuthoredStackExpansion.countFloor = 0
           /\ AuthoredStackExpansion.prefixDrop = 1
           /\ AuthoredStackExpansion.localExpandedPosition = 2
    BY ONLY SeedAuthoredExpansionUsesTheBoundFieldsAndPushes
<1>empty. CASE Len(pending) = 0
    BY ONLY <1>empty, <1>source, SMT DEF SeedAuthoredExpansionFailures, SeedRenderedExpansionFailures,
        SeedTraversalHelperCallsAreSafe, SeedExpansionEnabled
<1>nonempty. CASE Len(pending) > 0
    <2>bounds. /\ Len(pending) \in DOMAIN pending
                /\ Len(pending) - 1 \in 0..Len(pending)
                /\ Len(pending) - 1 \in SeedIntValues
        BY ONLY SeedExpansionInput, <1>nonempty, SeedExpansionInputSuppliesTheReachedBoundsAndPairViews
    <2>physical. /\ SeedRenderedLastDefined(pending)
                  /\ SeedRenderedReplacementDefined(pending, pending[Len(pending)], leftChild, rightChild)
        BY ONLY SeedExpansionInput, <1>nonempty, SeedReachedRenderedChecksAndReplacementAreDefined
    <2>. QED BY ONLY <1>shape, <1>source, <1>nonempty, <2>bounds, <2>physical, SeedExpansionInput, SMT
        DEF SeedExpansionInput, SeedAuthoredExpansionFailures, SeedRenderedExpansionFailures,
            SeedTraversalHelperCallsAreSafe, SeedExpansionEnabled
<1>. QED BY ONLY <1>shape, <1>empty, <1>nonempty, SMT

====
