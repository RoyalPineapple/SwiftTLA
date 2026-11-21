---- MODULE SwiftTLAStayActionProof ----
EXTENDS CheckedAdditionPrefixInitialModel, SwiftTLAStayActionSource, OrderedScalarCopyRule

ActionState(control, valueFirst, valueSecond, valueLast) ==
    [pc |-> control, first |-> valueFirst, second |-> valueSecond, last |-> valueLast]

Before == ActionState(pc, first, second, last)
After == ActionState(pc', first', second', last')
SourceTerminalControl == "Done"
StayDataKeys == AuthoredCopyDescriptor.frame \cup {AuthoredCopyDescriptor.target}
StayData(state) == [key \in StayDataKeys |-> state[key]]
AuthoredStayCopies == <<[target |-> AuthoredCopyDescriptor.target, read |-> AuthoredCopyDescriptor.read]>>

\* Physical references of the retained stay LET and its complete user-variable frame.
StayReads == <<<<"state", "last">>>>
StayWrites == [first |-> <<"state", "first">>, second |-> <<"state", "second">>,
               last |-> <<"capture", 1>>]
StayRoutes == [index \in 0..1 |-> IF index = 0 THEN CopyEntryRoutes(StayDataKeys) ELSE StayWrites]

SourceStay(before, after) ==
    /\ before.pc = AuthoredCopyDescriptor.label
    /\ after.pc = SourceTerminalControl
    /\ SourceCopyBranch(StayDataKeys, AuthoredStayCopies, before, StayData(after))

SourceTerminating(before, after) ==
    /\ before.pc = SourceTerminalControl
    /\ after.pc = before.pc
    /\ after.first = before.first
    /\ after.second = before.second
    /\ after.last = before.last

EmittedLabeled(label) ==
    \/ label = "stay" /\ stay
    \/ label = "Terminating" /\ Terminating

SourceLabeled(label, before, after) ==
    \/ label = AuthoredCopyDescriptor.label /\ SourceStay(before, after)
    \/ label = "Terminating" /\ SourceTerminating(before, after)

THEOREM AuthoredStayDeterminesThePhysicalCaptureAndFrame ==
    CopyPlan(StayDataKeys, AuthoredStayCopies, StayReads, StayWrites, StayRoutes)
    PROOF
    <1>shape. /\ StayDataKeys = {"first", "second", "last"}
              /\ Len(AuthoredStayCopies) = 1
              /\ AuthoredStayCopies[1] = [target |-> "last", read |-> "last"]
        BY AuthoredCopySyntaxBindsSourceIdentityAction, SMT
           DEF StayDataKeys, AuthoredStayCopies, SourceIdentityAction
    <1>seed. StayRoutes[0] = CopyEntryRoutes(StayDataKeys)
        BY SMT DEF StayRoutes
    <1>capture. StayReads[1] = StayRoutes[0]["last"]
        BY <1>shape, <1>seed, SMT DEF StayReads, CopyEntryRoutes
    <1>write. StayRoutes[1] = CopyReplace(StayDataKeys, StayRoutes[0], "last", <<"capture", 1>>)
        PROOF
        <2>. DEFINE written == CopyReplace(StayDataKeys, StayRoutes[0], "last", <<"capture", 1>>)
        <2>output. StayRoutes[1] = StayWrites BY ONLY SMT DEF StayRoutes
        <2>fields. ASSUME NEW a, NEW b, NEW c
                    PROVE DOMAIN [first |-> a, second |-> b, last |-> c] = {"first", "second", "last"}
            BY ONLY SetExtensionality, SMT
        <2>domain. DOMAIN StayWrites = StayDataKeys /\ DOMAIN written = StayDataKeys
            BY ONLY <1>shape, <2>fields, SMT DEF StayWrites, written, CopyReplace
        <2>first. written["first"] = StayWrites["first"]
            BY ONLY <1>shape, <1>seed, SMT DEF written, CopyReplace, CopyEntryRoutes, StayWrites
        <2>second. written["second"] = StayWrites["second"]
            BY ONLY <1>shape, <1>seed, SMT DEF written, CopyReplace, CopyEntryRoutes, StayWrites
        <2>last. written["last"] = StayWrites["last"]
            BY ONLY <1>shape, SMT DEF written, CopyReplace, StayWrites
        <2>. QED BY ONLY <1>shape, <2>first, <2>second, <2>last, <2>domain, <2>output, SetExtensionality, SMT DEF written, StayWrites, CopyReplace
    <1>. QED BY <1>shape, <1>seed, <1>capture, <1>write, SMT DEF CopyPlan, StayReads, StayRoutes, AuthoredStayCopies

THEOREM ActualStayRealizesThePhysicalCopyBranch ==
    stay <=>
        /\ pc = AuthoredCopyDescriptor.label
        /\ pc' = SourceTerminalControl
        /\ CompiledCopyBranch(StayDataKeys, Before, StayReads, StayWrites, StayData(After))
    PROOF
    <1>. DEFINE result(captures) == CopyMaterializedState(StayDataKeys, Before, captures, StayWrites)
    <1>data. StayDataKeys = {"first", "second", "last"}
        BY AuthoredCopySyntaxBindsSourceIdentityAction, SMT DEF StayDataKeys, SourceIdentityAction
    <1>rendered. stay <=> (pc = AuthoredCopyDescriptor.label /\ pc' = SourceTerminalControl
                             /\ StayData(After) = result(<<last>>))
        BY <1>data, AuthoredCopySyntaxBindsSourceIdentityAction, SMT
           DEF stay, StayData, Before, After, ActionState, result, CopyMaterializedState,
               CopyReferenceValue, StayWrites, SourceTerminalControl, SourceIdentityAction
    <1>enough. CopyCaptureHistory(Before, StayReads, <<last>>)
        BY SMT DEF CopyCaptureHistory, CopyReferenceValue, Before, ActionState, StayReads
    <1>unique. \A captures :
        CopyCaptureHistory(Before, StayReads, captures) => result(captures) = result(<<last>>)
        PROOF
        <2>. SUFFICES ASSUME NEW captures, CopyCaptureHistory(Before, StayReads, captures)
                     PROVE result(captures) = result(<<last>>)
             OBVIOUS
        <2>capture. captures[1] = last
            BY CopyCaptureHistory(Before, StayReads, captures), SMT
               DEF CopyCaptureHistory, CopyReferenceValue, Before, ActionState, StayReads
        <2>. QED BY <1>data, <2>capture, SMT
             DEF result, CopyMaterializedState, CopyReferenceValue, StayWrites
    <1>. QED BY <1>rendered, <1>enough, <1>unique, SMT DEF CompiledCopyBranch, result

THEOREM ActualStayMatchesAuthoredCopyAndCompleteFrame ==
    stay <=> SourceStay(Before, After)
    PROOF
    <1>copy. CompiledCopyBranch(StayDataKeys, Before, StayReads, StayWrites, StayData(After))
             <=> SourceCopyBranch(StayDataKeys, AuthoredStayCopies, Before, StayData(After))
        BY AuthoredStayDeterminesThePhysicalCaptureAndFrame, OrderedScalarCopyPlanPreservesTheCompleteBranch, SMT
    <1>. QED BY <1>copy, ActualStayRealizesThePhysicalCopyBranch, SMT DEF SourceStay, Before, After, ActionState

THEOREM ActualStayIsEnabledExactlyAtTheAuthoredEntry ==
    ENABLED stay <=> pc = AuthoredCopyDescriptor.label
    PROOF
    <1>only. ENABLED stay => pc = AuthoredCopyDescriptor.label
        BY AuthoredCopySyntaxBindsSourceIdentityAction, ExpandENABLED, SMT DEF stay, SourceIdentityAction
    <1>entry. ASSUME pc = AuthoredCopyDescriptor.label
              PROVE ENABLED stay
        <2>witness. \E nextPC, nextFirst, nextSecond, nextLast :
            /\ nextPC = SourceTerminalControl /\ nextFirst = first /\ nextSecond = second /\ nextLast = last
            PROOF
            <3>. WITNESS SourceTerminalControl, first, second, last
            <3>. QED BY SMT
        <2>. QED BY <2>witness, (pc = AuthoredCopyDescriptor.label), AuthoredCopySyntaxBindsSourceIdentityAction,
             ExpandENABLED, SMT DEF stay, SourceTerminalControl, SourceIdentityAction
    <1>. QED BY <1>only, <1>entry

THEOREM ActualTerminationRetainsEveryField ==
    Terminating <=> SourceTerminating(Before, After)
    BY SMT DEF Terminating, Before, After, ActionState, SourceTerminating, SourceTerminalControl

THEOREM ActualNextComposesTheCompleteLabeledActions ==
    ASSUME NEW label
    PROVE /\ (EmittedLabeled(label) <=> SourceLabeled(label, Before, After))
          /\ (Next <=> (SourceStay(Before, After) \/ SourceTerminating(Before, After)))
          /\ (ENABLED stay <=> pc = AuthoredCopyDescriptor.label)
    BY ActualStayMatchesAuthoredCopyAndCompleteFrame, ActualStayIsEnabledExactlyAtTheAuthoredEntry,
       ActualTerminationRetainsEveryField, AuthoredCopySyntaxBindsSourceIdentityAction, SMT
       DEF Next, EmittedLabeled, SourceLabeled, SourceIdentityAction

====
