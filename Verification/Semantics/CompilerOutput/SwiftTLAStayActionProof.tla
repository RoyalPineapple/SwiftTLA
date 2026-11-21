---- MODULE SwiftTLAStayActionProof ----
EXTENDS CheckedAdditionPrefixInitialModel, SwiftTLAStayActionSource, OrderedScalarCopyRule

ActionState(control, valueFirst, valueSecond, valueLast) ==
    [pc |-> control, first |-> valueFirst, second |-> valueSecond, last |-> valueLast]

Before == ActionState(pc, first, second, last)
After == ActionState(pc', first', second', last')
SourceTerminalControl == "Done"
AuthoredStayAction == AuthoredCopyActionRows[1]
StayDataKeys == AuthoredCopyFields
StayData(state) == [key \in StayDataKeys |-> state[key]]
AuthoredStayCopies == AuthoredStayAction.copies

StayRoutes == [index \in 0..(Len(StayRouteSnapshots) - 1) |-> StayRouteSnapshots[index + 1]]

SourceStay(before, after) ==
    /\ before.pc = AuthoredStayAction.label
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
    \/ label = AuthoredStayAction.label /\ SourceStay(before, after)
    \/ label = "Terminating" /\ SourceTerminating(before, after)

THEOREM AuthoredStayDeterminesThePhysicalCaptureAndFrame ==
    CopyPlan(StayDataKeys, AuthoredStayCopies, StayReads, StayWrites, StayRoutes)
    PROOF
    <1>. DEFINE count == Len(AuthoredStayCopies)
    <1>shape. /\ StayDataKeys = {"first", "second", "last"}
              /\ count = Len(StayReads)
              /\ DOMAIN AuthoredStayCopies = 1..count /\ DOMAIN StayReads = 1..count
        BY AuthoredCopySyntaxBindsWitnessRows, SMT
           DEF StayDataKeys, AuthoredStayCopies, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields, StayReads, count
    <1>seed. StayRoutes[0] = CopyEntryRoutes(StayDataKeys)
        BY <1>shape, SMT DEF StayRoutes, StayRouteSnapshots, CopyEntryRoutes
    <1>steps. \A index \in 1..count :
                  /\ AuthoredStayCopies[index].target \in StayDataKeys
                  /\ AuthoredStayCopies[index].read \in StayDataKeys
                  /\ StayReads[index] = StayRoutes[index - 1][AuthoredStayCopies[index].read]
                  /\ StayRoutes[index] = CopyReplace(StayDataKeys, StayRoutes[index - 1],
                                            AuthoredStayCopies[index].target, <<"capture", index>>)
        BY <1>shape, AuthoredCopySyntaxBindsWitnessRows, SMT
           DEF count, AuthoredStayCopies, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields, StayReads, StayRoutes,
               StayRouteSnapshots, CopyReplace
    <1>finish. StayWrites = StayRoutes[count]
        BY <1>shape, SMT DEF StayRoutes, StayRouteSnapshots, StayWrites, AuthoredStayCopies, count
    <1>. QED BY <1>shape, <1>seed, <1>steps, <1>finish, SMT DEF CopyPlan, count

THEOREM ActualStayRealizesThePhysicalCopyBranch ==
    stay <=>
        /\ pc = AuthoredStayAction.label
        /\ pc' = SourceTerminalControl
        /\ CompiledCopyBranch(StayDataKeys, Before, StayReads, StayWrites, StayData(After))
    PROOF
    <1>. DEFINE result(captures) == CopyMaterializedState(StayDataKeys, Before, captures, StayWrites)
    <1>data. StayDataKeys = {"first", "second", "last"}
        BY AuthoredCopySyntaxBindsWitnessRows, SMT DEF StayDataKeys, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields
    <1>rendered. stay <=> (pc = AuthoredStayAction.label /\ pc' = SourceTerminalControl
                             /\ StayData(After) = result(<<last>>))
        BY <1>data, AuthoredCopySyntaxBindsWitnessRows, SMT
           DEF stay, StayData, Before, After, ActionState, result, CopyMaterializedState,
               CopyReferenceValue, StayWrites, SourceTerminalControl, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields
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
    ENABLED stay <=> pc = AuthoredStayAction.label
    PROOF
    <1>only. ENABLED stay => pc = AuthoredStayAction.label
        BY AuthoredCopySyntaxBindsWitnessRows, ExpandENABLED, SMT DEF stay, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields
    <1>entry. ASSUME pc = AuthoredStayAction.label
              PROVE ENABLED stay
        <2>witness. \E nextPC, nextFirst, nextSecond, nextLast :
            /\ nextPC = SourceTerminalControl /\ nextFirst = first /\ nextSecond = second /\ nextLast = last
            PROOF
            <3>. WITNESS SourceTerminalControl, first, second, last
            <3>. QED BY SMT
        <2>. QED BY <2>witness, (pc = AuthoredStayAction.label), AuthoredCopySyntaxBindsWitnessRows,
             ExpandENABLED, SMT DEF stay, SourceTerminalControl, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields
    <1>. QED BY <1>only, <1>entry

THEOREM ActualTerminationRetainsEveryField ==
    Terminating <=> SourceTerminating(Before, After)
    BY SMT DEF Terminating, Before, After, ActionState, SourceTerminating, SourceTerminalControl

THEOREM ActualNextComposesTheCompleteLabeledActions ==
    ASSUME NEW label
    PROVE /\ (EmittedLabeled(label) <=> SourceLabeled(label, Before, After))
          /\ (Next <=> (SourceStay(Before, After) \/ SourceTerminating(Before, After)))
          /\ (ENABLED stay <=> pc = AuthoredStayAction.label)
    BY ActualStayMatchesAuthoredCopyAndCompleteFrame, ActualStayIsEnabledExactlyAtTheAuthoredEntry,
       ActualTerminationRetainsEveryField, AuthoredCopySyntaxBindsWitnessRows, SMT
       DEF Next, EmittedLabeled, SourceLabeled, AuthoredStayAction, WitnessCopyActionRows, WitnessCopyFields

====
