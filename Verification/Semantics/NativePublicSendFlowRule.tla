---- MODULE NativePublicSendFlowRule ----
EXTENDS TLAPS, SequenceTheorems_proofs

LOCAL Outcomes == INSTANCE ActionTreeOutcomeComposition
    WITH UpdateValues <- {}, FailureValues <- {}, NoFailure <- <<>>
LOCAL Store == INSTANCE NativePendingWriteFold
    WITH Vars <- {}, Values <- {}, ActionLabels <- {}, FailureValues <- {}, NoFailure <- <<>>

LOCAL Rank(steps, name) == CHOOSE place \in DOMAIN steps : steps[place] = name
LOCAL Receiver(plan, action) ==
    LET row == CHOOSE index \in DOMAIN plan.receivers : plan.receivers[index].handle = action
    IN plan.receivers[row].slot

\* The operation and binding checks below apply to a plan read from Swift.
\* The routed visitor's ordered callback and error arrays are supplied by its caller.
DecodedSendOperands(plan, action) ==
    LET distinct(values) == \A i, j \in DOMAIN values : values[i] = values[j] => i = j
    IN
    /\ \E row \in DOMAIN plan.receivers : plan.receivers[row].handle = action
    /\ \A row \in DOMAIN plan.receivers :
         plan.receivers[row].handle = action => plan.receivers[row].slot = plan.writeTarget
    /\ plan.send = <<plan.selected, plan.captured, plan.writeTarget, plan.result>>
    /\ distinct(plan.send)
    /\ plan.callbackOrder = <<plan.collector, plan.visitorResult, plan.failureGate, "return">>
    /\ distinct(plan.callbackOrder)
    /\ distinct(<<plan.inputAction, plan.captured, plan.getter>>)
    /\ plan.checking = "none" /\ plan.visitor = "_visitSuccessors"
    /\ plan.failureGate = "_firstNativeEvaluationFailure"
    /\ plan.appendOperation = "_appendNativeOutcome" /\ plan.appended = "$0"
    /\ plan.suppliedAction = plan.inputAction /\ plan.visitorAction = plan.inputAction
    /\ plan.collector = plan.appendTarget /\ plan.collector = plan.snapshots
    /\ plan.selector = "_singleNativeOutcome"
    /\ DOMAIN plan.selectorGuards = {1, 2}
    /\ plan.selectorGuards[1].test = "first" /\ plan.selectorGuards[2].test = "count"
    /\ plan.lookupResult = plan.lookupBinding
    /\ plan.projection = <<plan.writeTarget, "state">>
    /\ plan.captureSource = plan.getter
    /\ plan.writeValue = plan.selected
    /\ plan.fields = [action |-> plan.inputAction, before |-> plan.captured, after |-> plan.getter]

LOCAL Continue(value) == [updates |-> <<value>>, failure |-> <<>>]
LOCAL Stop(kind, reason) == [updates |-> <<>>, failure |-> [kind |-> kind, value |-> reason]]

LOCAL Collect(plan, action, visits, failures) ==
    LET input == [name \in {plan.inputAction} |-> action]
        fromVisitor == Rank(plan.callbackOrder, plan.visitorResult)
        gate == Rank(plan.callbackOrder, plan.failureGate)
        returned == Rank(plan.callbackOrder, "return")
        buffer == [name \in {plan.collector} |-> IF name = plan.appendTarget THEN visits ELSE <<>>]
        failure == Outcomes!ActionHistoryFirstFailure(failures)
    IN IF /\ plan.checking = "none" /\ plan.visitor = "_visitSuccessors"
          /\ plan.failureGate = "_firstNativeEvaluationFailure"
          /\ plan.appendOperation = "_appendNativeOutcome" /\ plan.appended = "$0"
          /\ input[plan.suppliedAction] = input[plan.visitorAction]
          /\ fromVisitor < gate /\ gate < returned
       THEN IF failure = <<>> THEN Continue(buffer[plan.snapshots])
            ELSE Stop("evaluationFailure", failure)
       ELSE Stop("unsupported", <<>>)

LOCAL SelectorGuard(plan, guard, visits) ==
    CASE guard.test = "first" ->
         IF Len(visits) = 0 THEN Stop("disabled", plan.errors[guard.error]) ELSE Continue(visits)
    [] guard.test = "count" ->
         IF Len(visits) # 1 THEN Stop("ambiguous", plan.errors[guard.error]) ELSE Continue(visits)
    [] OTHER -> Stop("unsupported", <<>>)

LOCAL Select(plan, visits) ==
    LET checked == Outcomes!ContinueBranch(SelectorGuard(plan, plan.selectorGuards[1], visits),
                         [values \in {visits} |-> SelectorGuard(plan, plan.selectorGuards[2], values)])
    IN IF plan.selector = "_singleNativeOutcome"
       THEN Outcomes!ContinueBranch(checked,
            [values \in {visits} |->
                Continue([name \in {plan.lookupBinding} |-> values[1]][plan.lookupResult])])
       ELSE Stop("unsupported", <<>>)

LOCAL Project(storage, plan) ==
    LET snapshot == storage[plan.projection[1]]
    IN [field \in {"state"} |-> snapshot[2]][plan.projection[2]]

LOCAL CommittedSend(snapshot, transition) ==
    Continue([kind |-> "success", current |-> snapshot, value |-> transition])

LOCAL Finish(plan, action, prior, selected) ==
    LET receiver == Receiver(plan, action)
        earlier == [key \in {receiver} |-> prior]
        local == [name \in {plan.selected} |-> selected]
        write == [key \in {plan.writeTarget} |-> local[plan.writeValue]]
        later == Store!NativeMaterializedSlots(DOMAIN earlier, earlier, write)
        read(step) == Project(
            IF Rank(plan.send, step) < Rank(plan.send, plan.writeTarget) THEN earlier ELSE later, plan)
        captured == [name \in {plan.getter} |-> read(plan.captured)][plan.captureSource]
        locals == [name \in {plan.inputAction, plan.captured, plan.getter} |->
            IF name = plan.inputAction THEN action
            ELSE IF name = plan.captured THEN captured ELSE read(plan.result)]
    IN CommittedSend(later[receiver], [field \in DOMAIN plan.fields |-> locals[plan.fields[field]]])

LOCAL Unchanged(prior, kind, value) == [kind |-> kind, current |-> prior, value |-> value]

DecodedPublicSend(plan, prior, action, visits, failures) ==
    LET collected == Collect(plan, action, visits, failures)
        selected == Outcomes!ContinueBranch(collected, [values \in {visits} |-> Select(plan, values)])
        completed == Outcomes!ContinueBranch(selected,
            [snapshot \in {visits[index] : index \in DOMAIN visits} |-> Finish(plan, action, prior, snapshot)])
    IN IF /\ Rank(plan.send, plan.selected) < Rank(plan.send, plan.writeTarget)
          /\ Rank(plan.send, plan.writeTarget) < Rank(plan.send, plan.result)
       THEN IF completed.failure = <<>> THEN completed.updates[1]
            ELSE Unchanged(prior, completed.failure.kind, completed.failure.value)
       ELSE Unchanged(prior, "unsupported", <<>>)

PublicSendOutcome(plan, prior, action, visits, failures) ==
    LET stopped(kind, value) == [kind |-> kind, current |-> prior, value |-> value]
    IN IF Len(failures) # 0 THEN stopped("evaluationFailure", failures[1])
       ELSE IF Len(visits) = 0 THEN stopped("disabled", plan.errors[plan.selectorGuards[1].error])
       ELSE IF Len(visits) # 1 THEN stopped("ambiguous", plan.errors[plan.selectorGuards[2].error])
       ELSE [kind |-> "success", current |-> visits[1],
             value |-> [action |-> action, before |-> prior[2], after |-> visits[1][2]]]

THEOREM DecodedSendUsesTheFirstErrorOrCommitsExactlyOneCallback ==
    ASSUME NEW plan, NEW action, NEW prior, DecodedSendOperands(plan, action),
           NEW snapshots, NEW reasons, <<>> \notin reasons,
           NEW visits \in Seq(snapshots), NEW failures \in Seq(reasons)
    PROVE DecodedPublicSend(plan, prior, action, visits, failures) =
              PublicSendOutcome(plan, prior, action, visits, failures)
PROOF
<1>send.
    /\ Rank(plan.send, plan.selected) = 1
    /\ Rank(plan.send, plan.captured) = 2
    /\ Rank(plan.send, plan.writeTarget) = 3
    /\ Rank(plan.send, plan.result) = 4
    BY ONLY DecodedSendOperands(plan, action), SMT DEF DecodedSendOperands, Rank
<1>collectOrder.
    /\ Rank(plan.callbackOrder, plan.visitorResult) = 2
    /\ Rank(plan.callbackOrder, plan.failureGate) = 3
    /\ Rank(plan.callbackOrder, "return") = 4
    BY ONLY DecodedSendOperands(plan, action), SMT DEF DecodedSendOperands, Rank
<1>nonempty. Len(failures) # 0 => failures[1] \in reasons
    BY ONLY (failures \in Seq(reasons)), LenProperties, ElementOfSeq, SMT
<1>collect.
    Collect(plan, action, visits, failures) =
      IF Len(failures) = 0 THEN Continue(visits) ELSE Stop("evaluationFailure", failures[1])
    BY ONLY DecodedSendOperands(plan, action), <1>collectOrder, <1>nonempty,
        (<<>> \notin reasons), SMT DEF DecodedSendOperands, Collect, Outcomes!ActionHistoryFirstFailure
<1>select.
    Select(plan, visits) =
        IF Len(visits) = 0 THEN Stop("disabled", plan.errors[plan.selectorGuards[1].error])
        ELSE IF Len(visits) # 1 THEN Stop("ambiguous", plan.errors[plan.selectorGuards[2].error])
        ELSE Continue(visits[1])
    <2>operands.
        /\ plan.selector = "_singleNativeOutcome"
        /\ plan.selectorGuards[1].test = "first"
        /\ plan.selectorGuards[2].test = "count"
        /\ plan.lookupResult = plan.lookupBinding
        BY ONLY DecodedSendOperands(plan, action) DEF DecodedSendOperands
    <2>first. SelectorGuard(plan, plan.selectorGuards[1], visits) =
        IF Len(visits) = 0 THEN Stop("disabled", plan.errors[plan.selectorGuards[1].error])
        ELSE Continue(visits)
        BY ONLY <2>operands, SMT DEF SelectorGuard
    <2>second. SelectorGuard(plan, plan.selectorGuards[2], visits) =
        IF Len(visits) # 1 THEN Stop("ambiguous", plan.errors[plan.selectorGuards[2].error])
        ELSE Continue(visits)
        BY ONLY <2>operands, SMT DEF SelectorGuard
    <2>empty. CASE Len(visits) = 0
        BY ONLY <2>empty, <2>operands, <2>first, IsaM("auto")
            DEF Select, Stop, Outcomes!ContinueBranch
    <2>one. CASE Len(visits) = 1
        BY ONLY <2>one, <2>operands, <2>first, <2>second, IsaM("auto")
            DEF Select, Continue, Outcomes!ContinueBranch
    <2>many. CASE Len(visits) # 0 /\ Len(visits) # 1
        <3>. DEFINE countCheck == [values \in {visits} |-> SelectorGuard(plan, plan.selectorGuards[2], values)]
                    checked == Outcomes!ContinueBranch(SelectorGuard(plan, plan.selectorGuards[1], visits), countCheck)
                    ambiguous == Stop("ambiguous", plan.errors[plan.selectorGuards[2].error])
        <3>lookup. countCheck[visits] = ambiguous
            BY ONLY <2>many, <2>second, SMT DEF countCheck, ambiguous
        <3>checked. checked = ambiguous
            BY ONLY <2>many, <2>first, <3>lookup, SMT DEF checked, Continue, Outcomes!ContinueBranch
        <3>result. Select(plan, visits) = ambiguous
            BY ONLY <2>operands, <3>checked, SMT
                DEF Select, checked, countCheck, ambiguous, Stop, Outcomes!ContinueBranch
        <3>. QED BY ONLY <2>many, <3>result, SMT DEF ambiguous
    <2>. QED BY ONLY <2>empty, <2>one, <2>many
<1>receiver. Receiver(plan, action) = plan.writeTarget
    BY ONLY DecodedSendOperands(plan, action), SMT DEF DecodedSendOperands, Receiver
<1>finish. \A selected :
    Finish(plan, action, prior, selected) =
        Continue([kind |-> "success", current |-> selected,
                  value |-> [action |-> action, before |-> prior[2], after |-> selected[2]]])
    <2>. TAKE selected
    <2>bindings.
        /\ plan.projection = <<plan.writeTarget, "state">>
        /\ plan.writeValue = plan.selected /\ plan.captureSource = plan.getter
        /\ plan.fields = [action |-> plan.inputAction, before |-> plan.captured, after |-> plan.getter]
        /\ plan.inputAction # plan.captured /\ plan.inputAction # plan.getter
        /\ plan.captured # plan.getter
        BY ONLY DecodedSendOperands(plan, action), SMT DEF DecodedSendOperands
    <2>. DEFINE
        before == [key \in {Receiver(plan, action)} |-> prior]
        selectedBinding == [name \in {plan.selected} |-> selected]
        write == [key \in {plan.writeTarget} |-> selectedBinding[plan.writeValue]]
        after == Store!NativeMaterializedSlots(DOMAIN before, before, write)
    <2>commit.
        /\ before[plan.writeTarget] = prior
        /\ after[plan.writeTarget] = selected
        BY ONLY <1>receiver, <2>bindings, IsaM("auto")
            DEF before, after, write, selectedBinding, Store!NativeMaterializedSlots
    <2>reads.
        /\ Project(before, plan) = prior[2]
        /\ Project(after, plan) = selected[2]
        BY ONLY <2>commit, <2>bindings, IsaM("auto") DEF Project
    <2>order.
        /\ Rank(plan.send, plan.captured) < Rank(plan.send, plan.writeTarget)
        /\ ~(Rank(plan.send, plan.result) < Rank(plan.send, plan.writeTarget))
        BY ONLY <1>send, SMT
    <2>. DEFINE read(step) == Project(
                    IF Rank(plan.send, step) < Rank(plan.send, plan.writeTarget) THEN before ELSE after, plan)
                captured == [name \in {plan.getter} |-> read(plan.captured)][plan.captureSource]
                locals == [name \in {plan.inputAction, plan.captured, plan.getter} |->
                    IF name = plan.inputAction THEN action
                    ELSE IF name = plan.captured THEN captured ELSE read(plan.result)]
                fields == [field \in DOMAIN plan.fields |-> locals[plan.fields[field]]]
    <2>values.
        /\ captured = prior[2] /\ read(plan.result) = selected[2]
        BY ONLY <2>order, <2>bindings, <2>reads, SMT DEF captured, read
    <2>returned.
        fields = [action |-> action, before |-> prior[2], after |-> selected[2]]
        BY ONLY <2>bindings, <2>values, SMT DEF fields, locals
    <2>effect. Finish(plan, action, prior, selected) =
        CommittedSend(after[Receiver(plan, action)], fields)
        BY ONLY DEF Finish, before, after, write, selectedBinding, fields, locals, captured, read
    <2>installed. after[Receiver(plan, action)] = selected
        BY ONLY <2>commit, <1>receiver, IsaM("simp")
    <2>returnedEffect. CommittedSend(after[Receiver(plan, action)], fields) =
        CommittedSend(selected, [action |-> action, before |-> prior[2], after |-> selected[2]])
        BY ONLY <2>installed, <2>returned, SMT
    <2>result. Finish(plan, action, prior, selected) =
        CommittedSend(selected, [action |-> action, before |-> prior[2], after |-> selected[2]])
        BY ONLY <2>effect, <2>returnedEffect, SMT
    <2>. QED BY ONLY <2>result DEF CommittedSend
<1>selected. Len(visits) = 1 => visits[1] \in {visits[index] : index \in DOMAIN visits}
    BY ONLY (visits \in Seq(snapshots)), LenProperties, SMT
<1>. DEFINE collected == Collect(plan, action, visits, failures)
            selectNext == [values \in {visits} |-> Select(plan, values)]
            selectedCall == Outcomes!ContinueBranch(collected, selectNext)
            targets == {visits[index] : index \in DOMAIN visits}
            commit == [snapshot \in targets |-> Finish(plan, action, prior, snapshot)]
            completed == Outcomes!ContinueBranch(selectedCall, commit)
            observed == DecodedPublicSend(plan, prior, action, visits, failures)
            expected == PublicSendOutcome(plan, prior, action, visits, failures)
<1>. SUFFICES observed = expected
    BY ONLY (observed = expected) DEF observed, expected
<1>lengths.
    /\ Len(<<>>) = 0
    /\ \A value : Len(<<value>>) = 1 /\ <<value>>[1] = value
    BY ONLY EmptySeq, SeqDef, LenProperties, SMT
<1>observe. observed =
    IF completed.failure = <<>> THEN completed.updates[1]
    ELSE Unchanged(prior, completed.failure.kind, completed.failure.value)
    BY ONLY <1>send, SMT DEF observed, completed, selectedCall, collected, selectNext, commit, targets,
        DecodedPublicSend
<1>selection.
    selectedCall = IF Len(failures) = 0 THEN Select(plan, visits) ELSE Stop("evaluationFailure", failures[1])
    <2>lookup. selectNext[visits] = Select(plan, visits)
        BY ONLY SMT DEF selectNext
    <2>normal. CASE Len(failures) = 0
        <3>input. collected = Continue(visits)
            BY ONLY <2>normal, <1>collect, SMT DEF collected
        <3>. QED BY ONLY <2>normal, <2>lookup, <3>input, <1>lengths, SMT
            DEF selectedCall, Continue, Outcomes!ContinueBranch
    <2>failed. CASE Len(failures) # 0
        <3>input. collected = Stop("evaluationFailure", failures[1])
            BY ONLY <2>failed, <1>collect, SMT DEF collected
        <3>. QED BY ONLY <2>failed, <3>input, <1>lengths, SMT
            DEF selectedCall, Stop, Outcomes!ContinueBranch
    <2>. QED BY ONLY <2>normal, <2>failed, SMT
<1>stopped. ASSUME NEW kind, NEW reason, selectedCall = Stop(kind, reason)
    PROVE observed = Unchanged(prior, kind, reason)
    <2>done. completed = Stop(kind, reason)
        BY ONLY (selectedCall = Stop(kind, reason)), <1>lengths, SMT
            DEF completed, Stop, Outcomes!ContinueBranch
    <2>. QED BY ONLY <1>observe, <2>done, SMT DEF Stop
<1>failure. CASE Len(failures) # 0
    <2>selectedError. selectedCall = Stop("evaluationFailure", failures[1])
        BY ONLY <1>selection, <1>failure, SMT
    <2>. QED BY ONLY <2>selectedError, <1>stopped, <1>failure, SMT DEF expected, PublicSendOutcome, Unchanged
<1>disabled. CASE Len(failures) = 0 /\ Len(visits) = 0
    <2>selectedError. selectedCall = Stop("disabled", plan.errors[plan.selectorGuards[1].error])
        BY ONLY <1>selection, <1>select, <1>disabled, SMT
    <2>. QED BY ONLY <2>selectedError, <1>stopped, <1>disabled, SMT DEF expected, PublicSendOutcome, Unchanged
<1>ambiguous. CASE Len(failures) = 0 /\ Len(visits) # 0 /\ Len(visits) # 1
    <2>selectedError. selectedCall = Stop("ambiguous", plan.errors[plan.selectorGuards[2].error])
        BY ONLY <1>selection, <1>select, <1>ambiguous, SMT
    <2>. QED BY ONLY <2>selectedError, <1>stopped, <1>ambiguous, SMT DEF expected, PublicSendOutcome, Unchanged
<1>success. CASE Len(failures) = 0 /\ Len(visits) = 1
    <2>single. selectedCall = Continue(visits[1])
        BY ONLY <1>selection, <1>select, <1>success, SMT
    <2>target. visits[1] \in targets
        BY ONLY <1>selected, <1>success, SMT DEF targets
    <2>apply. commit[visits[1]] = Finish(plan, action, prior, visits[1])
        BY ONLY <2>target, SMT DEF commit
    <2>done. completed = Finish(plan, action, prior, visits[1])
        BY ONLY <2>single, <2>apply, <1>lengths, SMT DEF completed, Continue, Outcomes!ContinueBranch
    <2>value. completed = Continue(expected)
        BY ONLY <2>done, <1>finish, <1>success, SMT DEF expected, PublicSendOutcome
    <2>. QED BY ONLY <1>observe, <2>value, <1>lengths, SMT DEF Continue
<1>. QED BY ONLY <1>failure, <1>disabled, <1>ambiguous, <1>success, SMT

====
