---- MODULE SwiftTLAOrderedRHSBackendAgreement ----
EXTENDS SwiftTLAOrderedRHSConfiguredProof, SwiftTLANativeAssignmentActions, TLAPS

\* The native packet records this failure from the real visitor of the actual initial machine.
LOCAL ActualNativeFailure == NativeAssignmentFailure
ActualNativeProjection ==
    RHSOutputFailureEvent(ActualNativeFailure.site, ActualNativeFailure.payload[2],
        ActualNativeFailure.payload[3], ActualNativeFailure.completed)

LOCAL SharedAssignmentRule == INSTANCE NativeIntAssignmentListRule
    WITH Keys <- RHSOutputKeys, SwiftIntMin <- RHSOutputMin, SwiftIntMax <- RHSOutputMax,
         Vars <- {}, Values <- {}, ActionLabels <- {}, FailureValues <- {}, NoFailure <- <<>>

LOCAL Source == INSTANCE SwiftTLAArithmeticAssignmentSource

LOCAL NativeFormalNames == [key \in RHSOutputKeys |-> key]
LOCAL NativeActionOrdinal == ActualNativeFailure.actionOrdinal
LOCAL DecodedNativeAction == NativeActionRows[NativeActionOrdinal + 1][2]
LOCAL NormalizedNativeAction == SharedAssignmentRule!NativeAssignmentRekey(DecodedNativeAction, NativeFormalNames, "pc")

ActualNativeAssignmentCaptureHistory(history) ==
    SharedAssignmentRule!NativeAssignmentCaptureHistory(RHSOutputBefore, NormalizedNativeAction, RHSOutputCount,
        SharedAssignmentRule!NativeAssignmentProjectedHistory(history, RHSOutputCount))

THEOREM ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles ==
    /\ SharedAssignmentRule!NativeAssignmentDispatchMatches(NativeActionRows, NativeActionDispatchLabels,
           NativeActionOrdinal, RHSOutputActionLabel, "advance")
    /\ SharedAssignmentRule!NativeAssignmentsNameTheirOperandsAndWrites(RHSOutputRows, DecodedNativeAction,
           NativeFormalNames, "pc", RHSOutputEntry, RHSOutputExit)
PROOF
<1>dispatch.
    SharedAssignmentRule!NativeAssignmentDispatchMatches(NativeActionRows, NativeActionDispatchLabels,
        NativeActionOrdinal, RHSOutputActionLabel, "advance")
    BY SMT DEF SharedAssignmentRule!NativeAssignmentDispatchMatches, NativeActionOrdinal,
        ActualNativeFailure, NativeAssignmentFailure, NativeActionRows, NativeActionDispatchLabels, RHSOutputActionLabel
<1>decode.
    /\ SharedAssignmentRule!NativeCopyKnownRoles(DecodedNativeAction, RHSOutputKeys, NativeFormalNames, "pc")
    /\ SharedAssignmentRule!NativeAssignmentReadNamesAreKnown(DecodedNativeAction, NativeFormalNames)
    BY SMT DEF SharedAssignmentRule!NativeCopyKnownRoles, SharedAssignmentRule!NativeCopyPhysicalKeys,
        SharedAssignmentRule!NativeAssignmentReadNamesAreKnown, SharedAssignmentRule!NativeAssignmentRhsPlan,
        DecodedNativeAction, NativeActionOrdinal, ActualNativeFailure, NativeAssignmentFailure,
        NativeActionRows, NativeFormalNames, RHSOutputKeys
<1>names.
    \A key \in RHSOutputKeys : SharedAssignmentRule!NativeCopyKey(RHSOutputKeys, NativeFormalNames, "pc", key) = key
    BY SMT DEF SharedAssignmentRule!NativeCopyKey, NativeFormalNames, RHSOutputKeys
<1>operands.
    /\ DOMAIN NormalizedNativeAction.captures = 1..RHSOutputCount
    /\ \A index \in 1..RHSOutputCount :
          SharedAssignmentRule!PhysicalAssignmentReadsNameWriters(RHSOutputRows, index, NormalizedNativeAction.captures[index])
    BY <1>names, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF SharedAssignmentRule!PhysicalAssignmentReadsNameWriters, SharedAssignmentRule!PhysicalAssignmentOperandsMatch,
            SharedAssignmentRule!CopyReceiptNamesWriter, SharedAssignmentRule!CopyReceiptOrdinal,
            SharedAssignmentRule!LastDirectCopy, SharedAssignmentRule!DirectCopyReference,
            SharedAssignmentRule!AssignmentRhsPlan, SharedAssignmentRule!ExtractedNodePlan,
            SharedAssignmentRule!NativeAssignmentRekey, SharedAssignmentRule!NativeAssignmentRhsPlan, NormalizedNativeAction,
            DecodedNativeAction, NativeActionOrdinal, ActualNativeFailure, NativeAssignmentFailure, NativeActionRows,
            RHSOutputRows, RHSOutputCount, RHSOutputKeys
<1>writes.
    SharedAssignmentRule!NativeAssignmentWritesNameLastTargets(RHSOutputRows, NormalizedNativeAction, RHSOutputEntry, RHSOutputExit)
    BY <1>names, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
        DEF SharedAssignmentRule!NativeAssignmentWritesNameLastTargets, SharedAssignmentRule!NativeCopyFields,
            SharedAssignmentRule!NativeCopyRekey, SharedAssignmentRule!NativeCopyKey, SharedAssignmentRule!NativeCopyControlSlot,
            SharedAssignmentRule!CopyReceiptNamesWriter, SharedAssignmentRule!CopyReceiptOrdinal,
            SharedAssignmentRule!LastDirectCopy, SharedAssignmentRule!DirectCopyReference,
            SharedAssignmentRule!NativeAssignmentRekey, NormalizedNativeAction, DecodedNativeAction, NativeActionOrdinal,
            ActualNativeFailure, NativeAssignmentFailure, NativeActionRows, RHSOutputRows, RHSOutputCount, RHSOutputKeys,
            RHSOutputEntry, RHSOutputExit
<1>. QED BY ONLY <1>dispatch, <1>decode, <1>operands, <1>writes
    DEF SharedAssignmentRule!NativeAssignmentsNameTheirOperandsAndWrites, NormalizedNativeAction, RHSOutputCount

THEOREM ActualNativeAndTLAInitialObservationsUseTheCertifiedAssignmentHistory ==
    ASSUME Init
    PROVE \E history :
        /\ RHSOutputSourceHistory(history)
        /\ RHSOutputGeneratedHistory(history)
        /\ RHSOutputHistoryObservation(history)
        /\ ActualNativeAssignmentCaptureHistory(history)
        /\ SharedAssignmentRule!NativeAssignmentCheckedCallback(ActualNativeFailure.before,
               RHSOutputActionLabel, NativeActionOrdinal, RHSOutputSelected,
               SharedAssignmentRule!NativeAssignmentPrefix(history[RHSOutputCount])) = {ActualNativeFailure}
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
<1>native. ActualNativeAssignmentCaptureHistory(history)
    BY <1>entry, <1>actual, ActualNativeActionOperandsAndWritesNameTheAuthoredAssignmentRoles,
        RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
        SharedAssignmentRule!PhysicalNativeCapturesUseTheCertifiedAssignmentHistory, SMT
        DEF ActualNativeAssignmentCaptureHistory, NormalizedNativeAction, RHSOutputSourceHistory,
            SharedAssignmentRule!AssignmentBindings, SharedAssignmentRule!AssignmentIntValues,
            RHSOutputCount, RHSOutputStateType
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
    SharedAssignmentRule!NativeAssignmentCheckedCallback(ActualNativeFailure.before,
        RHSOutputActionLabel, NativeActionOrdinal, RHSOutputSelected,
        SharedAssignmentRule!NativeAssignmentPrefix(history[RHSOutputCount])) = {ActualNativeFailure}
    BY <1>entry, <1>failure, SMT DEF SharedAssignmentRule!NativeAssignmentCheckedCallback,
        SharedAssignmentRule!NativeAssignmentPrefix, NativeActionOrdinal, ActualNativeFailure, NativeAssignmentFailure
<1>route. SharedAssignmentRule!CopyReceiptNamesWriter(RHSOutputRows, 1, "count", <<"capture", 1>>)
    BY SMT DEF RHSOutputRows, Source!MasterRows, SharedAssignmentRule!CopyReceiptNamesWriter, SharedAssignmentRule!CopyReceiptOrdinal,
       SharedAssignmentRule!LastDirectCopy, SharedAssignmentRule!DirectCopyReference
<1>writer. SharedAssignmentRule!DirectCopyRoutes(RHSOutputKeys, RHSOutputRows)[1]["count"] = <<"capture", 1>>
    BY <1>route, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
       SharedAssignmentRule!NamedAssignmentReadRouteIsTheScheduledRoute, SMT
       DEF RHSOutputKeys, SharedAssignmentRule!SupportedAssignmentList
<1>projection. ActualNativeProjection =
    [site |-> 2, target |-> "count", payload |-> <<"integerOverflow", "addition", <<RHSOutputMax, 1>>>>,
     completed |-> <<RHSOutputMax>>, before |-> [count |-> RHSOutputMax]]
    BY <1>writer, SMT DEF ActualNativeProjection, ActualNativeFailure, NativeAssignmentFailure, RHSOutputFailureEvent,
        RHSOutputKeys, RHSOutputRows, RHSOutputMin, RHSOutputMax, Source!MasterRows,
        SharedAssignmentRule!CompletedAssignmentBindings, SharedAssignmentRule!CopyMaterializedState, SharedAssignmentRule!CopyReferenceValue
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
