---- MODULE SwiftTLAStayActionProof ----
EXTENDS CheckedAdditionPrefixInitialModel, SwiftTLAStayActionSource, TLAPS

ActionState(control, valueFirst, valueSecond, valueLast) ==
    [pc |-> control, first |-> valueFirst, second |-> valueSecond, last |-> valueLast]

Before == ActionState(pc, first, second, last)
After == ActionState(pc', first', second', last')
SourceTerminalControl == "Done"

SourceCopyWithFrame(before, after, action, terminalControl) ==
    /\ before.pc = action.label
    /\ after.pc = terminalControl
    /\ after[action.target] = before[action.read]
    /\ \A key \in action.frame : after[key] = before[key]

SourceStay(before, after) ==
    SourceCopyWithFrame(before, after, SourceIdentityAction, SourceTerminalControl)

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
    \/ label = SourceIdentityAction.label /\ SourceStay(before, after)
    \/ label = "Terminating" /\ SourceTerminating(before, after)

THEOREM ActualStayMatchesAuthoredCopyAndCompleteFrame ==
    stay <=> SourceStay(Before, After)
    BY SMT DEF stay, Before, After, ActionState, SourceStay, SourceCopyWithFrame,
               SourceIdentityAction, SourceTerminalControl

THEOREM ActualStayIsEnabledExactlyAtTheAuthoredEntry ==
    ENABLED stay <=> pc = SourceIdentityAction.label
    PROOF
    <1>only. ENABLED stay => pc = SourceIdentityAction.label
        BY ExpandENABLED, SMT DEF stay, SourceIdentityAction
    <1>entry. ASSUME pc = SourceIdentityAction.label
              PROVE ENABLED stay
        <2>witness. \E nextPC, nextFirst, nextSecond, nextLast :
            pc = SourceIdentityAction.label
                => SourceStay(Before, ActionState(nextPC, nextFirst, nextSecond, nextLast))
            PROOF
            <3>. WITNESS SourceTerminalControl, first, second, Before[SourceIdentityAction.read]
            <3>. QED BY SMT DEF Before, ActionState, SourceStay, SourceCopyWithFrame,
                               SourceTerminalControl, SourceIdentityAction
        <2>. QED BY <2>witness, (pc = SourceIdentityAction.label), ExpandENABLED, SMT
             DEF stay, Before, ActionState, SourceStay, SourceCopyWithFrame, SourceTerminalControl, SourceIdentityAction
    <1>. QED BY <1>only, <1>entry

THEOREM ActualTerminationRetainsEveryField ==
    Terminating <=> SourceTerminating(Before, After)
    BY SMT DEF Terminating, Before, After, ActionState, SourceTerminating, SourceTerminalControl

THEOREM ActualNextComposesTheCompleteLabeledActions ==
    ASSUME NEW label
    PROVE /\ (EmittedLabeled(label) <=> SourceLabeled(label, Before, After))
          /\ (Next <=> (SourceStay(Before, After) \/ SourceTerminating(Before, After)))
          /\ (ENABLED stay <=> pc = SourceIdentityAction.label)
    BY ActualStayMatchesAuthoredCopyAndCompleteFrame, ActualStayIsEnabledExactlyAtTheAuthoredEntry,
       ActualTerminationRetainsEveryField, SMT
       DEF Next, EmittedLabeled, SourceLabeled, SourceIdentityAction

====
