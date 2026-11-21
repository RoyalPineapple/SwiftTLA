---- MODULE SwiftTLAOrderedRHSBackendAgreement ----
EXTENDS SwiftTLAOrderedRHSConfiguredProof, SwiftTLANativeAssignmentActions, TLAPS

\* The native packet records this failure from the real visitor of the actual initial machine.
LOCAL ActualNativeFailure == NativeAssignmentFailure
ActualNativeProjection ==
    RHSOutputFailureEvent(ActualNativeFailure.site, ActualNativeFailure.payload[2],
        ActualNativeFailure.payload[3], ActualNativeFailure.completed)

LOCAL NativeFormalNames == [key \in RHSOutputKeys |-> key]
LOCAL NativeActionOrdinal == ActualNativeFailure.actionOrdinal
LOCAL DecodedNativeAction == NativeActionRows[NativeActionOrdinal + 1][2]
LOCAL NormalizedNativeAction == RHSOutputInput!Rule!NativeAssignmentRekey(DecodedNativeAction, NativeFormalNames, "pc")

ActualNativeAssignmentCaptureHistory(history) ==
    RHSOutputInput!Rule!NativeAssignmentCaptureHistory(RHSOutputBefore, NormalizedNativeAction, RHSOutputCount,
        RHSOutputInput!Rule!NativeAssignmentProjectedHistory(history, RHSOutputCount))

THEOREM ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles ==
    /\ RHSOutputInput!Rule!NativeAssignmentDispatchMatches(NativeActionRows, NativeActionDispatchLabels,
           NativeActionOrdinal, RHSOutputActionLabel, "advance")
    /\ RHSOutputInput!Rule!NativeAssignmentsNameTheirOperandsAndWrites(RHSOutputRows, DecodedNativeAction,
           NativeFormalNames, "pc", RHSOutputEntry, RHSOutputExit)
PROOF
<1>ordinal. NativeActionOrdinal = 0
    BY ONLY SMT DEF NativeActionOrdinal, ActualNativeFailure, NativeAssignmentFailure
<1>dispatch.
    RHSOutputInput!Rule!NativeAssignmentDispatchMatches(NativeActionRows, NativeActionDispatchLabels,
        NativeActionOrdinal, RHSOutputActionLabel, "advance")
    BY ONLY <1>ordinal, SMT DEF RHSOutputInput!Rule!NativeAssignmentDispatchMatches,
        NativeActionRows, NativeActionDispatchLabels, RHSOutputActionLabel
<1>selected. DecodedNativeAction = NativeSelectedAction
    BY ONLY <1>ordinal, SMT DEF DecodedNativeAction, NativeActionRows
<1>keys. RHSOutputInput!MasterFields = RHSOutputKeys
    BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
<1>names.
    /\ \A key \in RHSOutputInput!MasterFields :
        RHSOutputInput!Rule!NativeCopyKey(RHSOutputInput!MasterFields, NativeFormalNames, "pc", key) = key
    /\ RHSOutputInput!Rule!NativeCopyKey(RHSOutputInput!MasterFields, NativeFormalNames, "pc", "pc") =
        RHSOutputInput!Rule!NativeCopyControlSlot
    BY ONLY SMT DEF RHSOutputInput!Rule!NativeCopyKey, NativeFormalNames, RHSOutputKeys, RHSOutputInput!MasterFields
<1>slots. RHSOutputInput!Rule!NativeCopyKnownRoles(DecodedNativeAction, RHSOutputInput!MasterFields, NativeFormalNames, "pc")
    <2>. DEFINE fields == RHSOutputInput!MasterFields
                keys == RHSOutputInput!Rule!NativeCopyPhysicalKeys(fields, NativeFormalNames, "pc")
    <2>map.
        /\ fields \subseteq STRING /\ DOMAIN NativeFormalNames = fields
        /\ \A key \in fields : NativeFormalNames[key] = key /\ key # "pc"
        /\ keys = fields \cup {"pc"}
        BY ONLY <1>keys, SMT DEF fields, keys, NativeFormalNames, RHSOutputKeys, RHSOutputInput!Rule!NativeCopyPhysicalKeys
    <2>captures. \A index \in DOMAIN NativeSelectedCaptures :
        NativeSelectedCaptures[index][1] = "state" => NativeSelectedCaptures[index][2] \in keys
        BY ONLY <2>map, SMT DEF NativeSelectedCaptures, NativeSelectedCaptureTags, NativeSelectedNodeReads, fields,
            RHSOutputInput!MasterFields
    <2>writes. \A index \in DOMAIN NativeSelectedWrites :
        /\ NativeSelectedWrites[index][1] \in keys
        /\ (NativeSelectedWrites[index][2][1] = "state" => NativeSelectedWrites[index][2][2] \in keys)
        BY ONLY <2>map, SMT DEF NativeSelectedWrites, fields, RHSOutputInput!MasterFields
    <2>. QED BY ONLY <1>selected, <2>map, <2>captures, <2>writes, SMT
        DEF NativeSelectedAction, fields, keys, RHSOutputInput!Rule!NativeCopyKnownRoles
<1>rawDomain. DOMAIN DecodedNativeAction.captures = 1..RHSOutputCount
    BY ONLY <1>selected, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF NativeSelectedAction, NativeSelectedCaptures, NativeSelectedCaptureTags
<1>. DEFINE directPlanColumns(index) ==
    LET tag == NativeSelectedCaptureTags[index]
        literal == tag = "literal"
        reference == NativeSelectedNodeReads[index][1]
    IN /\ NativeSelectedNodeCounts[index] = 1
       /\ NativeSelectedNodeKinds[index] = <<IF literal THEN "literal" ELSE "read">>
       /\ NativeSelectedNodeLiterals[index] = <<IF literal THEN NativeSelectedNodeLiterals[index][1] ELSE 0>>
       /\ NativeSelectedNodeReads[index] = <<IF literal THEN <<>> ELSE reference>>
       /\ (literal \/ reference = <<tag, reference[2]>>)
       /\ NativeSelectedNodeLeft[index] = <<0>>
       /\ NativeSelectedNodeRight[index] = <<0>>
<1>directColumns. \A index \in DOMAIN NativeSelectedCaptureTags :
    NativeSelectedCaptureTags[index] # "expression" => directPlanColumns(index)
    BY ONLY SMT DEF directPlanColumns, NativeSelectedCaptureTags, NativeSelectedNodeCounts, NativeSelectedNodeKinds,
        NativeSelectedNodeLiterals, NativeSelectedNodeReads, NativeSelectedNodeLeft, NativeSelectedNodeRight
<1>rawPlans. \A index \in 1..RHSOutputCount :
    RHSOutputInput!Rule!NativeAssignmentRhsPlan(DecodedNativeAction.captures[index]) =
        [NativeSelectedPlans[index] EXCEPT !.reads =
            IF NativeSelectedCaptureTags[index] = "literal" THEN <<NativeSelectedCaptures[index]>>
            ELSE NativeSelectedNodeReads[index]]
    <2>. TAKE index \in 1..RHSOutputCount
    <2>domain. index \in DOMAIN NativeSelectedCaptureTags
        BY ONLY <1>selected, <1>rawDomain, (index \in 1..RHSOutputCount), SMT
            DEF NativeSelectedAction, NativeSelectedCaptures
    <2>selected. DecodedNativeAction.captures[index] = NativeSelectedCaptures[index]
        BY ONLY <1>selected, SMT DEF NativeSelectedAction
    <2>expression. CASE NativeSelectedCaptureTags[index] = "expression"
        <3>capture. NativeSelectedCaptures[index] = <<"expression", NativeSelectedPlans[index]>>
            BY ONLY <2>domain, <2>expression, SMT DEF NativeSelectedCaptures
        <3>plan. RHSOutputInput!Rule!NativeAssignmentRhsPlan(DecodedNativeAction.captures[index]) = NativeSelectedPlans[index]
            BY ONLY <2>selected, <3>capture, SMT DEF RHSOutputInput!Rule!NativeAssignmentRhsPlan
        <3>reads. [NativeSelectedPlans[index] EXCEPT !.reads = NativeSelectedNodeReads[index]] = NativeSelectedPlans[index]
            BY ONLY <2>domain, SMT DEF NativeSelectedPlans
        <3>. QED BY ONLY <2>expression, <3>plan, <3>reads, SMT
    <2>direct. CASE NativeSelectedCaptureTags[index] # "expression"
        <3>. DEFINE literal == NativeSelectedCaptureTags[index] = "literal"
                    value == NativeSelectedNodeLiterals[index][1]
                    reference == NativeSelectedNodeReads[index][1]
                    capture == NativeSelectedCaptures[index]
                    plan(reads) == [count |-> 1, kinds |-> <<IF literal THEN "literal" ELSE "read">>,
                        literals |-> <<IF literal THEN value ELSE 0>>, reads |-> reads,
                        left |-> <<0>>, right |-> <<0>>]
        <3>columns. directPlanColumns(index)
            BY ONLY <1>directColumns, <2>domain, <2>direct, SMT
        <3>capture. capture = IF literal THEN <<"literal", value>> ELSE reference
            BY ONLY <2>domain, <2>direct, SMT DEF capture, literal, value, reference, NativeSelectedCaptures
        <3>packed. NativeSelectedPlans[index] = plan(NativeSelectedNodeReads[index])
            BY ONLY <2>domain, <3>columns, SMT DEF directPlanColumns, plan, literal, value, NativeSelectedPlans
        <3>decoded. RHSOutputInput!Rule!NativeAssignmentRhsPlan(DecodedNativeAction.captures[index]) = plan(<<capture>>)
            BY ONLY <2>selected, <2>direct, <3>capture, <3>columns, SMT
                DEF RHSOutputInput!Rule!NativeAssignmentRhsPlan, directPlanColumns, plan, literal, value, reference, capture
        <3>reads. (IF literal THEN <<capture>> ELSE NativeSelectedNodeReads[index]) = <<capture>>
            BY ONLY <3>capture, <3>columns, SMT DEF directPlanColumns, literal, reference
        <3>. QED BY ONLY <3>packed, <3>decoded, <3>reads, SMT DEF plan, literal, capture
    <2>. QED BY ONLY <2>expression, <2>direct, SMT
<1>readNames. RHSOutputInput!Rule!NativeAssignmentReadNamesAreKnown(DecodedNativeAction, NativeFormalNames)
    <2>columns. \A index \in 1..RHSOutputCount : \A node \in 1..NativeSelectedNodeCounts[index] :
        (NativeSelectedNodeKinds[index][node] = "read" /\ NativeSelectedNodeReads[index][node][1] = "state") =>
            NativeSelectedNodeReads[index][node][2] \in RHSOutputInput!MasterFields
        BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
            DEF NativeSelectedNodeCounts, NativeSelectedNodeKinds, NativeSelectedNodeReads, RHSOutputInput!MasterFields
    <2>literal. \A index \in 1..RHSOutputCount : NativeSelectedCaptureTags[index] = "literal" =>
        \A node \in 1..NativeSelectedNodeCounts[index] : NativeSelectedNodeKinds[index][node] # "read"
        BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
            DEF NativeSelectedCaptureTags, NativeSelectedNodeCounts, NativeSelectedNodeKinds
    <2>. QED BY ONLY <1>keys, <1>selected, <1>rawDomain, <1>rawPlans, <2>columns, <2>literal, SMT
        DEF NativeSelectedAction, NativeSelectedCaptures, NativeSelectedPlans, NativeFormalNames,
            RHSOutputInput!Rule!NativeAssignmentReadNamesAreKnown
<1>captureDomain.
    /\ DOMAIN NormalizedNativeAction.captures = DOMAIN DecodedNativeAction.captures
    /\ DOMAIN RHSOutputPlans = DOMAIN RHSOutputRows
    /\ DOMAIN RHSOutputRows = 1..RHSOutputCount
    BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF NormalizedNativeAction, RHSOutputInput!Rule!NativeAssignmentRekey,
            RHSOutputInput!Rule!SupportedAssignmentList, RHSOutputCount
<1>sameCaptures. \A index \in 1..RHSOutputCount :
    NormalizedNativeAction.captures[index] = RHSOutputPlans[index]
    <2>. TAKE index \in 1..RHSOutputCount
    <2>. DEFINE raw == RHSOutputInput!Rule!NativeAssignmentRhsPlan(DecodedNativeAction.captures[index])
                rendered == RHSOutputPlans[index]
                physical == NormalizedNativeAction.captures[index]
    <2>counts. NativeSelectedNodeCounts = RHSOutputNodeCounts
        BY ONLY SMT DEF NativeSelectedNodeCounts, RHSOutputNodeCounts
    <2>kinds. NativeSelectedNodeKinds = RHSOutputNodeKinds
        BY ONLY SMT DEF NativeSelectedNodeKinds, RHSOutputNodeKinds
    <2>literals. NativeSelectedNodeLiterals = RHSOutputNodeLiterals
        BY ONLY SMT DEF NativeSelectedNodeLiterals, RHSOutputNodeLiterals
    <2>readColumns. NativeSelectedNodeReads = RHSOutputNodeReads
        BY ONLY SMT DEF NativeSelectedNodeReads, RHSOutputNodeReads
    <2>children. /\ NativeSelectedNodeLeft = RHSOutputNodeLeft /\ NativeSelectedNodeRight = RHSOutputNodeRight
        BY ONLY SMT DEF NativeSelectedNodeLeft, NativeSelectedNodeRight, RHSOutputNodeLeft, RHSOutputNodeRight
    <2>same. NativeSelectedPlans[index] = rendered
        BY ONLY <1>rawDomain, <1>captureDomain, <1>selected, (index \in 1..RHSOutputCount),
            <2>counts, <2>kinds, <2>literals, <2>readColumns, <2>children, SMT
            DEF NativeSelectedAction, NativeSelectedCaptures, NativeSelectedPlans, rendered, RHSOutputPlans
    <2>record. raw = [rendered EXCEPT !.reads =
        IF NativeSelectedCaptureTags[index] = "literal" THEN <<NativeSelectedCaptures[index]>> ELSE rendered.reads]
        BY ONLY <1>rawDomain, <1>selected, <1>rawPlans, <2>same, (index \in 1..RHSOutputCount), SMT
            DEF raw, NativeSelectedAction, NativeSelectedCaptures, NativeSelectedPlans
    <2>reads.
        /\ rendered.reads = [node \in 1..rendered.count |-> rendered.reads[node]]
        /\ \A node \in 1..rendered.count :
              /\ (raw.kinds[node] = "read" => raw.reads[node] = rendered.reads[node])
              /\ (raw.kinds[node] # "read" => rendered.reads[node] = <<>>)
        BY ONLY <2>record, <1>captureDomain, (index \in 1..RHSOutputCount),
            RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
            DEF rendered, RHSOutputPlans, RHSOutputNodeCounts, RHSOutputNodeKinds, RHSOutputNodeReads, NativeSelectedCaptureTags
    <2>known. \A node \in 1..raw.count :
        (raw.kinds[node] = "read" /\ raw.reads[node][1] = "state") => raw.reads[node][2] \in RHSOutputInput!MasterFields
        BY ONLY <1>readNames, <1>keys, <1>rawDomain, (index \in 1..RHSOutputCount), SMT
            DEF raw, NativeFormalNames, RHSOutputInput!Rule!NativeAssignmentReadNamesAreKnown
    <2>. DEFINE references == [node \in 1..raw.count |->
        IF raw.kinds[node] = "read" THEN
            IF raw.reads[node][1] = "state" THEN <<"state",
                RHSOutputInput!Rule!NativeCopyKey(RHSOutputInput!MasterFields, NativeFormalNames, "pc", raw.reads[node][2])>>
            ELSE raw.reads[node]
        ELSE <<>>]
    <2>update. physical = [raw EXCEPT !.reads = references]
        BY ONLY <1>rawDomain, (index \in 1..RHSOutputCount), SMT
            DEF physical, raw, references, NormalizedNativeAction, RHSOutputInput!Rule!NativeAssignmentRekey
    <2>. DEFINE withReads(refs) ==
        [count |-> rendered.count, kinds |-> rendered.kinds, literals |-> rendered.literals,
         reads |-> refs, left |-> rendered.left, right |-> rendered.right]
    <2>renderedDomain. index \in DOMAIN RHSOutputPlans
        BY ONLY (index \in 1..RHSOutputCount), <1>captureDomain, SMT
    <2>renderedRecord. rendered = withReads(rendered.reads)
        BY ONLY <2>renderedDomain, SMT DEF withReads, rendered, RHSOutputPlans
    <2>rawRecord. raw = withReads(raw.reads)
        BY ONLY <2>renderedRecord, <2>record, SMT DEF withReads
    <2>stateReads. \A node \in 1..rendered.count :
        (rendered.kinds[node] = "read" /\ rendered.reads[node][1] = "state") =>
            rendered.reads[node] = <<"state", rendered.reads[node][2]>>
        BY ONLY <2>renderedDomain, (index \in 1..RHSOutputCount), RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
            DEF rendered, RHSOutputPlans, RHSOutputNodeCounts, RHSOutputNodeKinds, RHSOutputNodeReads
    <2>normalized. references = rendered.reads
        <3>count. raw.count = rendered.count
            BY ONLY <2>rawRecord, SMT DEF withReads
        <3>points. \A node \in 1..rendered.count : references[node] = rendered.reads[node]
            <4>. TAKE node \in 1..rendered.count
            <4>state. (raw.kinds[node] = "read" /\ raw.reads[node][1] = "state") =>
                raw.reads[node] = <<"state", raw.reads[node][2]>>
                BY ONLY <2>stateReads, <2>rawRecord, <2>reads, (node \in 1..rendered.count), SMT DEF withReads
            <4>. QED BY ONLY <4>state, <3>count, <1>names, <2>known, <2>reads, (node \in 1..rendered.count),
                SMT DEF references
        <3>. QED BY ONLY <3>count, <3>points, <2>reads, SMT DEF references
    <2>restored. [raw EXCEPT !.reads = rendered.reads] = rendered
        BY ONLY <2>renderedRecord, <2>rawRecord, SMT DEF withReads
    <2>. QED BY ONLY <2>restored, <2>update, <2>normalized, SMT DEF physical, rendered

<1>operands. \A index \in 1..RHSOutputCount :
    RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters(RHSOutputRows, index, NormalizedNativeAction.captures[index])
    BY ONLY <1>sameCaptures, <1>captureDomain, ActualRenderedRightHandSidesNameTheAuthoredWriters, SMT
<1>writeDomain.
    /\ Len(DecodedNativeAction.writes) \in Nat
    /\ DOMAIN DecodedNativeAction.writes = 1..Len(DecodedNativeAction.writes)
    BY ONLY <1>selected, SMT DEF NativeSelectedAction, NativeSelectedWrites
<1>writeCount.
    /\ Len(NormalizedNativeAction.writes) = Len(DecodedNativeAction.writes)
    /\ DOMAIN NormalizedNativeAction.writes = DOMAIN DecodedNativeAction.writes
    <2>. DEFINE writes == NormalizedNativeAction.writes
                values == {writes[index] : index \in DOMAIN writes}
    <2>domain. DOMAIN writes = DOMAIN DecodedNativeAction.writes
        BY ONLY SMT DEF writes, NormalizedNativeAction, RHSOutputInput!Rule!NativeAssignmentRekey,
            RHSOutputInput!Rule!NativeCopyRekey
    <2>function. writes \in [1..Len(DecodedNativeAction.writes) -> values]
        BY ONLY <2>domain, <1>writeDomain, SMT DEF writes, values, NormalizedNativeAction,
            RHSOutputInput!Rule!NativeAssignmentRekey, RHSOutputInput!Rule!NativeCopyRekey
    <2>sequence. writes \in Seq(values)
        BY ONLY <2>function, <1>writeDomain, RHSOutputInput!Rule!SeqDef, SMT
    <2>. QED BY ONLY <2>domain, <2>sequence, <1>writeDomain, RHSOutputInput!Rule!LenProperties, SMT DEF writes
<1>updates.
    /\ NormalizedNativeAction.guards = NativeSelectedGuards
    /\ NormalizedNativeAction.writes = [index \in DOMAIN NativeSelectedWrites |->
           LET write == NativeSelectedWrites[index]
           IN <<RHSOutputInput!Rule!NativeCopyKey(RHSOutputInput!MasterFields, NativeFormalNames, "pc", write[1]),
                IF write[2][1] = "state" THEN <<"state",
                    RHSOutputInput!Rule!NativeCopyKey(RHSOutputInput!MasterFields, NativeFormalNames, "pc", write[2][2])>>
                ELSE write[2]>>]
    BY ONLY <1>selected, SMT DEF NormalizedNativeAction, NativeSelectedAction,
        RHSOutputInput!Rule!NativeAssignmentRekey, RHSOutputInput!Rule!NativeCopyRekey
<1>frame.
    /\ RHSOutputInput!MasterFields \subseteq STRING
    /\ RHSOutputInput!Rule!NativeCopyControlSlot \notin RHSOutputInput!MasterFields
    /\ NormalizedNativeAction.guards = <<RHSOutputEntry>>
    /\ \A key \in RHSOutputInput!Rule!NativeCopyFields(RHSOutputInput!MasterFields) :
           \E index \in DOMAIN NormalizedNativeAction.writes : NormalizedNativeAction.writes[index][1] = key
    BY ONLY <1>updates, <1>keys, <1>names, SMT
        DEF NativeSelectedGuards, NativeSelectedWrites, RHSOutputKeys, RHSOutputEntry,
            RHSOutputInput!Rule!NativeCopyFields, RHSOutputInput!Rule!NativeCopyControlSlot
<1>writeRefs. \A index \in DOMAIN NormalizedNativeAction.writes :
    LET key == NormalizedNativeAction.writes[index][1]
    IN /\ key \in RHSOutputInput!Rule!NativeCopyFields(RHSOutputInput!MasterFields)
       /\ NormalizedNativeAction.writes[index][2] =
            IF key = RHSOutputInput!Rule!NativeCopyControlSlot THEN <<"control", RHSOutputExit>> ELSE RHSOutputWriteRoutes[key]
    BY ONLY <1>updates, <1>keys, <1>names, SMT
        DEF NativeSelectedWrites, RHSOutputKeys, RHSOutputExit, RHSOutputWriteRoutes,
            RHSOutputInput!Rule!NativeCopyFields, RHSOutputInput!Rule!NativeCopyControlSlot
<1>writes.
    RHSOutputInput!Rule!NativeAssignmentWritesNameLastTargets(RHSOutputRows, NormalizedNativeAction, RHSOutputEntry, RHSOutputExit)
    BY ONLY <1>keys, <1>writeDomain, <1>writeCount, <1>frame, <1>writeRefs, ActualRenderedWriteRoutesNameTheAuthoredWriters, SMT
        DEF RHSOutputInput!Rule!NativeAssignmentWritesNameLastTargets, RHSOutputInput!Rule!NativeCopyFields, RHSOutputCount
<1>. QED BY ONLY <1>dispatch, <1>slots, <1>readNames, <1>rawDomain, <1>captureDomain, <1>operands, <1>writes, SMT
    DEF RHSOutputInput!Rule!NativeAssignmentsNameTheirOperandsAndWrites, NormalizedNativeAction, RHSOutputCount

THEOREM ActualNativeAndTLAInitialObservationsUseTheCertifiedAssignmentHistory ==
    ASSUME Init
    PROVE \E history :
        /\ RHSOutputSourceHistory(history)
        /\ RHSOutputGeneratedHistory(history)
        /\ RHSOutputHistoryObservation(history)
        /\ ActualNativeAssignmentCaptureHistory(history)
        /\ RHSOutputInput!Rule!NativeAssignmentCheckedCallback(ActualNativeFailure.before,
               RHSOutputActionLabel, NativeActionOrdinal, RHSOutputSelected,
               RHSOutputInput!Rule!NativeAssignmentPrefix(history[RHSOutputCount])) = {ActualNativeFailure}
        /\ RHSOutputSelectedSubExpressions = {<<ActualNativeFailure.site, 3>>}
        /\ RHSOutputActualFailures = {ActualNativeProjection}
        /\ RHSOutputActualFailures =
            {[site |-> 2, target |-> "count", payload |-> <<"integerOverflow", "addition", <<RHSOutputMax, 1>>>>,
                  completed |-> <<RHSOutputMax>>, before |-> [count |-> RHSOutputMax]]}
        /\ ~ENABLED Next
        /\ ~RHSOutputSelectedEvaluationCheck
PROOF
<1>entry.
    /\ RHSOutputStateType
    /\ RHSOutputSelected
    /\ ActualNativeFailure.label = RHSOutputActionLabel
    /\ ActualNativeFailure.actionOrdinal = 0
    /\ NativeActionDispatchLabels[ActualNativeFailure.actionOrdinal + 1] = "advance"
    /\ ActualNativeFailure.before["pc"] = pc
    /\ [key \in RHSOutputKeys |-> ActualNativeFailure.before[key]] = RHSOutputBefore
    BY Init, SMT DEF Init, RHSOutputStateType, RHSOutputSelected, RHSOutputEntry, RHSOutputActionLabel,
        RHSOutputKeys, RHSOutputBefore, ActualNativeFailure, NativeAssignmentFailure, NativeActionDispatchLabels,
        RHSOutputMin, RHSOutputMax
<1>actual. PICK history :
    RHSOutputSourceHistory(history) /\ RHSOutputGeneratedHistory(history) /\ RHSOutputHistoryObservation(history)
    BY <1>entry, ActualTLAActionHasACertifiedAssignmentHistory
<1>type. RHSOutputBefore \in RHSOutputInput!Rule!AssignmentBindings
    BY ONLY <1>entry, SMT
        DEF RHSOutputStateType, RHSOutputKeys, RHSOutputMin, RHSOutputMax, RHSOutputInput!MasterFields,
            RHSOutputInput!Rule!AssignmentBindings, RHSOutputInput!Rule!AssignmentIntValues
<1>source.
    /\ RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
    /\ RHSOutputInput!Rule!AssignmentListHistory(FALSE, RHSOutputBefore, RHSOutputRows, history)
    BY ONLY <1>actual, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory DEF RHSOutputSourceHistory
<1>native. ActualNativeAssignmentCaptureHistory(history)
    BY ONLY <1>type, <1>source, ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles,
        RHSOutputInput!Rule!PhysicalNativeCapturesUseTheCertifiedAssignmentHistory, SMT
        DEF ActualNativeAssignmentCaptureHistory, NormalizedNativeAction, RHSOutputCount
<1>event. /\ RHSOutputSelectedSubExpressions = {<<ActualNativeFailure.site, 3>>}
           /\ RHSOutputActualFailures = {ActualNativeProjection}
    BY Init, SMT DEF Init, RHSOutputSelectedSubExpressions, RHSOutputActualFailures, RHSOutputFailureProbeSites,
        RHSOutputProbePositions, RHSOutputGuards, RHSOutputPayloads, ActualNativeProjection, ActualNativeFailure,
        NativeAssignmentFailure, __SwiftTLAOverflowFailure0, __SwiftTLAOverflowFailure0_1, __SwiftTLAOverflowBefore0_1,
        __SwiftTLAOverflowOperation0_1, __SwiftTLAOverflowOperands0_1
<1>failure. LET final == history[RHSOutputCount]
    IN /\ final.failure # <<>>
       /\ final.failure.site = ActualNativeFailure.site
       /\ final.failure.payload = ActualNativeFailure.payload
       /\ final.completed = ActualNativeFailure.completed
    BY <1>entry, <1>actual, <1>event, SMT DEF RHSOutputHistoryObservation, RHSOutputHistoryFailures,
        ActualNativeProjection, ActualNativeFailure, NativeAssignmentFailure, RHSOutputFailureEvent
<1>callback.
    RHSOutputInput!Rule!NativeAssignmentCheckedCallback(ActualNativeFailure.before,
        RHSOutputActionLabel, NativeActionOrdinal, RHSOutputSelected,
        RHSOutputInput!Rule!NativeAssignmentPrefix(history[RHSOutputCount])) = {ActualNativeFailure}
    BY <1>entry, <1>failure, SMT DEF RHSOutputInput!Rule!NativeAssignmentCheckedCallback,
        RHSOutputInput!Rule!NativeAssignmentPrefix, NativeActionOrdinal, ActualNativeFailure, NativeAssignmentFailure
<1>route. RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, 1, "count", <<"capture", 1>>)
    BY ONLY SMT DEF RHSOutputRows, RHSOutputInput!MasterRows, RHSOutputInput!MasterNodeCounts, RHSOutputInput!MasterTargets,
        RHSOutputInput!Rule!CopyReceiptNamesWriter, RHSOutputInput!Rule!CopyReceiptOrdinal,
        RHSOutputInput!Rule!LastDirectCopy, RHSOutputInput!Rule!DirectCopyReference
<1>writer. RHSOutputInput!Rule!DirectCopyRoutes(RHSOutputKeys, RHSOutputRows)[1]["count"] = <<"capture", 1>>
    BY <1>route, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
       RHSOutputInput!Rule!NamedAssignmentReadRouteIsTheScheduledRoute, SMT
       DEF RHSOutputKeys, RHSOutputInput!MasterFields, RHSOutputInput!Rule!SupportedAssignmentList
<1>projection. ActualNativeProjection =
    [site |-> 2, target |-> "count", payload |-> <<"integerOverflow", "addition", <<RHSOutputMax, 1>>>>,
     completed |-> <<RHSOutputMax>>, before |-> [count |-> RHSOutputMax]]
    BY <1>writer, SMT DEF ActualNativeProjection, ActualNativeFailure, NativeAssignmentFailure, RHSOutputFailureEvent,
        RHSOutputKeys, RHSOutputRows, RHSOutputMin, RHSOutputMax, RHSOutputInput!MasterFields, RHSOutputInput!MasterRows,
        RHSOutputInput!MasterNodeCounts, RHSOutputInput!MasterTargets,
        RHSOutputInput!Rule!CompletedAssignmentBindings, RHSOutputInput!Rule!CopyMaterializedState, RHSOutputInput!Rule!CopyReferenceValue
<1>exact. RHSOutputActualFailures =
    {[site |-> 2, target |-> "count", payload |-> <<"integerOverflow", "addition", <<RHSOutputMax, 1>>>>,
      completed |-> <<RHSOutputMax>>, before |-> [count |-> RHSOutputMax]]}
    BY <1>event, <1>projection, SMT
<1>blocked. ~ENABLED Next
    BY Init, ExpandENABLED, SMT DEF Init, Next, advance, Terminating
<1>rejected. ~RHSOutputSelectedEvaluationCheck
    BY <1>entry, <1>event, ConfiguredEvaluationCheckMatchesTheCompleteSelectedRHSFailure, SMT
<1>. WITNESS history
<1>. QED BY <1>actual, <1>native, <1>callback, <1>event, <1>exact, <1>blocked, <1>rejected

THEOREM ActualInitialEventRecordsTheExactOverflowAndPrecedingBindings ==
    ASSUME Init
    PROVE /\ RHSOutputActualFailures =
                {[site |-> 2, target |-> "count", payload |-> <<"integerOverflow", "addition", <<RHSOutputMax, 1>>>>,
                  completed |-> <<RHSOutputMax>>, before |-> [count |-> RHSOutputMax]]}
          /\ RHSOutputActualFailures = {ActualNativeProjection}
          /\ RHSOutputSelectedSubExpressions = {<<2, 3>>}
          /\ ~ENABLED Next
          /\ ~RHSOutputSelectedEvaluationCheck
    BY Init, ActualNativeAndTLAInitialObservationsUseTheCertifiedAssignmentHistory, SMT
       DEF ActualNativeFailure, NativeAssignmentFailure

LOCAL NativeCaptureObservation(visited) ==
    RHSOutputInput!Rule!NativeAssignmentCaptureHistory(RHSOutputBefore, NormalizedNativeAction, RHSOutputCount, visited)

LOCAL NativeCompletedAdvance(completed) ==
    RHSOutputInput!Rule!NativeCopyVisits(
        RHSOutputInput!Rule!NativeAssignmentMaterializationPlan(NormalizedNativeAction, completed),
        RHSOutputInput!MasterFields, RHSOutputBefore, RHSOutputAfter, pc, pc')

ActualNativeAssignmentAdvance ==
    /\ RHSOutputAfter \in RHSOutputInput!Rule!AssignmentBindings
    /\ \E visited :
        /\ NativeCaptureObservation(visited)
        /\ visited[RHSOutputCount].failure = <<>>
        /\ NativeCompletedAdvance(visited[RHSOutputCount].completed)

LOCAL NativeAssignmentBefore ==
    [key \in RHSOutputKeys \cup {"pc"} |-> IF key = "pc" THEN pc ELSE RHSOutputBefore[key]]

LOCAL NativeAssignmentSelected ==
    \A index \in DOMAIN NormalizedNativeAction.guards : pc = NormalizedNativeAction.guards[index]

LOCAL NativeAssignmentRawFailures ==
    RHSOutputInput!Rule!NativeAssignmentCheckedCallback(NativeAssignmentBefore, RHSOutputActionLabel,
        NativeActionOrdinal, NativeAssignmentSelected,
        (CHOOSE visited : NativeCaptureObservation(visited))[RHSOutputCount])

LOCAL NativeAssignmentFailureEvent(event) ==
    [site |-> event.site, target |-> RHSOutputRows[event.site].target, payload |-> event.payload,
     completed |-> event.completed,
     before |-> RHSOutputInput!Rule!CompletedAssignmentBindings(
         [key \in RHSOutputInput!MasterFields |-> event.before[NativeFormalNames[key]]], RHSOutputRows, event.completed)]

ActualNativeAssignmentFailures ==
    {NativeAssignmentFailureEvent(event) : event \in NativeAssignmentRawFailures}

THEOREM ActualNativeAndTLAAdvanceAgreeOnTypedInput ==
    ASSUME RHSOutputStateType
    PROVE /\ (ActualNativeAssignmentAdvance <=> advance)
          /\ ActualNativeAssignmentFailures = RHSOutputActualFailures
PROOF
<1>actual. PICK history : RHSOutputSourceHistory(history) /\ RHSOutputHistoryObservation(history)
    BY ONLY RHSOutputStateType, ActualTLAActionHasACertifiedAssignmentHistory
<1>. DEFINE final == history[RHSOutputCount]
<1>type. RHSOutputBefore \in RHSOutputInput!Rule!AssignmentBindings
    BY ONLY RHSOutputStateType, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF RHSOutputStateType, RHSOutputMin, RHSOutputMax,
            RHSOutputInput!Rule!AssignmentBindings, RHSOutputInput!Rule!AssignmentIntValues
<1>source.
    /\ RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
    /\ RHSOutputInput!Rule!AssignmentListHistory(FALSE, RHSOutputBefore, RHSOutputRows, history)
    BY ONLY <1>actual, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory DEF RHSOutputSourceHistory
<1>finalIndex. RHSOutputCount \in 0..Len(RHSOutputRows)
    BY ONLY <1>source, SMT DEF RHSOutputCount, RHSOutputInput!Rule!SupportedAssignmentList
<1>typedFinal. final.bindings \in RHSOutputInput!Rule!AssignmentBindings
    BY ONLY <1>source, <1>finalIndex, SMT
        DEF final, RHSOutputCount, RHSOutputInput!Rule!AssignmentListHistory, RHSOutputInput!Rule!AssignmentPrefixStates
<1>matching. \A visited : NativeCaptureObservation(visited) =>
    visited[RHSOutputCount] = RHSOutputInput!Rule!NativeAssignmentPrefix(final)
    <2>. SUFFICES ASSUME NEW visited, NativeCaptureObservation(visited)
                 PROVE visited[RHSOutputCount] = RHSOutputInput!Rule!NativeAssignmentPrefix(final)
        OBVIOUS
    <2>. QED BY ONLY <1>type, <1>source, <1>finalIndex, NativeCaptureObservation(visited),
        ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles,
        RHSOutputInput!Rule!PhysicalNativePrefixAgreesWithTheCertifiedAssignments, SMT
        DEF NativeCaptureObservation, NormalizedNativeAction, RHSOutputCount, final
<1>native. ActualNativeAssignmentCaptureHistory(history)
    BY ONLY <1>type, <1>source, ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles,
        RHSOutputInput!Rule!PhysicalNativeCapturesUseTheCertifiedAssignmentHistory, SMT
        DEF ActualNativeAssignmentCaptureHistory, NormalizedNativeAction, RHSOutputCount
<1>exists. \E visited : NativeCaptureObservation(visited)
    /\ visited[RHSOutputCount] = RHSOutputInput!Rule!NativeAssignmentPrefix(final)
    <2>. WITNESS RHSOutputInput!Rule!NativeAssignmentProjectedHistory(history, RHSOutputCount)
    <2>. QED BY ONLY <1>native, <1>matching, SMT
        DEF NativeCaptureObservation, ActualNativeAssignmentCaptureHistory
<1>outcome. ActualNativeAssignmentAdvance <=>
    /\ RHSOutputAfter \in RHSOutputInput!Rule!AssignmentBindings
    /\ final.failure = <<>>
    /\ NativeCompletedAdvance(final.completed)
    BY ONLY <1>matching, <1>exists, SMT
        DEF ActualNativeAssignmentAdvance, RHSOutputInput!Rule!NativeAssignmentPrefix
<1>writes. ASSUME final.failure = <<>>, RHSOutputAfter \in RHSOutputInput!Rule!AssignmentBindings
    PROVE NativeCompletedAdvance(final.completed) <=>
        (RHSOutputSelected /\ pc' = RHSOutputExit /\ RHSOutputAfter = final.bindings)
    BY ONLY <1>type, <1>source, ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles,
        (final.failure = <<>>), (RHSOutputAfter \in RHSOutputInput!Rule!AssignmentBindings),
        RHSOutputInput!Rule!SuccessfulNativeAssignmentsUseTheCompleteLastWriteFrame, SMT
        DEF NativeCompletedAdvance, NormalizedNativeAction, RHSOutputSelected, final, RHSOutputCount
<1>advance. ActualNativeAssignmentAdvance <=> advance
    BY ONLY <1>actual, <1>typedFinal, <1>outcome, <1>writes, SMT
        DEF RHSOutputHistoryObservation, RHSOutputHistoryAdvance, final
<1>guard. NormalizedNativeAction.guards = <<RHSOutputEntry>>
    BY ONLY ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles, SMT
        DEF NormalizedNativeAction, RHSOutputInput!Rule!NativeAssignmentsNameTheirOperandsAndWrites,
            RHSOutputInput!Rule!NativeAssignmentWritesNameLastTargets
<1>selected. NativeAssignmentSelected <=> RHSOutputSelected
    BY ONLY <1>guard, SMT DEF NativeAssignmentSelected, RHSOutputSelected
<1>before. [key \in RHSOutputInput!MasterFields |-> NativeAssignmentBefore[NativeFormalNames[key]]] = RHSOutputBefore
    BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF NativeAssignmentBefore, NativeFormalNames, RHSOutputBefore, RHSOutputKeys, RHSOutputInput!MasterFields
<1>prefix. final.failure # <<>> =>
    final.failure.before = RHSOutputInput!Rule!CompletedAssignmentBindings(RHSOutputBefore, RHSOutputRows, final.completed)
    <2>meaning. RHSOutputInput!Rule!AssignmentPrefixMeaning(RHSOutputBefore, RHSOutputRows, history, RHSOutputCount)
        BY ONLY <1>type, <1>source, <1>finalIndex, RHSOutputInput!Rule!OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix,
            SMT DEF RHSOutputCount
    <2>. QED BY ONLY <2>meaning, SMT DEF RHSOutputInput!Rule!AssignmentPrefixMeaning, final
<1>last. (CHOOSE visited : NativeCaptureObservation(visited))[RHSOutputCount] =
    RHSOutputInput!Rule!NativeAssignmentPrefix(final)
    BY ONLY <1>exists, <1>matching, SMT
<1>raw. NativeAssignmentRawFailures =
    IF RHSOutputSelected /\ final.failure # <<>> THEN
        {[label |-> RHSOutputActionLabel, actionOrdinal |-> NativeActionOrdinal, site |-> final.failure.site,
          completed |-> final.completed, payload |-> final.failure.payload, before |-> NativeAssignmentBefore]}
    ELSE {}
    BY ONLY <1>last, <1>selected, SMT
        DEF NativeAssignmentRawFailures, RHSOutputInput!Rule!NativeAssignmentCheckedCallback, RHSOutputInput!Rule!NativeAssignmentPrefix
<1>failures. ActualNativeAssignmentFailures = RHSOutputHistoryFailures(history)
    <2>inactive. CASE ~RHSOutputSelected \/ final.failure = <<>>
        BY ONLY <1>raw, <2>inactive, SMT DEF ActualNativeAssignmentFailures, RHSOutputHistoryFailures, final
    <2>reached. CASE RHSOutputSelected /\ final.failure # <<>>
        BY ONLY <1>raw, <1>prefix, <1>before, <2>reached, SMT
            DEF ActualNativeAssignmentFailures, NativeAssignmentFailureEvent, RHSOutputHistoryFailures, final
    <2>. QED BY ONLY <2>inactive, <2>reached, SMT
<1>. QED BY ONLY <1>advance, <1>actual, <1>failures DEF RHSOutputHistoryObservation

====
