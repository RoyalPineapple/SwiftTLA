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

RenderedAssignmentTablesAgreeOnPrefix(prefixRows, raw, prefixRaw) ==
    \A index \in DOMAIN prefixRows :
        /\ prefixRaw.plans[index] = raw.plans[index]
        /\ prefixRaw.starts[index] = raw.starts[index]
        /\ prefixRaw.terms[index] = raw.terms[index]
        /\ prefixRaw.guards[index] = raw.guards[index]
        /\ prefixRaw.roots[index] = raw.roots[index]

THEOREM RenderedAssignmentInventoryRestrictsToPrefix ==
    ASSUME NEW rows, NEW prefixRows, AssignmentRhsRowsArePrefix(rows, prefixRows),
           NEW before, NEW raw, RenderedAssignmentInventory(rows, before, raw),
           NEW prefixRaw, RenderedAssignmentTablesAgreeOnPrefix(prefixRows, raw, prefixRaw)
    PROVE RenderedAssignmentInventory(prefixRows, before, prefixRaw)
PROOF
<1>shape. /\ Len(prefixRows) \in Nat /\ DOMAIN prefixRows = 1..Len(prefixRows)
          /\ DOMAIN prefixRows \subseteq DOMAIN rows
    BY ONLY AssignmentRhsRowsArePrefix(rows, prefixRows), SMT DEF AssignmentRhsRowsArePrefix
<1>fullReads. \A index \in DOMAIN rows : PhysicalAssignmentReadsMatchRoutes(rows, index, raw.plans[index])
    BY ONLY RenderedAssignmentInventory(rows, before, raw) DEF RenderedAssignmentInventory
<1>plans. \A index \in DOMAIN prefixRows : prefixRaw.plans[index] = raw.plans[index]
    BY ONLY RenderedAssignmentTablesAgreeOnPrefix(prefixRows, raw, prefixRaw) DEF RenderedAssignmentTablesAgreeOnPrefix
<1>prefixReads. \A index \in DOMAIN prefixRows :
    PhysicalAssignmentReadsMatchRoutes(prefixRows, index, prefixRaw.plans[index])
    BY ONLY AssignmentRhsRowsArePrefix(rows, prefixRows), <1>fullReads, <1>plans,
        PhysicalAssignmentReadsRestrictToPrefix
<1>inventory. \A index \in DOMAIN prefixRows :
    LET plan == prefixRaw.plans[index]
    IN /\ PhysicalAssignmentReadsMatchRoutes(prefixRows, index, plan)
       /\ RenderedRhsTerms(plan, before, HistoryPrefix(prefixRaw.roots, index - 1),
                          prefixRaw.starts[index], prefixRaw.terms[index])
       /\ RenderedRhsGuards(plan, prefixRaw.terms[index], prefixRaw.guards[index])
       /\ prefixRaw.roots[index] = prefixRaw.terms[index][plan.count]
    <2>. TAKE index \in DOMAIN prefixRows
    <2>bounds. /\ index \in DOMAIN rows /\ 1..(index - 1) \subseteq DOMAIN prefixRows
        BY ONLY <1>shape, (index \in DOMAIN prefixRows), SMT
    <2>raw. /\ prefixRaw.plans[index] = raw.plans[index]
            /\ prefixRaw.starts[index] = raw.starts[index]
            /\ prefixRaw.terms[index] = raw.terms[index]
            /\ prefixRaw.guards[index] = raw.guards[index]
            /\ prefixRaw.roots[index] = raw.roots[index]
        BY ONLY (index \in DOMAIN prefixRows), RenderedAssignmentTablesAgreeOnPrefix(prefixRows, raw, prefixRaw), SMT
            DEF RenderedAssignmentTablesAgreeOnPrefix
    <2>completed. HistoryPrefix(prefixRaw.roots, index - 1) = HistoryPrefix(raw.roots, index - 1)
        BY ONLY <2>bounds, RenderedAssignmentTablesAgreeOnPrefix(prefixRows, raw, prefixRaw), SMT
            DEF RenderedAssignmentTablesAgreeOnPrefix, HistoryPrefix
    <2>full. LET plan == raw.plans[index]
             IN /\ RenderedRhsTerms(plan, before, HistoryPrefix(raw.roots, index - 1),
                                    raw.starts[index], raw.terms[index])
                /\ RenderedRhsGuards(plan, raw.terms[index], raw.guards[index])
                /\ raw.roots[index] = raw.terms[index][plan.count]
        BY ONLY <2>bounds, RenderedAssignmentInventory(rows, before, raw), SMT DEF RenderedAssignmentInventory
    <2>. QED BY ONLY <1>prefixReads, (index \in DOMAIN prefixRows), <2>raw, <2>completed, <2>full, SMT
<1>. QED BY ONLY <1>inventory DEF RenderedAssignmentInventory

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
            <4>. DEFINE values == AssignmentIntValues \cup {raw.roots[end]}
                        added == Append(prior.completed, raw.roots[end])
            <4>input. prior.completed \in Seq(values) /\ raw.roots[end] \in values
                BY ONLY <2>previous, SeqMonotonic, SMT DEF values
            <4>prefix. /\ Len(prior.completed) = end - 1
                       /\ prior.completed = HistoryPrefix(raw.roots, end - 1)
                BY ONLY <2>reached, <3>earlier, SMT
            <4>slots. /\ added \in Seq(values) /\ Len(added) = end
                      /\ added[end] = raw.roots[end]
                      /\ \A index \in 1..(end - 1) : added[index] = prior.completed[index]
                BY ONLY <4>input, <4>prefix, AppendProperties, SMT DEF added
            <4>function. added \in [1..end -> values]
                BY ONLY <4>slots, LenProperties, SMT
            <4>. QED BY ONLY <1>shape, (end \in 1..count), <4>prefix, <4>slots, <4>function, SMT
                DEF HistoryPrefix, added
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
            <4>guards. /\ RenderedAssignmentsPass(raw, end - 1)
                       /\ FirstRejectedRenderedGuard(raw.guards[end], plan.count, node)
                BY ONLY <3>this, RenderedAssignmentFailsAt(raw, end, index, node), SMT
                    DEF RenderedAssignmentFailsAt, plan
            <4>entry. /\ prior.failure = <<>>
                      /\ prior.completed = HistoryPrefix(raw.roots, end - 1)
                      /\ prior.bindings = CompletedAssignmentBindings(before, rows, prior.completed)
                BY ONLY <2>reached, <4>guards, SMT
            <4>kind. /\ plan.kinds[node] = "add" /\ rhs = RenderedTermOverflow(plan, raw.terms[end], node)
                BY ONLY <3>this, <4>guards, <2>local, (node \in 1..raw.plans[index].count), SMT DEF plan
            <4>payload. /\ ~rhs.ok /\ rhs.failure = RenderedTermOverflow(plan, raw.terms[end], node).failure
                BY ONLY <4>kind, SMT DEF RenderedTermOverflow, GeneratedOverflow
            <4>transition. /\ current.completed = prior.completed
                           /\ current.failure = [before |-> prior.bindings, site |-> end, payload |-> rhs.failure]
                <5>live. prior.failure = <<>> /\ ~rhs.ok
                    BY ONLY <4>entry, <4>payload
                <5>step. current = AssignmentListStep(FALSE, prior, rows[end], end)
                    BY ONLY <2>previous
                <5>record. AssignmentListStep(FALSE, prior, rows[end], end) =
                    [bindings |-> prior.bindings, completed |-> prior.completed,
                     failure |-> [before |-> prior.bindings, site |-> end, payload |-> rhs.failure]]
                    BY ONLY <5>live, SMT DEF AssignmentListStep, rhs
                <5>current. current =
                    [bindings |-> prior.bindings, completed |-> prior.completed,
                     failure |-> [before |-> prior.bindings, site |-> end, payload |-> rhs.failure]]
                    BY ONLY <5>step, <5>record, Zenon
                <5>. QED BY ONLY <5>current, IsaM("simp")
            <4>. QED BY ONLY <3>this, <4>entry, <4>kind, <4>payload, <4>transition, SMT
                DEF RenderedAssignmentFailure, plan
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
<1>. DEFINE rejected(node) == node \in 1..count /\ ~guards[node]
<1>some. PICK candidate \in Nat : rejected(candidate)
    BY ONLY (count \in Nat), ~EveryRenderedGuardPasses(guards, count), SMT DEF rejected, EveryRenderedGuardPasses
<1>. HIDE DEF rejected
<1>first. PICK least \in Nat :
             rejected(least) /\ \A earlier \in 0..(least - 1) : ~rejected(earlier)
    BY ONLY <1>some, SmallestNatural
<1>bounds. least \in 1..count /\ ~guards[least]
    BY ONLY <1>first DEF rejected
<1>prior. EveryRenderedGuardPasses(guards, least - 1)
    BY ONLY <1>first, <1>bounds, SMT DEF rejected, EveryRenderedGuardPasses
<1>site. FirstRejectedRenderedGuard(guards, count, least)
    BY ONLY <1>bounds, <1>prior DEF FirstRejectedRenderedGuard
<1>. QED BY ONLY <1>bounds, <1>site, Zenon

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
    <2>site. PICK index \in 1..count : \E node \in 1..raw.plans[index].count :
                 RenderedAssignmentFailsAt(raw, count, index, node)
        BY ONLY (\E index \in 1..count : \E node \in 1..raw.plans[index].count :
                     RenderedAssignmentFailsAt(raw, count, index, node))
    <2>node. PICK node \in 1..raw.plans[index].count : RenderedAssignmentFailsAt(raw, count, index, node)
        BY ONLY <2>site
    <2>reject. ~raw.guards[index][node]
        BY ONLY <2>node DEF RenderedAssignmentFailsAt, FirstRejectedRenderedGuard
    <2>. QED BY ONLY (index \in 1..count), (node \in 1..raw.plans[index].count), <2>reject, SMT
        DEF RenderedAssignmentsPass, EveryRenderedGuardPasses
<1>. QED BY <1>first, <1>some DEF count

THEOREM RenderedAssignmentFailurePositionIsUnique ==
    ASSUME NEW raw, NEW end, NEW a, NEW i, NEW b, NEW j,
           RenderedAssignmentFailsAt(raw, end, a, i),
           RenderedAssignmentFailsAt(raw, end, b, j)
    PROVE a = b /\ i = j
PROOF
<1>a. /\ a \in 1..end /\ i \in 1..raw.plans[a].count /\ ~raw.guards[a][i]
      /\ RenderedAssignmentsPass(raw, a - 1)
      /\ EveryRenderedGuardPasses(raw.guards[a], i - 1)
    BY ONLY RenderedAssignmentFailsAt(raw, end, a, i)
        DEF RenderedAssignmentFailsAt, FirstRejectedRenderedGuard
<1>b. /\ b \in 1..end /\ j \in 1..raw.plans[b].count /\ ~raw.guards[b][j]
      /\ RenderedAssignmentsPass(raw, b - 1)
      /\ EveryRenderedGuardPasses(raw.guards[b], j - 1)
    BY ONLY RenderedAssignmentFailsAt(raw, end, b, j)
        DEF RenderedAssignmentFailsAt, FirstRejectedRenderedGuard
<1>row. a = b
    <2>ab. a < b => a \in 1..(b - 1)
        BY ONLY <1>a, <1>b, SMT
    <2>ba. b < a => b \in 1..(a - 1)
        BY ONLY <1>a, <1>b, SMT
    <2>notEarlier. ~(a < b)
        BY ONLY <1>a, <1>b, <2>ab, SMT
            DEF RenderedAssignmentsPass, EveryRenderedGuardPasses
    <2>notLater. ~(b < a)
        BY ONLY <1>a, <1>b, <2>ba, SMT
            DEF RenderedAssignmentsPass, EveryRenderedGuardPasses
    <2>. QED BY ONLY <1>a, <1>b, <2>notEarlier, <2>notLater, SMT
<1>node. i = j
    <2>bounds. /\ (i < j => i \in 1..(j - 1)) /\ (j < i => j \in 1..(i - 1))
        BY ONLY <1>a, <1>b, SMT
    <2>. QED BY ONLY <1>row, <1>a, <1>b, <2>bounds, SMT DEF EveryRenderedGuardPasses
<1>. QED BY ONLY <1>row, <1>node

====
