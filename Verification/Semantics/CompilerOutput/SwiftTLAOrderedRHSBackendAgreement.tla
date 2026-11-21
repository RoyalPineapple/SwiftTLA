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
<1>dispatch.
    RHSOutputInput!Rule!NativeAssignmentDispatchMatches(NativeActionRows, NativeActionDispatchLabels,
        NativeActionOrdinal, RHSOutputActionLabel, "advance")
    BY SMT DEF RHSOutputInput!Rule!NativeAssignmentDispatchMatches, NativeActionOrdinal,
        ActualNativeFailure, NativeAssignmentFailure, NativeActionRows, NativeActionDispatchLabels, RHSOutputActionLabel
<1>decode.
    /\ RHSOutputInput!Rule!NativeCopyKnownRoles(DecodedNativeAction, RHSOutputKeys, NativeFormalNames, "pc")
    /\ RHSOutputInput!Rule!NativeAssignmentReadNamesAreKnown(DecodedNativeAction, NativeFormalNames)
    BY SMT DEF RHSOutputInput!Rule!NativeCopyKnownRoles, RHSOutputInput!Rule!NativeCopyPhysicalKeys,
        RHSOutputInput!Rule!NativeAssignmentReadNamesAreKnown, RHSOutputInput!Rule!NativeAssignmentRhsPlan,
        DecodedNativeAction, NativeActionOrdinal, ActualNativeFailure, NativeAssignmentFailure,
        NativeActionRows, NativeFormalNames, RHSOutputInput!MasterFields, RHSOutputKeys
<1>names.
    \A key \in RHSOutputKeys : RHSOutputInput!Rule!NativeCopyKey(RHSOutputKeys, NativeFormalNames, "pc", key) = key
    BY SMT DEF RHSOutputInput!Rule!NativeCopyKey, NativeFormalNames, RHSOutputKeys
<1>operands.
    /\ DOMAIN NormalizedNativeAction.captures = 1..RHSOutputCount
    /\ \A index \in 1..RHSOutputCount :
          RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters(RHSOutputRows, index, NormalizedNativeAction.captures[index])
    BY <1>names, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters, RHSOutputInput!Rule!PhysicalAssignmentOperandsMatch,
            RHSOutputInput!Rule!CopyReceiptNamesWriter, RHSOutputInput!Rule!CopyReceiptOrdinal,
            RHSOutputInput!Rule!LastDirectCopy, RHSOutputInput!Rule!DirectCopyReference,
            RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan,
            RHSOutputInput!Rule!NativeAssignmentRekey, RHSOutputInput!Rule!NativeAssignmentRhsPlan, NormalizedNativeAction,
            DecodedNativeAction, NativeActionOrdinal, ActualNativeFailure, NativeAssignmentFailure, NativeActionRows,
            RHSOutputRows, RHSOutputCount, RHSOutputInput!MasterFields, RHSOutputKeys
<1>writes.
    RHSOutputInput!Rule!NativeAssignmentWritesNameLastTargets(RHSOutputRows, NormalizedNativeAction, RHSOutputEntry, RHSOutputExit)
    BY <1>names, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF RHSOutputInput!Rule!NativeAssignmentWritesNameLastTargets, RHSOutputInput!Rule!NativeCopyFields,
            RHSOutputInput!Rule!NativeCopyRekey, RHSOutputInput!Rule!NativeCopyKey, RHSOutputInput!Rule!NativeCopyControlSlot,
            RHSOutputInput!Rule!CopyReceiptNamesWriter, RHSOutputInput!Rule!CopyReceiptOrdinal,
            RHSOutputInput!Rule!LastDirectCopy, RHSOutputInput!Rule!DirectCopyReference,
            RHSOutputInput!Rule!NativeAssignmentRekey, NormalizedNativeAction, DecodedNativeAction, NativeActionOrdinal,
            ActualNativeFailure, NativeAssignmentFailure, NativeActionRows, RHSOutputRows, RHSOutputCount, RHSOutputKeys,
            RHSOutputInput!MasterFields, RHSOutputEntry, RHSOutputExit
<1>. QED BY ONLY <1>dispatch, <1>decode, <1>operands, <1>writes
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
    BY SMT DEF RHSOutputRows, RHSOutputInput!MasterRows, RHSOutputInput!Rule!CopyReceiptNamesWriter, RHSOutputInput!Rule!CopyReceiptOrdinal,
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

====
