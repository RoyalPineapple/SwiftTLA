---- MODULE RenderedIntAssignmentActionRule ----
EXTENDS RenderedIntAssignmentTerms

RenderedAssignmentInventory(rows, before, raw) ==
    \A index \in DOMAIN rows :
        LET plan == raw.plans[index]
        IN /\ PhysicalAssignmentReadsMatchRoutes(rows, index, plan)
           /\ RenderedRhsTerms(plan, before, HistoryPrefix(raw.roots, index - 1),
                              raw.starts[index], raw.terms[index])
           /\ RenderedRhsGuards(plan, raw.terms[index], raw.guards[index])
           /\ raw.roots[index] = raw.terms[index][plan.count]

RenderedAssignmentsPass(raw, end) ==
    \A index \in 1..end : EveryRenderedGuardPasses(raw.guards[index], raw.plans[index].count)

RenderedAssignmentFailsAt(raw, end, index, node) ==
    /\ index \in 1..end
    /\ RenderedAssignmentsPass(raw, index - 1)
    /\ FirstRejectedRenderedGuard(raw.guards[index], raw.plans[index].count, node)

RenderedAssignmentFailure(rows, before, raw, index, node) ==
    [before |-> CompletedAssignmentBindings(before, rows, HistoryPrefix(raw.roots, index - 1)),
     site |-> index,
     payload |-> RenderedTermOverflow(raw.plans[index], raw.terms[index], node).failure]

RenderedAssignmentHistoryAt(rows, before, raw, history, end) ==
    /\ RenderedAssignmentsPass(raw, end) =>
          /\ history[end].failure = <<>>
          /\ history[end].completed = HistoryPrefix(raw.roots, end)
    /\ \A index \in 1..end : \A node \in 1..raw.plans[index].count :
         RenderedAssignmentFailsAt(raw, end, index, node) =>
           /\ raw.plans[index].kinds[node] = "add"
           /\ history[end].failure = RenderedAssignmentFailure(rows, before, raw, index, node)
           /\ history[end].completed = HistoryPrefix(raw.roots, index - 1)

THEOREM PhysicalGuardedAssignmentTablesDetermineTheCompleteOutcome ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings,
           NEW raw, RenderedAssignmentInventory(rows, before, raw),
           NEW history, AssignmentListHistory(FALSE, before, rows, history)
    PROVE \A end \in 0..Len(rows) : RenderedAssignmentHistoryAt(rows, before, raw, history, end)
PROOF
<1>. DEFINE count == Len(rows)
            holds(end) == RenderedAssignmentHistoryAt(rows, before, raw, history, end)
<1>shape. /\ count \in Nat /\ DOMAIN rows = 1..count
    BY SMT DEF SupportedAssignmentList, count
<1>meaning. \A end \in 0..count : AssignmentPrefixMeaning(before, rows, history, end)
    BY OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix DEF count
<1>zero. holds(0)
    BY SMT DEF holds, RenderedAssignmentHistoryAt, AssignmentListHistory, AssignmentListStart, HistoryPrefix
<1>advance. ASSUME NEW end \in 1..count, \A earlier \in 0..(end - 1) : holds(earlier)
            PROVE holds(end)
    <2>. DEFINE prior == history[end - 1]
                current == history[end]
                plan == raw.plans[end]
                rhs == SourceAssignmentRHS(rows[end], prior.bindings)
    <2>previous. /\ holds(end - 1)
                 /\ AssignmentPrefixMeaning(before, rows, history, end - 1)
                 /\ prior.completed \in Seq(AssignmentIntValues)
                 /\ current = AssignmentListStep(FALSE, prior, rows[end], end)
        BY <1>meaning, <1>shape, (end \in 1..count), (\A earlier \in 0..(end - 1) : holds(earlier)), SMT
            DEF AssignmentListHistory, AssignmentPrefixStates, prior, current, count
    <2>reached. RenderedAssignmentsPass(raw, end - 1) =>
        /\ prior.failure = <<>>
        /\ prior.completed = HistoryPrefix(raw.roots, end - 1)
        /\ Len(prior.completed) = end - 1
        /\ prior.bindings = CompletedAssignmentBindings(before, rows, prior.completed)
        BY <2>previous, SMT DEF holds, RenderedAssignmentHistoryAt, AssignmentPrefixMeaning, prior
    <2>local. RenderedAssignmentsPass(raw, end - 1) =>
        /\ (EveryRenderedGuardPasses(raw.guards[end], plan.count) => rhs = Success(raw.roots[end]))
        /\ \A node \in 1..plan.count : FirstRejectedRenderedGuard(raw.guards[end], plan.count, node) =>
              /\ plan.kinds[node] = "add"
              /\ rhs = RenderedTermOverflow(plan, raw.terms[end], node)
        <3>. SUFFICES ASSUME RenderedAssignmentsPass(raw, end - 1)
           PROVE /\ (EveryRenderedGuardPasses(raw.guards[end], plan.count) => rhs = Success(raw.roots[end]))
                 /\ \A node \in 1..plan.count : FirstRejectedRenderedGuard(raw.guards[end], plan.count, node) =>
                          /\ plan.kinds[node] = "add"
                          /\ rhs = RenderedTermOverflow(plan, raw.terms[end], node)
            OBVIOUS
        <3>inventory. /\ PhysicalAssignmentReadsMatchRoutes(rows, end, plan)
                      /\ RenderedRhsTerms(plan, before, prior.completed, raw.starts[end], raw.terms[end])
                      /\ RenderedRhsGuards(plan, raw.terms[end], raw.guards[end])
                      /\ raw.roots[end] = raw.terms[end][plan.count]
            BY <1>shape, <2>reached, (end \in 1..count), RenderedAssignmentsPass(raw, end - 1), SMT
                DEF RenderedAssignmentInventory, plan
        <3>. QED BY <2>previous, <2>reached, <3>inventory, (end \in 1..count), RenderedAssignmentsPass(raw, end - 1),
            RenderedReachedRhsHasCertifiedObservation, SMT DEF rhs, count
    <2>passed. RenderedAssignmentsPass(raw, end) =>
                 current.failure = <<>> /\ current.completed = HistoryPrefix(raw.roots, end)
        <3>. SUFFICES ASSUME RenderedAssignmentsPass(raw, end)
            PROVE current.failure = <<>> /\ current.completed = HistoryPrefix(raw.roots, end)
            OBVIOUS
        <3>earlier. /\ RenderedAssignmentsPass(raw, end - 1)
                     /\ EveryRenderedGuardPasses(raw.guards[end], plan.count)
            BY RenderedAssignmentsPass(raw, end), (end \in 1..count), SMT DEF RenderedAssignmentsPass, plan
        <3>append. Append(prior.completed, raw.roots[end]) = HistoryPrefix(raw.roots, end)
            BY <2>previous, <2>reached, <3>earlier, (end \in 1..count), AppendProperties, SMT DEF HistoryPrefix
        <3>. QED BY <2>previous, <2>reached, <2>local, <3>earlier, <3>append, SMT DEF AssignmentListStep, Success
    <2>failed. \A index \in 1..end : \A node \in 1..raw.plans[index].count :
           RenderedAssignmentFailsAt(raw, end, index, node) =>
               /\ raw.plans[index].kinds[node] = "add"
               /\ current.failure = RenderedAssignmentFailure(rows, before, raw, index, node)
               /\ current.completed = HistoryPrefix(raw.roots, index - 1)
        <3>. SUFFICES ASSUME NEW index \in 1..end, NEW node \in 1..raw.plans[index].count,
                             RenderedAssignmentFailsAt(raw, end, index, node)
            PROVE /\ raw.plans[index].kinds[node] = "add"
                  /\ current.failure = RenderedAssignmentFailure(rows, before, raw, index, node)
                  /\ current.completed = HistoryPrefix(raw.roots, index - 1)
            OBVIOUS
        <3>this. CASE index = end
            BY <3>this, <2>previous, <2>reached, <2>local, RenderedAssignmentFailsAt(raw, end, index, node), SMT
                DEF RenderedAssignmentFailsAt, RenderedAssignmentFailure, AssignmentListStep,
                    RenderedTermOverflow, GeneratedOverflow, plan
        <3>earlier. CASE index < end
            <4>seen. /\ raw.plans[index].kinds[node] = "add"
                     /\ prior.failure = RenderedAssignmentFailure(rows, before, raw, index, node)
                     /\ prior.completed = HistoryPrefix(raw.roots, index - 1)
                BY <3>earlier, <2>previous, RenderedAssignmentFailsAt(raw, end, index, node), SMT
                    DEF holds, RenderedAssignmentHistoryAt, RenderedAssignmentFailsAt, prior
            <4>frozen. current = prior
                BY <4>seen, <2>previous, SMT DEF RenderedAssignmentFailure, AssignmentListStep
            <4>. QED BY <4>seen, <4>frozen
        <3>. QED BY <3>this, <3>earlier, (index \in 1..end), SMT
    <2>. QED BY <2>passed, <2>failed DEF holds, RenderedAssignmentHistoryAt, current
<1>. HIDE DEF holds
<1>all. \A end \in 0..count : holds(end)
    BY <1>shape, <1>zero, <1>advance, FiniteIndexedPrefixProperty, Isa
<1>. QED BY <1>all DEF holds, count

THEOREM EveryFiniteGuardFailureHasAFirstPosition ==
    ASSUME NEW count \in Nat, NEW guards, ~EveryRenderedGuardPasses(guards, count)
    PROVE \E index \in 1..count : FirstRejectedRenderedGuard(guards, count, index)
PROOF
<1>. DEFINE prefix(end) ==
        EveryRenderedGuardPasses(guards, end) \/
        (\E index \in 1..end : FirstRejectedRenderedGuard(guards, end, index))
<1>zero. prefix(0)
    BY SMT DEF prefix, EveryRenderedGuardPasses
<1>step. ASSUME NEW end \in 1..count, \A earlier \in 0..(end - 1) : prefix(earlier)
         PROVE prefix(end)
    <2>prior. prefix(end - 1)
        BY (end \in 1..count), (\A earlier \in 0..(end - 1) : prefix(earlier)), SMT
    <2>passed. CASE EveryRenderedGuardPasses(guards, end - 1)
        BY <2>passed, (end \in 1..count), SMT DEF prefix, EveryRenderedGuardPasses, FirstRejectedRenderedGuard
    <2>failed. CASE ~EveryRenderedGuardPasses(guards, end - 1)
        BY <2>failed, <2>prior, (end \in 1..count), SMT DEF prefix, FirstRejectedRenderedGuard
    <2>. QED BY <2>passed, <2>failed, SMT
<1>. HIDE DEF prefix
<1>all. \A end \in 0..count : prefix(end)
    BY (count \in Nat), <1>zero, <1>step, FiniteIndexedPrefixProperty, Isa
<1>. QED BY <1>all, (count \in Nat), ~EveryRenderedGuardPasses(guards, count), SMT DEF prefix

THEOREM WholeGuardTableHasAnExactFirstFailureSite ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before, NEW raw,
           RenderedAssignmentInventory(rows, before, raw)
    PROVE ~RenderedAssignmentsPass(raw, Len(rows)) <=>
         (\E index \in 1..Len(rows) : \E node \in 1..raw.plans[index].count :
              RenderedAssignmentFailsAt(raw, Len(rows), index, node))
PROOF
<1>. DEFINE count == Len(rows)
            guards == [index \in 1..count |-> EveryRenderedGuardPasses(raw.guards[index], raw.plans[index].count)]
<1>shape. /\ count \in Nat /\ DOMAIN rows = 1..count
    BY SMT DEF SupportedAssignmentList, count
<1>first. ASSUME ~RenderedAssignmentsPass(raw, count)
          PROVE \E index \in 1..count : \E node \in 1..raw.plans[index].count :
                    RenderedAssignmentFailsAt(raw, count, index, node)
    <2>chosen. PICK index \in 1..count : FirstRejectedRenderedGuard(guards, count, index)
        BY <1>shape, ~RenderedAssignmentsPass(raw, count), EveryFiniteGuardFailureHasAFirstPosition, SMT
            DEF RenderedAssignmentsPass, EveryRenderedGuardPasses, guards
    <2>count. /\ raw.plans[index].count \in Nat
              /\ ~EveryRenderedGuardPasses(raw.guards[index], raw.plans[index].count)
              /\ RenderedAssignmentsPass(raw, index - 1)
        BY <1>shape, <2>chosen, SMT DEF guards, FirstRejectedRenderedGuard, RenderedAssignmentsPass,
            EveryRenderedGuardPasses, RenderedAssignmentInventory, RenderedRhsTerms
    <2>node. PICK node \in 1..raw.plans[index].count :
                   FirstRejectedRenderedGuard(raw.guards[index], raw.plans[index].count, node)
        BY <2>count, EveryFiniteGuardFailureHasAFirstPosition
    <2>. QED BY <2>chosen, <2>count, <2>node, SMT DEF RenderedAssignmentFailsAt
<1>some. ASSUME \E index \in 1..count : \E node \in 1..raw.plans[index].count :
                  RenderedAssignmentFailsAt(raw, count, index, node)
         PROVE ~RenderedAssignmentsPass(raw, count)
    BY SMT DEF RenderedAssignmentsPass, RenderedAssignmentFailsAt, EveryRenderedGuardPasses, FirstRejectedRenderedGuard
<1>. QED BY <1>first, <1>some DEF count

====
