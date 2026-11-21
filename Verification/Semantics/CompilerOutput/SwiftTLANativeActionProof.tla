---- MODULE SwiftTLANativeActionProof ----
EXTENDS SwiftTLAStayActionProof, SwiftTLANativeActions, OrderedScalarCopyRule, NativePendingWriteFold

\* The validated Swift operations read the immutable snapshot and store optional pending writes.
\* A merge to an existing slot emits only if its value agrees. Materialization takes a pending
\* value when present and the old field otherwise. Captures and guards are total on typed states.
LOCAL NativeWriteValue(before, captures, reference) ==
    IF reference[1] = "control" THEN reference[2]
    ELSE CopyReferenceValue(before, captures, reference)

LOCAL NativeTargets(writes) == {writes[index][1] : index \in DOMAIN writes}

LOCAL NativeEvaluatedWrites(plan, before, captures) ==
    [index \in DOMAIN plan.writes |->
        <<plan.writes[index][1], NativeWriteValue(before, captures, plan.writes[index][2])>>]

NativeVisits(plan, before, after, captures) ==
    /\ CopyCaptureHistory(before, plan.captures, captures)
    /\ \A index \in DOMAIN plan.guards : before.pc = plan.guards[index]
    /\ NativePendingMergesEmit(DOMAIN before, before, after, Len(plan.writes),
           NativeEvaluatedWrites(plan, before, captures))

LOCAL NativeVisitConstraints(plan, before, after, captures) ==
    /\ CopyCaptureHistory(before, plan.captures, captures)
    /\ \A index \in DOMAIN plan.guards : before.pc = plan.guards[index]
    /\ \A index \in DOMAIN plan.writes :
        after[plan.writes[index][1]] = NativeWriteValue(before, captures, plan.writes[index][2])
    /\ \A key \in DOMAIN before \ NativeTargets(plan.writes) : after[key] = before[key]

THEOREM EmittedNativeMergesAgreeWithCompleteFieldConstraints ==
    ASSUME NEW plan, NEW before, NEW after, NEW captures,
           Len(plan.writes) \in Nat,
           DOMAIN plan.writes = 1..Len(plan.writes),
           \A index \in DOMAIN plan.writes : plan.writes[index][1] \in DOMAIN before
    PROVE NativeVisits(plan, before, after, captures) <=> NativeVisitConstraints(plan, before, after, captures)
    PROOF
    <1>. DEFINE writes == NativeEvaluatedWrites(plan, before, captures)
    <1>writes. \A index \in DOMAIN plan.writes :
        /\ writes[index][1] = plan.writes[index][1]
        /\ writes[index][2] = NativeWriteValue(before, captures, plan.writes[index][2])
        BY SMT DEF writes, NativeEvaluatedWrites
    <1>targets. \A index \in 1..Len(plan.writes) : writes[index][1] \in DOMAIN before
        BY <1>writes, SMT
    <1>keys. PendingWriteKeys(writes, Len(plan.writes)) = NativeTargets(plan.writes)
        BY <1>writes, SetExtensionality, SMT DEF PendingWriteKeys, NativeTargets
    <1>fold. NativePendingMergesEmit(DOMAIN before, before, after, Len(plan.writes), writes)
               <=> NativePendingWriteConstraints(DOMAIN before, before, after, Len(plan.writes), writes)
        BY <1>targets, PendingMergeFoldMaterializesExactlyTheCompatibleWrites, SMT
    <1>. QED BY <1>writes, <1>keys, <1>fold, SMT
        DEF NativeVisits, NativeVisitConstraints, NativePendingWriteConstraints, writes

NativeLabeled(label, before, after) ==
    \E row \in DOMAIN NativeActionRows :
        /\ NativeActionRows[row][1] = label
        /\ \E captured : NativeVisits(NativeActionRows[row][2], before, after, captured)

THEOREM NativeStayImplementsAuthoredCopyAndCompleteFrame ==
    (\E captured : NativeVisits(NativeActionRows[1][2], Before, After, captured))
        <=> SourceStay(Before, After)
    PROOF
    <1>. DEFINE plan == NativeActionRows[1][2]
                materialized(captured) == CopyMaterializedState(StayDataKeys, Before, captured, StayWrites)
    <1>bindings.
        /\ plan.guards = <<AuthoredStayAction.label>>
        /\ plan.captures = StayReads
        /\ plan.writes = <<<<"last", <<"capture", 1>>>>,
                            <<"pc", <<"control", SourceTerminalControl>>>>,
                            <<"first", <<"state", "first">>>>,
                            <<"second", <<"state", "second">>>>>>
        /\ StayDataKeys = {"first", "second", "last"}
        /\ DOMAIN Before = {"pc", "first", "second", "last"}
        BY ONLY AuthoredCopySyntaxBindsWitnessRows, SMT
            DEF plan, NativeActionRows, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields, StayReads, StayDataKeys,
                SourceTerminalControl, Before, ActionState
    <1>operations. \A captured :
        NativeVisits(plan, Before, After, captured)
        <=> /\ Before.pc = AuthoredStayAction.label
            /\ After.pc = SourceTerminalControl
            /\ CopyCaptureHistory(Before, StayReads, captured)
            /\ StayData(After) = materialized(captured)
        PROOF
        <2>. SUFFICES ASSUME NEW captured
            PROVE NativeVisits(plan, Before, After, captured)
                <=> /\ Before.pc = AuthoredStayAction.label
                    /\ After.pc = SourceTerminalControl
                    /\ CopyCaptureHistory(Before, StayReads, captured)
                    /\ StayData(After) = materialized(captured)
            OBVIOUS
        <2>frame. StayData(After) = materialized(captured)
            <=> /\ After.first = Before.first
                /\ After.second = Before.second
                /\ After.last = captured[1]
            BY ONLY <1>bindings, SMT
                DEF materialized, CopyMaterializedState, CopyReferenceValue, StayData, StayWrites
        <2>fold. NativeVisits(plan, Before, After, captured) <=> NativeVisitConstraints(plan, Before, After, captured)
            BY ONLY <1>bindings, EmittedNativeMergesAgreeWithCompleteFieldConstraints, SMT
        <2>. QED BY ONLY <1>bindings, <2>frame, <2>fold, SMT
            DEF NativeVisitConstraints, NativeTargets, NativeWriteValue, CopyReferenceValue
    <1>branch. (\E captured : NativeVisits(plan, Before, After, captured))
        <=> /\ pc = AuthoredStayAction.label
            /\ pc' = SourceTerminalControl
            /\ CompiledCopyBranch(StayDataKeys, Before, StayReads, StayWrites, StayData(After))
        BY ONLY <1>operations, SMT DEF CompiledCopyBranch, materialized, Before, After, ActionState
    <1>. QED BY ONLY <1>branch, ActualStayRealizesThePhysicalCopyBranch,
        ActualStayMatchesAuthoredCopyAndCompleteFrame DEF plan

THEOREM NativeTerminationRetainsEveryField ==
    (\E captured : NativeVisits(NativeActionRows[2][2], Before, After, captured))
        <=> SourceTerminating(Before, After)
    PROOF
    <1>. DEFINE plan == NativeActionRows[2][2]
    <1>bindings.
        /\ plan.guards = <<SourceTerminalControl>>
        /\ plan.captures = <<>>
        /\ plan.writes = <<<<"pc", <<"state", "pc">>>>,
                            <<"first", <<"state", "first">>>>,
                            <<"second", <<"state", "second">>>>,
                            <<"last", <<"state", "last">>>>,
                            <<"pc", <<"state", "pc">>>>>>
        /\ DOMAIN Before = {"pc", "first", "second", "last"}
        BY ONLY SMT DEF plan, NativeActionRows, SourceTerminalControl, Before, ActionState
    <1>knownCapture. CopyCaptureHistory(Before, plan.captures, <<>>)
        BY ONLY <1>bindings, SMT DEF CopyCaptureHistory
    <1>covered. NativeTargets(plan.writes) = DOMAIN Before
        BY ONLY <1>bindings, SetExtensionality, SMT DEF NativeTargets
    <1>fold. \A captured :
        NativeVisits(plan, Before, After, captured) <=> NativeVisitConstraints(plan, Before, After, captured)
        BY ONLY <1>bindings, EmittedNativeMergesAgreeWithCompleteFieldConstraints, SMT
    <1>forward. ASSUME NEW captured, NativeVisitConstraints(plan, Before, After, captured)
                PROVE SourceTerminating(Before, After)
        <2>guard. Before.pc = SourceTerminalControl
            BY ONLY NativeVisitConstraints(plan, Before, After, captured), <1>bindings, SMT
                DEF NativeVisitConstraints
        <2>writes. \A index \in DOMAIN plan.writes :
            After[plan.writes[index][1]] = NativeWriteValue(Before, captured, plan.writes[index][2])
            BY ONLY NativeVisitConstraints(plan, Before, After, captured) DEF NativeVisitConstraints
        <2>pc. After.pc = Before.pc
            BY ONLY <1>bindings, <2>writes, SMT DEF NativeWriteValue, CopyReferenceValue
        <2>first. After.first = Before.first
            BY ONLY <1>bindings, <2>writes, SMT DEF NativeWriteValue, CopyReferenceValue
        <2>second. After.second = Before.second
            BY ONLY <1>bindings, <2>writes, SMT DEF NativeWriteValue, CopyReferenceValue
        <2>last. After.last = Before.last
            BY ONLY <1>bindings, <2>writes, SMT DEF NativeWriteValue, CopyReferenceValue
        <2>. QED BY ONLY <2>guard, <2>pc, <2>first, <2>second, <2>last DEF SourceTerminating
    <1>backward. ASSUME SourceTerminating(Before, After)
                 PROVE NativeVisitConstraints(plan, Before, After, <<>>)
        <2>guard. \A index \in DOMAIN plan.guards : Before.pc = plan.guards[index]
            BY ONLY <1>bindings, SourceTerminating(Before, After), SMT DEF SourceTerminating
        <2>writes. \A index \in DOMAIN plan.writes :
            After[plan.writes[index][1]] = NativeWriteValue(Before, <<>>, plan.writes[index][2])
            BY ONLY <1>bindings, SourceTerminating(Before, After), SMT
                DEF NativeWriteValue, CopyReferenceValue, SourceTerminating
        <2>. QED BY ONLY <1>covered, <1>knownCapture, <2>guard, <2>writes, SMT
            DEF NativeVisitConstraints
    <1>. QED BY ONLY <1>forward, <1>backward, <1>fold, SMT DEF plan

THEOREM NativeActionObservationsMatchActualNext ==
    /\ \A label : NativeLabeled(label, Before, After) <=> EmittedLabeled(label)
    /\ (Next <=> (\E label : NativeLabeled(label, Before, After)))
    PROOF
    <1>routes.
        /\ DOMAIN NativeActionRows = 1..2
        /\ NativeActionRows[1][1] = AuthoredStayAction.label
        /\ NativeActionRows[2][1] = "Terminating"
        BY ONLY AuthoredCopySyntaxBindsWitnessRows, SMT DEF NativeActionRows, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields
    <1>source. \A label :
        NativeLabeled(label, Before, After) <=> SourceLabeled(label, Before, After)
        BY ONLY <1>routes, NativeStayImplementsAuthoredCopyAndCompleteFrame,
            NativeTerminationRetainsEveryField, SMT DEF NativeLabeled, SourceLabeled
    <1>next. Next <=> (\E label : NativeLabeled(label, Before, After))
        BY ONLY <1>source, ActualNextComposesTheCompleteLabeledActions, SMT
            DEF SourceLabeled, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields
    <1>. QED BY ONLY <1>source, <1>next, ActualNextComposesTheCompleteLabeledActions, SMT

====
