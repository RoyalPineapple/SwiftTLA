---- MODULE SwiftTLANativeActionProof ----
EXTENDS SwiftTLAStayActionProof, SwiftTLANativeActions, OrderedScalarCopyRule

\* The validated Swift operations read the immutable snapshot and store optional pending writes.
\* A merge to an existing slot emits only if its value agrees. Materialization takes a pending
\* value when present and the old field otherwise. Captures and guards are total on typed states.
LOCAL NativeWriteValue(before, captures, reference) ==
    IF reference[1] = "control" THEN reference[2]
    ELSE CopyReferenceValue(before, captures, reference)

LOCAL NativeTargets(writes) == {writes[index][1] : index \in DOMAIN writes}

NativeVisits(plan, before, after, captures) ==
    /\ CopyCaptureHistory(before, plan.captures, captures)
    /\ \A index \in DOMAIN plan.guards : before.pc = plan.guards[index]
    /\ \A index \in DOMAIN plan.writes :
        after[plan.writes[index][1]] = NativeWriteValue(before, captures, plan.writes[index][2])
    /\ \A key \in DOMAIN before \ NativeTargets(plan.writes) : after[key] = before[key]

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
        /\ plan.guards = <<AuthoredCopyDescriptor.label>>
        /\ plan.captures = StayReads
        /\ plan.writes = <<<<"last", <<"capture", 1>>>>,
                            <<"pc", <<"control", SourceTerminalControl>>>>,
                            <<"first", <<"state", "first">>>>,
                            <<"second", <<"state", "second">>>>>>
        /\ StayDataKeys = {"first", "second", "last"}
        /\ DOMAIN Before = {"pc", "first", "second", "last"}
        BY ONLY AuthoredCopySyntaxBindsSourceIdentityAction, SMT
            DEF plan, NativeActionRows, SourceIdentityAction, StayReads, StayDataKeys,
                SourceTerminalControl, Before, ActionState
    <1>operations. \A captured :
        NativeVisits(plan, Before, After, captured)
        <=> /\ Before.pc = AuthoredCopyDescriptor.label
            /\ After.pc = SourceTerminalControl
            /\ CopyCaptureHistory(Before, StayReads, captured)
            /\ StayData(After) = materialized(captured)
        PROOF
        <2>. SUFFICES ASSUME NEW captured
            PROVE NativeVisits(plan, Before, After, captured)
                <=> /\ Before.pc = AuthoredCopyDescriptor.label
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
        <2>. QED BY ONLY <1>bindings, <2>frame, SMT
            DEF NativeVisits, NativeTargets, NativeWriteValue, CopyReferenceValue
    <1>branch. (\E captured : NativeVisits(plan, Before, After, captured))
        <=> /\ pc = AuthoredCopyDescriptor.label
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
    <1>forward. ASSUME NEW captured, NativeVisits(plan, Before, After, captured)
                PROVE SourceTerminating(Before, After)
        BY ONLY <1>bindings, SMT DEF NativeVisits, NativeWriteValue, CopyReferenceValue, SourceTerminating
    <1>backward. ASSUME SourceTerminating(Before, After)
                 PROVE NativeVisits(plan, Before, After, <<>>)
        BY ONLY <1>bindings, <1>knownCapture, SMT
             DEF NativeVisits, NativeWriteValue, NativeTargets, CopyReferenceValue, SourceTerminating
    <1>. QED BY ONLY <1>forward, <1>backward, SMT DEF plan

THEOREM NativeActionObservationsMatchActualNext ==
    /\ \A label : NativeLabeled(label, Before, After) <=> EmittedLabeled(label)
    /\ (Next <=> (\E label : NativeLabeled(label, Before, After)))
    PROOF
    <1>routes.
        /\ DOMAIN NativeActionRows = 1..2
        /\ NativeActionRows[1][1] = AuthoredCopyDescriptor.label
        /\ NativeActionRows[2][1] = "Terminating"
        BY ONLY AuthoredCopySyntaxBindsSourceIdentityAction, SMT DEF NativeActionRows, SourceIdentityAction
    <1>source. \A label :
        NativeLabeled(label, Before, After) <=> SourceLabeled(label, Before, After)
        BY ONLY <1>routes, NativeStayImplementsAuthoredCopyAndCompleteFrame,
            NativeTerminationRetainsEveryField, SMT DEF NativeLabeled, SourceLabeled
    <1>next. Next <=> (\E label : NativeLabeled(label, Before, After))
        BY ONLY <1>source, ActualNextComposesTheCompleteLabeledActions, SMT
            DEF SourceLabeled, SourceIdentityAction
    <1>. QED BY ONLY <1>source, <1>next, ActualNextComposesTheCompleteLabeledActions, SMT

====
