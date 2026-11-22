---------------- MODULE SwiftTLABranchwiseSelectedChecking ----------------
EXTENDS TLAPS, Integers, SequenceTheorems_proofs, SwiftTLABranchwiseProjectedCheckingInputs,
        BranchwiseFailureStateProjectionProof
\* BranchwisePhysicalPageRequests

LOCAL Check == INSTANCE CheckingSelectionCompilerBinding WITH NoPropertyHandle <- ""
LOCAL M8At(visit) == INSTANCE BranchwiseConjunctionFailureHistories
    WITH divisor <- BranchwiseNativeSnapshots[visit][1],
         modulus <- BranchwiseNativeSnapshots[visit][2],
         selected <- BranchwiseNativeSnapshots[visit][3],
         result <- BranchwiseNativeSnapshots[visit][4]

LOCAL Visits == DOMAIN BranchwiseNativeSnapshots
LOCAL Native == BranchwiseNativeHistory
LOCAL Cuts == BranchwiseNativeCuts
LOCAL Lift(visit, events) ==
    [offset \in DOMAIN events |-> <<visit - 1, events[offset].action, events[offset]>>]
LOCAL AuthoredAt(visit) == Lift(visit, M8At(visit)!SourceOrderedFailureHistory)
LOCAL EmittedAt(visit) == Lift(visit, M8At(visit)!__SwiftTLAActionFailureHistory0)
LOCAL ReceivedAt(visit) ==
    [offset \in 1..(Cuts[visit + 1] - Cuts[visit]) |-> Native[Cuts[visit] + offset]]

\* The source IDs in the receipt route positions to visits. The cuts are
\* checked against the complete independently evaluated histories at every ID.
LOCAL NativeVisitOf(position) == Native[position][1] + 1
LOCAL Assemble(slices) ==
    [position \in 1..Cuts[Len(BranchwiseNativeSnapshots) + 1] |->
         slices[NativeVisitOf(position)][position - Cuts[NativeVisitOf(position)]]]

BranchwiseAuthoredSlices == [visit \in Visits |-> AuthoredAt(visit)]
BranchwiseEmittedSlices == [visit \in Visits |-> EmittedAt(visit)]
BranchwiseAuthoredHistory == Assemble(BranchwiseAuthoredSlices)
BranchwiseEmittedHistory == Assemble(BranchwiseEmittedSlices)

LOCAL FailureFactsAt(visit) ==
    LET At == INSTANCE BranchwiseConjunctionFailureHistories
        WITH divisor <- BranchwiseNativeSnapshots[visit][1],
             modulus <- BranchwiseNativeSnapshots[visit][2],
             selected <- BranchwiseNativeSnapshots[visit][3],
             result <- BranchwiseNativeSnapshots[visit][4]
    IN /\ At!__SwiftTLAActionFailureHistory0 = At!SourceOrderedFailureHistory
       /\ (At!__SwiftTLAEvaluationOK <=> DOMAIN At!SourceOrderedFailureHistory = {})

LOCAL BadVisit == CHOOSE visit \in Visits : ~FailureFactsAt(visit)
LOCAL M8Bad == INSTANCE BranchwiseConjunctionFailureHistories
    WITH divisor <- BranchwiseNativeSnapshots[BadVisit][1],
         modulus <- BranchwiseNativeSnapshots[BadVisit][2],
         selected <- BranchwiseNativeSnapshots[BadVisit][3],
         result <- BranchwiseNativeSnapshots[BadVisit][4]

LOCAL THEOREM TheObservedVisitsHaveTheCheckedM8FailureFacts ==
    \A visit \in Visits : FailureFactsAt(visit)
PROOF
<1>indices. Visits = 1..Len(BranchwiseNativeSnapshots)
    BY ONLY IsaM("simp") DEF Visits, BranchwiseNativeSnapshots
<1>states. \A visit \in Visits :
    /\ BranchwiseNativeSnapshots[visit][1] \in 0..1
    /\ BranchwiseNativeSnapshots[visit][2] \in {-1, 0, 1, 2}
    /\ BranchwiseNativeSnapshots[visit][3] \in Int
    /\ BranchwiseNativeSnapshots[visit][4] \in Int
    BY ONLY <1>indices, SMT DEF BranchwiseNativeSnapshots
<1>counterexample. ASSUME \E visit \in Visits : ~FailureFactsAt(visit)
                   PROVE FALSE
    <2>chosen. /\ BadVisit \in Visits /\ ~FailureFactsAt(BadVisit)
        BY ONLY (\E visit \in Visits : ~FailureFactsAt(visit)), SMT DEF BadVisit
    <2>typed. M8Bad!SourceDomain
        BY ONLY <1>states, <2>chosen, SMT DEF M8Bad!SourceDomain
    <2>history. M8Bad!__SwiftTLAActionFailureHistory0 = M8Bad!SourceOrderedFailureHistory
        BY ONLY <2>typed, M8Bad!ActualBranchwiseHistoryMatchesAuthoredOrder
    <2>presence. M8Bad!__SwiftTLAEvaluationOK <=> DOMAIN M8Bad!SourceOrderedFailureHistory = {}
        BY ONLY <2>typed, M8Bad!ActualBranchwiseEvaluationCheckUsesTheOrderedHistory
    <2>facts. FailureFactsAt(BadVisit)
        BY ONLY <2>history, <2>presence, SMT
        DEF FailureFactsAt,
            M8Bad!__SwiftTLAActionFailureHistory0, M8Bad!__SwiftTLAEvaluationOK,
            M8Bad!__SwiftTLAAnyEvaluationFailure0, M8Bad!SourceOrderedFailureHistory,
            M8Bad!SourceLeftFailureHistory, M8Bad!SourceRightFailureHistory,
            M8Bad!DivisionEvent, M8Bad!NegativeModuloEvent, M8Bad!FailureEvent,
            M8Bad!LeftBefore, M8Bad!RightBefore, M8Bad!vars
    <2>. QED BY ONLY <2>chosen, <2>facts
<1>. QED BY ONLY <1>counterexample, SMT

THEOREM ActualBranchwiseOrderedFailureHistoriesAgree ==
    /\ BranchwiseNativeFields = <<"divisor", "modulus", "selected", "result">>
    /\ Cuts[1] = 0
    /\ DOMAIN Cuts = 1..(Len(BranchwiseNativeSnapshots) + 1)
    /\ \A visit \in Visits : Cuts[visit] \in Nat /\ Cuts[visit] <= Cuts[visit + 1]
    /\ \A visit \in Visits :
          /\ DOMAIN AuthoredAt(visit) = 1..(Cuts[visit + 1] - Cuts[visit])
          /\ EmittedAt(visit) = AuthoredAt(visit)
          /\ ReceivedAt(visit) = AuthoredAt(visit)
    /\ BranchwiseAuthoredHistory = Native
    /\ BranchwiseEmittedHistory = Native
    /\ Len(Native) >= 2
PROOF
<1>layout. BranchwiseNativeFields = <<"divisor", "modulus", "selected", "result">>
    BY ONLY IsaM("simp") DEF BranchwiseNativeFields
<1>cuts. /\ Cuts[1] = 0
         /\ DOMAIN Cuts = 1..(Len(BranchwiseNativeSnapshots) + 1)
         /\ DOMAIN Native = 1..Cuts[Len(BranchwiseNativeSnapshots) + 1]
         /\ Len(Native) >= 2
    BY ONLY IsaM("simp") DEF Cuts, Native, BranchwiseNativeCuts, BranchwiseNativeHistory, BranchwiseNativeSnapshots
<1>monotone. \A visit \in Visits : Cuts[visit] \in Nat /\ Cuts[visit] <= Cuts[visit + 1]
    BY ONLY SMT DEF Visits, Cuts, BranchwiseNativeSnapshots, BranchwiseNativeCuts
<1>routes. \A position \in DOMAIN Native :
    /\ NativeVisitOf(position) \in Visits
    /\ Cuts[NativeVisitOf(position)] < position
    /\ position <= Cuts[NativeVisitOf(position) + 1]
    BY ONLY SMT DEF NativeVisitOf, Visits, Native, Cuts,
        BranchwiseNativeSnapshots, BranchwiseNativeHistory, BranchwiseNativeCuts
<1>slices. \A visit \in Visits :
    /\ DOMAIN AuthoredAt(visit) = 1..(Cuts[visit + 1] - Cuts[visit])
    /\ EmittedAt(visit) = AuthoredAt(visit)
    /\ ReceivedAt(visit) = AuthoredAt(visit)
    <2>. TAKE visit \in Visits
    <2>emitted. EmittedAt(visit) = AuthoredAt(visit)
        BY ONLY (visit \in Visits), TheObservedVisitsHaveTheCheckedM8FailureFacts,
            SMT DEF EmittedAt, AuthoredAt, FailureFactsAt
    <2>native. /\ DOMAIN AuthoredAt(visit) = 1..(Cuts[visit + 1] - Cuts[visit])
               /\ ReceivedAt(visit) = AuthoredAt(visit)
        BY ONLY (visit \in Visits), SMT
            DEF Visits, ReceivedAt, AuthoredAt, Lift, Cuts, Native,
                M8At!SourceOrderedFailureHistory, M8At!SourceLeftFailureHistory, M8At!SourceRightFailureHistory,
                BranchwiseNativeSnapshots, BranchwiseNativeHistory, BranchwiseNativeCuts
    <2>. QED BY ONLY <2>emitted, <2>native
<1>output. /\ BranchwiseAuthoredHistory = Native /\ BranchwiseEmittedHistory = Native
    <2>domain. /\ DOMAIN BranchwiseAuthoredHistory = DOMAIN Native
               /\ DOMAIN BranchwiseEmittedHistory = DOMAIN Native
        BY ONLY <1>cuts, SMT DEF BranchwiseAuthoredHistory, BranchwiseEmittedHistory, Assemble
    <2>values. \A position \in DOMAIN Native :
        /\ BranchwiseAuthoredHistory[position] = Native[position]
        /\ BranchwiseEmittedHistory[position] = Native[position]
        <3>. TAKE position \in DOMAIN Native
        <3>. DEFINE visit == NativeVisitOf(position)
                    offset == position - Cuts[visit]
        <3>indices. /\ visit \in Visits
                    /\ offset \in 1..(Cuts[visit + 1] - Cuts[visit])
            BY ONLY <1>routes, (position \in DOMAIN Native), SMT DEF visit, offset
        <3>actual. ReceivedAt(visit)[offset] = Native[position]
            BY ONLY <3>indices, SMT DEF ReceivedAt, offset
        <3>same. /\ AuthoredAt(visit)[offset] = Native[position]
                 /\ EmittedAt(visit)[offset] = Native[position]
            BY ONLY <1>slices, <3>indices, <3>actual, SMT
        <3>. QED BY ONLY <2>domain, (position \in DOMAIN Native), <3>indices, <3>same, SMT
            DEF BranchwiseAuthoredHistory, BranchwiseEmittedHistory, BranchwiseAuthoredSlices,
                BranchwiseEmittedSlices, Assemble, visit, offset
    <2>. QED BY ONLY <2>domain, <2>values, SMT
        DEF BranchwiseAuthoredHistory, BranchwiseEmittedHistory, Assemble, Native, BranchwiseNativeHistory
<1>. QED BY ONLY <1>layout, <1>cuts, <1>monotone, <1>slices, <1>output

LOCAL States == BranchwiseStateIDs
LOCAL Labels ==
    {edge[2] : edge \in BranchwiseNativeEdges} \cup {Native[index][2] : index \in DOMAIN Native}
LOCAL Properties == BranchwiseSourceSelection.invariants
LOCAL FailureRecords == {Native[index][3] : index \in DOMAIN Native}
LOCAL ClaimTable(claims) ==
    [property \in Properties |-> [id \in States |-> claims[property][id] = TRUE]]
LOCAL Reached ==
    Check!SourceCheckingReachable(States, Labels, BranchwiseNativeInitialIDs, BranchwiseNativeEdges)

\* The comparison uses the retained validator graph, with authored, native
\* and emitted histories and claims computed for those same state IDs.
LOCAL AuthoredObservation ==
    Check!SourceCheckingObservation(States, Labels, BranchwiseNativeInitialIDs, BranchwiseNativeEdges,
        BranchwiseSourceSelection.invariants, BranchwiseSourceSelection.reachability,
        ClaimTable(BranchwiseSourceClaims), {}, Check!ActionFailureEventSet(BranchwiseAuthoredHistory),
        BranchwiseSourceSelection.deadlock)
LOCAL NativeObservation ==
    Check!GeneratedCheckingObservation(Labels, BranchwiseNativeInitialIDs, BranchwiseNativeEdges, Reached,
        BranchwiseNativeSelection.invariants, BranchwiseNativeSelection.reachability,
        ClaimTable(BranchwiseNativeClaims), {}, Check!ActionFailureEventSet(Native),
        BranchwiseNativeSelection.deadlock)
LOCAL CFGObservation ==
    Check!GeneratedCheckingObservation(Labels, BranchwiseNativeInitialIDs, BranchwiseNativeEdges, Reached,
        BranchwiseCFGSelection.invariants, BranchwiseCFGSelection.reachability,
        ClaimTable(BranchwiseCFGClaims), {}, Check!ActionFailureEventSet(BranchwiseEmittedHistory),
        BranchwiseCFGSelection.deadlock)

THEOREM ActualBranchwiseNamedCheckingUsesTheSameOrderedFailures ==
    /\ AuthoredObservation = NativeObservation
    /\ AuthoredObservation = CFGObservation
    /\ BranchwiseAuthoredHistory = Native
    /\ BranchwiseEmittedHistory = Native
    /\ BranchwiseCFGEvaluationCheckEnabled
    /\ BranchwiseStateProjectionMatchesEmission
    /\ \A visit \in Visits :
           BranchwiseActualTLAEvaluationOK(BranchwiseNativeSnapshots[visit])
               <=> DOMAIN ReceivedAt(visit) = {}
    /\ \E first, second, omitted \in BranchwiseAuthoredInvariantNames :
           /\ first # second /\ first # omitted /\ second # omitted
           /\ Properties = {first, second}
           /\ omitted \notin Properties
    /\ \E visit \in Visits :
           /\ visit - 1 \in BranchwiseNativeInitialIDs
           /\ Len(BranchwiseAuthoredSlices[visit]) = 2
           /\ BranchwiseAuthoredSlices[visit][1][3].branch = 0
           /\ BranchwiseAuthoredSlices[visit][2][3].branch = 1
           /\ \A offset \in 1..2 :
                 BranchwiseAuthoredSlices[visit][offset] \in CFGObservation.actionFailures
PROOF
<1>selection. /\ BranchwiseSourceSelection = BranchwiseNativeSelection
              /\ BranchwiseSourceSelection = BranchwiseCFGSelection
    BY ONLY ActualBranchwiseInvariantSelectionAgrees
<1>signatures. /\ BranchwiseSourceSelection.invariants \subseteq Properties
               /\ BranchwiseSourceSelection.reachability \subseteq Properties
               /\ BranchwiseSourceSelection.deadlock \in BOOLEAN
    BY ONLY ActualBranchwiseInvariantSelectionAgrees, SMT DEF Properties
<1>claims. /\ ClaimTable(BranchwiseSourceClaims) \in [Properties -> [States -> BOOLEAN]]
           /\ ClaimTable(BranchwiseSourceClaims) = ClaimTable(BranchwiseNativeClaims)
           /\ ClaimTable(BranchwiseSourceClaims) = ClaimTable(BranchwiseCFGClaims)
    BY ONLY ActualBranchwiseClaimsAgreeOnObservedStates, SMT DEF ClaimTable
<1>graph. /\ BranchwiseNativeInitialIDs \subseteq States
          /\ BranchwiseNativeEdges \subseteq (States \X Labels \X States)
          /\ Reached \subseteq States
    BY ONLY SMT DEF BranchwiseNativeInitialIDs, BranchwiseNativeEdges, BranchwiseStateIDs,
        States, Labels, Reached, Check!SourceCheckingReachable, BranchwiseNativeSnapshots
<1>word. Native \in Seq(States \X Labels \X FailureRecords)
    BY ONLY SeqDef, SMT DEF Native, States, Labels, FailureRecords,
        BranchwiseNativeHistory, BranchwiseNativeEdges, BranchwiseStateIDs, BranchwiseNativeSnapshots
<1>native. /\ AuthoredObservation = NativeObservation
           /\ \A event \in States \X Labels \X FailureRecords :
                (event \in NativeObservation.actionFailures) <=>
                  (event[1] \in Reached /\ \E index \in DOMAIN Native : Native[index] = event)
    BY ONLY <1>selection, <1>signatures, <1>claims, <1>graph, <1>word,
        ActualBranchwiseOrderedFailureHistoriesAgree, Check!ExhaustiveSelectedCheckingWithOrderedActionFailures,
        SMT DEF AuthoredObservation, NativeObservation, Reached
<1>configured. NativeObservation = CFGObservation
    BY ONLY <1>selection, <1>claims, ActualBranchwiseOrderedFailureHistoriesAgree, SMT
        DEF NativeObservation, CFGObservation
<1>evaluation. \A visit \in Visits :
    BranchwiseActualTLAEvaluationOK(BranchwiseNativeSnapshots[visit])
        <=> DOMAIN ReceivedAt(visit) = {}
    <2>. TAKE visit \in Visits
    <2>presence. M8At(visit)!__SwiftTLAEvaluationOK <=> DOMAIN M8At(visit)!SourceOrderedFailureHistory = {}
        BY ONLY (visit \in Visits), TheObservedVisitsHaveTheCheckedM8FailureFacts, SMT DEF FailureFactsAt
    <2>mode. BranchwiseActualTLAEvaluationOK(BranchwiseNativeSnapshots[visit]) <=> M8At(visit)!__SwiftTLAEvaluationOK
        BY ONLY SMT DEF BranchwiseActualTLAEvaluationOK, BranchwisePredicates!__SwiftTLAEvaluationOK,
            M8At!__SwiftTLAEvaluationOK
    <2>domain. DOMAIN ReceivedAt(visit) = DOMAIN M8At(visit)!SourceOrderedFailureHistory
        BY ONLY (visit \in Visits), ActualBranchwiseOrderedFailureHistoriesAgree, SMT DEF AuthoredAt, Lift
    <2>. QED BY ONLY <2>presence, <2>mode, <2>domain
<1>named. \E first, second, omitted \in BranchwiseAuthoredInvariantNames :
    /\ first # second /\ first # omitted /\ second # omitted
    /\ Properties = {first, second}
    /\ omitted \notin Properties
    BY ONLY ActualBranchwiseInvariantSelectionAgrees, SMT DEF Properties
<1>initials. BranchwiseNativeInitialIDs \subseteq Reached
    <2>. TAKE id \in BranchwiseNativeInitialIDs
    <2>. DEFINE path == <<id>>
    <2>path. /\ path \in Seq(States)
             /\ Check!CheckingPath(States, Labels, BranchwiseNativeInitialIDs, BranchwiseNativeEdges, path)
             /\ path[Len(path)] = id
        BY ONLY (id \in BranchwiseNativeInitialIDs), <1>graph, SeqDef, SMT DEF path, Check!CheckingPath
    <2>. QED BY ONLY (id \in BranchwiseNativeInitialIDs), <2>path, <1>graph, SMT
        DEF Reached, Check!SourceCheckingReachable
<1>pair. \E visit \in Visits :
    /\ visit - 1 \in BranchwiseNativeInitialIDs
    /\ Cuts[visit + 1] - Cuts[visit] = 2
    /\ \A offset \in 1..2 :
           /\ Cuts[visit] + offset \in DOMAIN Native
           /\ Native[Cuts[visit] + offset][1] = visit - 1
           /\ Native[Cuts[visit] + offset][3].branch = offset - 1
    BY ONLY SMT DEF Visits, Cuts, Native, BranchwiseNativeSnapshots,
        BranchwiseNativeCuts, BranchwiseNativeHistory, BranchwiseNativeInitialIDs
<1>occurrences. \E visit \in Visits :
    /\ visit - 1 \in BranchwiseNativeInitialIDs
    /\ Len(BranchwiseAuthoredSlices[visit]) = 2
    /\ BranchwiseAuthoredSlices[visit][1][3].branch = 0
    /\ BranchwiseAuthoredSlices[visit][2][3].branch = 1
    /\ \A offset \in 1..2 :
          BranchwiseAuthoredSlices[visit][offset] \in CFGObservation.actionFailures
    <2>candidate. PICK visit \in Visits :
        /\ visit - 1 \in BranchwiseNativeInitialIDs
        /\ Cuts[visit + 1] - Cuts[visit] = 2
        /\ \A offset \in 1..2 :
               /\ Cuts[visit] + offset \in DOMAIN Native
               /\ Native[Cuts[visit] + offset][1] = visit - 1
               /\ Native[Cuts[visit] + offset][3].branch = offset - 1
        BY ONLY <1>pair
    <2>slice. BranchwiseAuthoredSlices[visit] = ReceivedAt(visit)
        BY ONLY <2>candidate, ActualBranchwiseOrderedFailureHistoriesAgree, SMT DEF BranchwiseAuthoredSlices
    <2>typed. ReceivedAt(visit) \in [1..2 -> (States \X Labels \X FailureRecords)]
        BY ONLY <2>candidate, <1>word, ElementOfSeq, SMT DEF ReceivedAt
    <2>length. Len(BranchwiseAuthoredSlices[visit]) = 2
        BY ONLY <2>candidate, <2>slice, <2>typed, LenProperties, SeqDef, SMT DEF ReceivedAt
    <2>values. \A offset \in 1..2 :
        /\ BranchwiseAuthoredSlices[visit][offset][3].branch = offset - 1
        /\ BranchwiseAuthoredSlices[visit][offset] \in CFGObservation.actionFailures
        <3>. TAKE offset \in 1..2
        <3>. DEFINE position == Cuts[visit] + offset
        <3>position. /\ position \in DOMAIN Native
                     /\ Native[position][1] \in Reached
                     /\ Native[position][3].branch = offset - 1
            BY ONLY <2>candidate, <1>initials, (offset \in 1..2), SMT DEF position
        <3>entry. BranchwiseAuthoredSlices[visit][offset] = Native[position]
            BY ONLY <2>candidate, <2>slice, (offset \in 1..2), SMT DEF ReceivedAt, position
        <3>. QED BY ONLY <3>entry, <3>position, <1>native, <1>configured, <1>word, ElementOfSeq, SMT
    <2>. QED BY ONLY <2>candidate, <2>length, <2>values, SMT
<1>. QED BY ONLY <1>native, <1>configured, <1>named, <1>occurrences, <1>evaluation,
    ActualBranchwiseOrderedFailureHistoriesAgree, ActualBranchwiseCFGContainsTheEvaluationInvariant,
    TheProjectionUsesTheActualEmittedStateOperators, SMT

====
