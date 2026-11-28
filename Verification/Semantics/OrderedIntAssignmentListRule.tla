---- MODULE OrderedIntAssignmentListRule ----
EXTENDS OrderedIntExpressionRule, OrderedScalarCopyRule, SequenceTheorems

AssignmentIntValues == SwiftIntMin..SwiftIntMax
AssignmentBindings == [Keys -> AssignmentIntValues]
AssignmentFailureEvents == [before: AssignmentBindings, site: Nat \ {0}, payload: ArithmeticFailures]
AssignmentPrefixStates ==
    [bindings: AssignmentBindings, completed: Seq(AssignmentIntValues),
     failure: {<<>>} \cup AssignmentFailureEvents]

AssignmentRhsCertificate(row) ==
    LiteralReadAddCertificate(row.view, row.emitted, row.inverse, row.fallback, Keys)

SupportedAssignmentList(rows) ==
    /\ Len(rows) \in Nat
    /\ DOMAIN rows = 1..Len(rows)
    /\ \A index \in DOMAIN rows : rows[index].target \in Keys /\ AssignmentRhsCertificate(rows[index])

SourceAssignmentRHS(row, bindings) ==
    LET meaning == CHOOSE history : SourceSyntaxHistory(row.view, bindings, history)
    IN meaning[row.view.root]

AssignmentRhsPlan(row) == ExtractedNodePlan(row.emitted, row.fallback)

GeneratedAssignmentRhsHistory(row, bindings, history) ==
    LET plan == AssignmentRhsPlan(row)
    IN GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
           plan.reads, plan.left, plan.right, bindings, history)

GeneratedAssignmentRHS(row, bindings) ==
    LET history == CHOOSE witness : GeneratedAssignmentRhsHistory(row, bindings, witness)
    IN history[AssignmentRhsPlan(row).count]

THEOREM CertifiedAssignmentRhsConstructsBothMeanings ==
    ASSUME NEW row, AssignmentRhsCertificate(row), NEW bindings \in AssignmentBindings
    PROVE /\ SourceAssignmentRHS(row, bindings) \in ExpressionOutcomes
          /\ SourceAssignmentRHS(row, bindings) = GeneratedAssignmentRHS(row, bindings)
          /\ \A history : GeneratedAssignmentRhsHistory(row, bindings, history) =>
                    history[AssignmentRhsPlan(row).count] = SourceAssignmentRHS(row, bindings)
    PROOF
    <1>. DEFINE plan == AssignmentRhsPlan(row)
                src(history) == SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                    plan.reads, plan.left, plan.right, bindings, history)
    <1>certificate. /\ PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
                              plan.reads, plan.left, plan.right, Keys, bindings)
                    /\ \A source : src(source) =>
                        /\ \E meaning : SourceSyntaxHistory(row.view, bindings, meaning)
                        /\ \A meaning : SourceSyntaxHistory(row.view, bindings, meaning) =>
                             source[plan.count] = meaning[row.view.root]
                    /\ \E source, generated : src(source) /\ GeneratedAssignmentRhsHistory(row, bindings, generated)
        BY LiteralReadAddCertificateSuppliesExpressionParent, SMT
            DEF AssignmentRhsCertificate, plan, AssignmentRhsPlan, AssignmentBindings, AssignmentIntValues,
                src, GeneratedAssignmentRhsHistory
    <1>source. PICK source : src(source)
        BY ONLY <1>certificate, SMT
    <1>meaning. SourceSyntaxHistory(row.view, bindings,
                      CHOOSE history : SourceSyntaxHistory(row.view, bindings, history))
        BY ONLY <1>certificate, <1>source, SMT
    <1>root. source[plan.count] = SourceAssignmentRHS(row, bindings)
        BY ONLY <1>certificate, <1>source, <1>meaning, SMT DEF SourceAssignmentRHS
    <1>count. plan.count \in 0..plan.count
        BY ONLY <1>certificate, SMT DEF PartialExpressionPlan, ExpressionPlan
    <1>arbitrary. \A generated : GeneratedAssignmentRhsHistory(row, bindings, generated) =>
                    /\ source[plan.count] = generated[plan.count]
                    /\ source[plan.count] \in ExpressionOutcomes
        <2>. SUFFICES ASSUME NEW generated, GeneratedAssignmentRhsHistory(row, bindings, generated)
                     PROVE /\ source[plan.count] = generated[plan.count]
                           /\ source[plan.count] \in ExpressionOutcomes
            OBVIOUS
        <2>all. \A index \in 0..plan.count :
                  /\ OutcomeAgrees(source, generated, index)
                  /\ source[index] \in ExpressionOutcomes
                  /\ generated[index] \in ExpressionOutcomes
            BY ONLY <1>certificate, <1>source, GeneratedAssignmentRhsHistory(row, bindings, generated),
                AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT DEF src, plan, GeneratedAssignmentRhsHistory
        <2>. QED BY ONLY <2>all, <1>count, SMT DEF OutcomeAgrees
    <1>selected. GeneratedAssignmentRhsHistory(row, bindings,
                     CHOOSE history : GeneratedAssignmentRhsHistory(row, bindings, history))
        BY ONLY <1>certificate, SMT
    <1>. QED BY ONLY <1>selected, <1>arbitrary, <1>root, SMT DEF plan, GeneratedAssignmentRHS

AssignmentListStart(before) == [bindings |-> before, completed |-> <<>>, failure |-> <<>>]

AssignmentListStep(generated, state, row, index) ==
    IF state.failure # <<>> THEN state
    ELSE
        LET outcome == IF generated THEN GeneratedAssignmentRHS(row, state.bindings)
                      ELSE SourceAssignmentRHS(row, state.bindings)
        IN IF outcome.ok
           THEN [bindings |-> CopyReplace(Keys, state.bindings, row.target, outcome.value),
                 completed |-> Append(state.completed, outcome.value), failure |-> <<>>]
           ELSE [bindings |-> state.bindings, completed |-> state.completed,
                 failure |-> [before |-> state.bindings, site |-> index, payload |-> outcome.failure]]

THEOREM CertifiedAssignmentStepIsTypedAndShared ==
    ASSUME NEW row, row.target \in Keys, AssignmentRhsCertificate(row),
           NEW index \in Nat \ {0}, NEW state \in AssignmentPrefixStates
    PROVE /\ AssignmentListStep(FALSE, state, row, index) \in AssignmentPrefixStates
          /\ AssignmentListStep(TRUE, state, row, index) = AssignmentListStep(FALSE, state, row, index)
    PROOF
    <1>typed. /\ state.bindings \in AssignmentBindings
              /\ state.completed \in Seq(AssignmentIntValues)
        BY SMT DEF AssignmentPrefixStates
    <1>. DEFINE outcome == SourceAssignmentRHS(row, state.bindings)
    <1>expression. outcome \in ExpressionOutcomes /\ outcome = GeneratedAssignmentRHS(row, state.bindings)
        BY ONLY <1>typed, (AssignmentRhsCertificate(row)), CertifiedAssignmentRhsConstructsBothMeanings, SMT DEF outcome
    <1>ok. outcome.ok =>
        /\ CopyReplace(Keys, state.bindings, row.target, outcome.value) \in AssignmentBindings
        /\ Append(state.completed, outcome.value) \in Seq(AssignmentIntValues)
        PROOF
        <2>. SUFFICES ASSUME outcome.ok
                     PROVE /\ CopyReplace(Keys, state.bindings, row.target, outcome.value) \in AssignmentBindings
                           /\ Append(state.completed, outcome.value) \in Seq(AssignmentIntValues)
            OBVIOUS
        <2>value. outcome.value \in AssignmentIntValues
            BY ONLY <1>expression, (outcome.ok), SMT DEF ExpressionOutcomes, AssignmentIntValues
        <2>bindings. CopyReplace(Keys, state.bindings, row.target, outcome.value) \in AssignmentBindings
            BY ONLY <2>value, <1>typed, (row.target \in Keys), SMT DEF AssignmentBindings, CopyReplace
        <2>append. Append(state.completed, outcome.value) \in Seq(AssignmentIntValues)
            BY ONLY <2>value, <1>typed, AppendProperties, SMT
        <2>. QED BY ONLY <2>bindings, <2>append
    <1>failed. ~outcome.ok => [before |-> state.bindings, site |-> index, payload |-> outcome.failure] \in AssignmentFailureEvents
        BY ONLY <1>typed, <1>expression, (index \in Nat \ {0}), SMT DEF AssignmentFailureEvents, ExpressionOutcomes
    <1>same. AssignmentListStep(TRUE, state, row, index) = AssignmentListStep(FALSE, state, row, index)
        BY ONLY <1>expression, SMT DEF AssignmentListStep, outcome
    <1>stopped. CASE state.failure # <<>>
        BY ONLY <1>stopped, (state \in AssignmentPrefixStates), SMT DEF AssignmentListStep
    <1>succeeded. CASE state.failure = <<>> /\ outcome.ok
        <2>record. AssignmentListStep(FALSE, state, row, index) =
            [bindings |-> CopyReplace(Keys, state.bindings, row.target, outcome.value),
             completed |-> Append(state.completed, outcome.value), failure |-> <<>>]
            BY ONLY <1>succeeded, SMT DEF AssignmentListStep, outcome
        <2>. QED BY ONLY <1>same, <1>succeeded, <1>ok, <2>record, SMT DEF AssignmentPrefixStates
    <1>overflow. CASE state.failure = <<>> /\ ~outcome.ok
        <2>notOk. outcome.ok = FALSE
            BY ONLY <1>overflow, <1>expression, SMT DEF ExpressionOutcomes
        <2>. DEFINE fault == [before |-> state.bindings, site |-> index, payload |-> outcome.failure]
        <2>record. AssignmentListStep(FALSE, state, row, index) =
            [bindings |-> state.bindings, completed |-> state.completed, failure |-> fault]
            BY ONLY <1>overflow, <2>notOk, SMT DEF AssignmentListStep, outcome, fault
        <2>event. fault \in AssignmentFailureEvents
            BY ONLY <1>overflow, <1>failed, SMT DEF fault
        <2>. HIDE DEF fault
        <2>typed. [bindings |-> state.bindings, completed |-> state.completed, failure |-> fault] \in AssignmentPrefixStates
            BY ONLY <1>typed, <2>event, SMT DEF AssignmentPrefixStates
        <2>. QED BY ONLY <1>same, <2>record, <2>typed, SMT
    <1>. QED BY ONLY <1>same, <1>stopped, <1>succeeded, <1>overflow, SMT

AssignmentListHistory(generated, before, rows, history) ==
    /\ history \in [0..Len(rows) -> AssignmentPrefixStates]
    /\ history[0] = AssignmentListStart(before)
    /\ \A index \in 1..Len(rows) :
           history[index] = AssignmentListStep(generated, history[index - 1], rows[index], index)

THEOREM CertifiedAssignmentListsConstructTheirHistories ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings
    PROVE \E history : AssignmentListHistory(FALSE, before, rows, history) /\ AssignmentListHistory(TRUE, before, rows, history)
    PROOF
    <1>. DEFINE count == Len(rows)
                start == AssignmentListStart(before)
                steps == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> AssignmentPrefixStates] |->
                        AssignmentListStep(FALSE, IF index = 1 THEN start ELSE prefix[index - 1], rows[index], index)]]
    <1>shape. /\ count \in Nat /\ DOMAIN rows = 1..count
              /\ \A index \in 1..count : rows[index].target \in Keys /\ AssignmentRhsCertificate(rows[index])
        BY SMT DEF SupportedAssignmentList, count
    <1>start. start \in AssignmentPrefixStates
        BY (before \in AssignmentBindings), EmptySeq, SMT DEF start, AssignmentListStart, AssignmentPrefixStates
    <1>steps. \A index \in 1..count :
        steps[index] \in [[1..(index - 1) -> AssignmentPrefixStates] -> AssignmentPrefixStates]
        <2>. TAKE index \in 1..count
        <2>prefix. \A prefix \in [1..(index - 1) -> AssignmentPrefixStates] :
            (IF index = 1 THEN start ELSE prefix[index - 1]) \in AssignmentPrefixStates
            BY ONLY <1>start, (index \in 1..count), SMT
        <2>facts. /\ index \in Nat \ {0} /\ rows[index].target \in Keys /\ AssignmentRhsCertificate(rows[index])
            BY ONLY <1>shape, (index \in 1..count), SMT
        <2>range. \A prefix \in [1..(index - 1) -> AssignmentPrefixStates] :
            AssignmentListStep(FALSE, IF index = 1 THEN start ELSE prefix[index - 1], rows[index], index)
                \in AssignmentPrefixStates
            BY ONLY <2>prefix, <2>facts, CertifiedAssignmentStepIsTypedAndShared, SMT
        <2>. QED BY ONLY <2>range, (index \in 1..count), SMT DEF steps
    <1>. HIDE DEF steps
    <1>count. count \in Nat
        BY ONLY <1>shape
    <1>indexed. PICK indexed \in [1..count -> AssignmentPrefixStates] : IndexedHistory(steps, indexed, count)
        BY ONLY <1>count, <1>steps, FiniteIndexedHistoryExists, Zenon
    <1>. DEFINE history == [index \in 0..count |-> IF index = 0 THEN start ELSE indexed[index]]
    <1>history. /\ history \in [0..count -> AssignmentPrefixStates] /\ history[0] = start
        BY ONLY <1>indexed, <1>count, <1>start, SMT DEF history
    <1>advances. \A index \in 1..count :
        history[index] = AssignmentListStep(FALSE, history[index - 1], rows[index], index)
        <2>. TAKE index \in 1..count
        <2>. DEFINE prefix == HistoryPrefix(indexed, index - 1)
        <2>bounds. /\ index - 1 \in 0..count
                   /\ 1..(index - 1) \subseteq 1..count
                   /\ (index # 1 => index - 1 \in 1..(index - 1))
            BY ONLY <1>count, (index \in 1..count), SMT
        <2>entries. \A prior \in 1..(index - 1) : indexed[prior] \in AssignmentPrefixStates
            BY ONLY <1>indexed, <2>bounds, SMT
        <2>typed. prefix \in [1..(index - 1) -> AssignmentPrefixStates]
            BY ONLY <2>entries, SMT DEF prefix, HistoryPrefix
        <2>prior. (IF index = 1 THEN start ELSE prefix[index - 1]) = history[index - 1]
            BY ONLY <2>bounds, SMT DEF prefix, history, HistoryPrefix
        <2>stored. history[index] = steps[index][prefix]
            BY ONLY <1>indexed, (index \in 1..count), SMT DEF history, prefix, IndexedHistory
        <2>evaluated. steps[index][prefix] =
            AssignmentListStep(FALSE, history[index - 1], rows[index], index)
            BY ONLY <2>typed, <2>prior, (index \in 1..count), SMT DEF steps
        <2>. QED BY ONLY <2>stored, <2>evaluated
    <1>shared. \A index \in 1..count :
        AssignmentListStep(FALSE, history[index - 1], rows[index], index) =
        AssignmentListStep(TRUE, history[index - 1], rows[index], index)
        <2>. TAKE index \in 1..count
        <2>input. /\ index \in Nat \ {0} /\ rows[index].target \in Keys /\ AssignmentRhsCertificate(rows[index])
                  /\ history[index - 1] \in AssignmentPrefixStates
            BY ONLY <1>shape, <1>history, (index \in 1..count), SMT
        <2>. QED BY ONLY <2>input, CertifiedAssignmentStepIsTypedAndShared, SMT
    <1>source. AssignmentListHistory(FALSE, before, rows, history)
        BY ONLY <1>history, <1>advances, SMT DEF AssignmentListHistory, count, start
    <1>generated. AssignmentListHistory(TRUE, before, rows, history)
        BY ONLY <1>history, <1>advances, <1>shared, SMT DEF AssignmentListHistory, count, start
    <1>. QED BY ONLY <1>source, <1>generated, SMT

CompletedAssignmentBindings(before, rows, completed) ==
    CopyMaterializedState(Keys, before, completed, DirectCopyRoutes(Keys, rows)[Len(completed)])

THEOREM ReachedAssignmentRoutesUseOnlyEarlierCaptures ==
    ASSUME NEW rows, NEW prefix \in 0..Len(rows), Len(rows) \in Nat
    PROVE \A key \in Keys :
        LET route == DirectCopyRoutes(Keys, rows)[prefix][key]
        IN route[1] = "capture" => route[2] \in 1..prefix
    PROOF
    <1>. TAKE key \in Keys
    <1>. DEFINE writer == DirectCopyWriter(rows, prefix, key)
    <1>exists. \E position \in 0..prefix : LastDirectCopy(rows, prefix, key, position)
        BY ONLY (Len(rows) \in Nat), (prefix \in 0..Len(rows)), EveryFiniteCopyPrefixHasALastWriter, SMT
    <1>writer. writer \in 0..prefix
        BY ONLY <1>exists, SMT DEF writer, DirectCopyWriter
    <1>route. DirectCopyRoutes(Keys, rows)[prefix][key] = DirectCopyReference(key, writer)
        BY ONLY (prefix \in 0..Len(rows)), (key \in Keys), SMT DEF DirectCopyRoutes, writer
    <1>. QED BY ONLY <1>writer, <1>route, SMT DEF DirectCopyReference

THEOREM SuccessfulAssignmentExtendsExactlyTheLatestBindings ==
    ASSUME NEW before, NEW rows, Len(rows) \in Nat, NEW completed \in Seq(AssignmentIntValues),
           Len(completed) < Len(rows),
           \A index \in 1..Len(rows) : rows[index].target \in Keys,
           NEW value \in AssignmentIntValues
    PROVE CompletedAssignmentBindings(before, rows, Append(completed, value)) =
          CopyReplace(Keys, CompletedAssignmentBindings(before, rows, completed),
                      rows[Len(completed) + 1].target, value)
    PROOF
    <1>. DEFINE count == Len(completed)
                position == count + 1
                routes == DirectCopyRoutes(Keys, rows)
                added == Append(completed, value)
    <1>bounds. count \in 0..Len(rows) /\ position \in 1..Len(rows)
        BY LenProperties, SMT DEF count, position
    <1>append. /\ Len(added) = position /\ added[position] = value
               /\ \A earlier \in 1..count : added[earlier] = completed[earlier]
        BY AppendProperties DEF count, position, added
    <1>oldReads. CopyMaterializedState(Keys, before, added, routes[count]) =
                 CopyMaterializedState(Keys, before, completed, routes[count])
        BY ONLY <1>bounds, <1>append, (Len(rows) \in Nat), ReachedAssignmentRoutesUseOnlyEarlierCaptures, SMT
            DEF CopyMaterializedState, CopyReferenceValue, routes
    <1>route. routes[position] = CopyReplace(Keys, routes[count], rows[position].target, <<"capture", position>>)
        BY ONLY <1>bounds, (Len(rows) \in Nat), DirectCopyRoutesFollowEveryCapture, SMT DEF routes, position
    <1>target. rows[position].target \in Keys
        BY <1>bounds, SMT
    <1>updated. CopyMaterializedState(Keys, before, added, routes[position]) =
                    CopyReplace(Keys, CopyMaterializedState(Keys, before, added, routes[count]), rows[position].target, added[position])
        BY <1>route, <1>target, CopyMaterializationCommutesWithRecordingOneWrite, SMT
    <1>. QED BY ONLY <1>append, <1>oldReads, <1>updated, SMT DEF CompletedAssignmentBindings, routes, count, position, added

\* A successful list has one emitted state. A reached failure keeps the entry
\* state for invocation identity and the latest bindings and captures for its prefix.
OrderedAssignmentObservation(before, label, prefix) ==
    [source |-> before, action |-> label,
     successors |-> IF prefix.failure = <<>> THEN {prefix.bindings} ELSE {},
     selectedFailure |-> IF prefix.failure = <<>> THEN Success(0).failure ELSE prefix.failure.payload,
     disabled |-> FALSE]

AssignmentPrefixMeaning(before, rows, history, index) ==
    LET current == history[index]
        completed == Len(current.completed)
    IN /\ current.bindings = CompletedAssignmentBindings(before, rows, current.completed)
       /\ \A visit \in 1..completed :
              /\ history[visit - 1].failure = <<>>
              /\ SourceAssignmentRHS(rows[visit], history[visit - 1].bindings) = Success(current.completed[visit])
       /\ IF current.failure = <<>>
          THEN completed = index
          ELSE LET site == current.failure.site
                   prior == history[site - 1]
                   outcome == SourceAssignmentRHS(rows[site], prior.bindings)
               IN /\ site = completed + 1 /\ site \in 1..index
                  /\ prior.failure = <<>>
                  /\ prior.completed = current.completed
                  /\ prior.bindings = current.bindings
                  /\ current.failure.before = prior.bindings
                  /\ ~outcome.ok /\ current.failure.payload = outcome.failure

THEOREM OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings,
           NEW history, AssignmentListHistory(FALSE, before, rows, history)
    PROVE \A index \in 0..Len(rows) : AssignmentPrefixMeaning(before, rows, history, index)
    PROOF
    <1>. DEFINE count == Len(rows)
                holds(index) == AssignmentPrefixMeaning(before, rows, history, index)
    <1>shape. /\ count \in Nat /\ DOMAIN rows = 1..count
              /\ \A index \in 1..count : rows[index].target \in Keys /\ AssignmentRhsCertificate(rows[index])
              /\ history \in [0..count -> AssignmentPrefixStates]
        BY SMT DEF SupportedAssignmentList, AssignmentListHistory, count
    <1>initial. holds(0)
        PROOF
        <2>entries. CompletedAssignmentBindings(before, rows, <<>>) = before
            BY ONLY <1>shape, (before \in AssignmentBindings), DirectCopyRoutesFollowEveryCapture, SMT
                DEF CompletedAssignmentBindings, CopyMaterializedState, CopyEntryRoutes, CopyReferenceValue, AssignmentBindings, count
        <2>. QED BY <2>entries, SMT DEF AssignmentListHistory, AssignmentListStart, AssignmentPrefixMeaning, holds
    <1>step. \A index \in 1..count :
        (\A prior \in 0..(index - 1) : holds(prior)) => holds(index)
        <2>. SUFFICES ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : holds(prior)
                     PROVE holds(index)
            OBVIOUS
        <2>. DEFINE prior == history[index - 1]
                    current == history[index]
                    outcome == SourceAssignmentRHS(rows[index], prior.bindings)
        <2>previous. /\ holds(index - 1) /\ prior \in AssignmentPrefixStates
                      /\ index \in Nat \ {0}
            BY <1>shape, (index \in 1..count), (\A prior \in 0..(index - 1) : holds(prior)), SMT DEF prior
        <2>transition. current = AssignmentListStep(FALSE, prior, rows[index], index)
            BY AssignmentListHistory(FALSE, before, rows, history), (index \in 1..count), SMT
                DEF AssignmentListHistory, prior, current, count
        <2>stop. CASE prior.failure # <<>>
            BY <2>stop, <2>previous, <2>transition, (index \in 1..count), SMT
                DEF holds, AssignmentPrefixMeaning, AssignmentListStep, prior, current
        <2>live. CASE prior.failure = <<>>
            <3>values. /\ Len(prior.completed) = index - 1
                       /\ prior.completed \in Seq(AssignmentIntValues)
                       /\ prior.bindings \in AssignmentBindings
                BY ONLY <2>live, <2>previous, SMT
                    DEF holds, AssignmentPrefixMeaning, AssignmentPrefixStates, prior
            <3>expression. outcome \in ExpressionOutcomes
                BY ONLY <3>values, <1>shape, (index \in 1..count), CertifiedAssignmentRhsConstructsBothMeanings, SMT DEF outcome
            <3>failure. CASE ~outcome.ok
                <4>notOk. outcome.ok = FALSE
                    BY ONLY <3>expression, <3>failure, SMT DEF ExpressionOutcomes
                <4>. DEFINE failed == [before |-> prior.bindings, site |-> index, payload |-> outcome.failure]
                <4>selected. AssignmentListStep(FALSE, prior, rows[index], index) =
                    [bindings |-> prior.bindings, completed |-> prior.completed, failure |-> failed]
                    BY ONLY <4>notOk, <2>live, SMT DEF failed, outcome, AssignmentListStep
                <4>record. current = [bindings |-> prior.bindings, completed |-> prior.completed, failure |-> failed]
                    BY ONLY <2>transition, <4>selected
                <4>fields. /\ current.completed = prior.completed
                           /\ current.bindings = prior.bindings
                           /\ current.failure = [before |-> prior.bindings, site |-> index, payload |-> outcome.failure]
                    BY ONLY <4>record, IsaM("simp") DEF failed
                <4>prefix. /\ current.bindings = CompletedAssignmentBindings(before, rows, current.completed)
                           /\ \A visit \in 1..Len(current.completed) :
                                /\ history[visit - 1].failure = <<>>
                                /\ SourceAssignmentRHS(rows[visit], history[visit - 1].bindings) = Success(current.completed[visit])
                    BY ONLY <2>previous, <4>fields, SMT DEF holds, AssignmentPrefixMeaning, prior
                <4>failed. /\ current.failure # <<>>
                           /\ current.failure.site = Len(current.completed) + 1
                           /\ current.failure.site \in 1..index
                           /\ current.failure.before = prior.bindings
                           /\ current.failure.payload = outcome.failure
                           /\ current.failure.site = index
                    BY ONLY <4>fields, <3>values, (index \in 1..count), SMT
                <4>. QED BY ONLY <4>fields, <4>prefix, <4>failed, <3>failure, <2>live, SMT
                    DEF holds, AssignmentPrefixMeaning, current, prior, outcome
            <3>success. CASE outcome.ok
                <4>value. /\ outcome = Success(outcome.value) /\ outcome.value \in AssignmentIntValues
                    BY ONLY <3>expression, <3>success, SMT DEF ExpressionOutcomes, AssignmentIntValues, Success
                <4>append. /\ current.completed = Append(prior.completed, outcome.value)
                           /\ Len(current.completed) = index /\ current.completed[index] = outcome.value
                           /\ \A earlier \in 1..(index - 1) : current.completed[earlier] = prior.completed[earlier]
                    BY ONLY <2>transition, <2>live, <3>values, <3>success, <4>value, AppendProperties, SMT DEF outcome, AssignmentListStep
                <4>bindings. current.bindings = CompletedAssignmentBindings(before, rows, current.completed)
                    BY ONLY <1>shape, (index \in 1..count), <2>transition, <2>previous, <2>live, <3>values,
                        <3>success, <4>value, <4>append, SuccessfulAssignmentExtendsExactlyTheLatestBindings, SMT
                        DEF holds, AssignmentPrefixMeaning, AssignmentListStep, prior, current, outcome, count
                <4>prefix. \A visit \in 1..index :
                      /\ history[visit - 1].failure = <<>>
                      /\ SourceAssignmentRHS(rows[visit], history[visit - 1].bindings) = Success(current.completed[visit])
                    BY ONLY <2>previous, <2>live, <3>values, <4>value, <4>append, SMT
                        DEF holds, AssignmentPrefixMeaning, prior, outcome
                <4>. QED BY ONLY <2>transition, <2>live, <3>success, <4>append, <4>bindings, <4>prefix, SMT
                    DEF holds, AssignmentPrefixMeaning, AssignmentListStep, current, prior, outcome
            <3>. QED BY ONLY <3>failure, <3>success, SMT
        <2>. QED BY ONLY <2>stop, <2>live, SMT
    <1>. HIDE DEF holds
    <1>all. \A index \in 0..count : holds(index)
        BY ONLY <1>shape, <1>initial, <1>step, FiniteIndexedPrefixProperty, Isa
    <1>. QED BY ONLY <1>all DEF holds, count

THEOREM CertifiedAssignmentListHistoriesAgree ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings,
           NEW source, NEW generated,
           AssignmentListHistory(FALSE, before, rows, source),
           AssignmentListHistory(TRUE, before, rows, generated)
    PROVE /\ \A index \in 0..Len(rows) : source[index] = generated[index]
          /\ \A label : OrderedAssignmentObservation(before, label, source[Len(rows)]) =
                        OrderedAssignmentObservation(before, label, generated[Len(rows)])
    PROOF
    <1>. DEFINE count == Len(rows)
                agrees(index) == source[index] = generated[index]
    <1>shape. /\ count \in Nat
              /\ \A index \in 1..count : rows[index].target \in Keys /\ AssignmentRhsCertificate(rows[index])
              /\ source \in [0..count -> AssignmentPrefixStates]
        BY SMT DEF SupportedAssignmentList, AssignmentListHistory, count
    <1>entry. agrees(0)
        BY SMT DEF AssignmentListHistory, agrees
    <1>step. \A index \in 1..count : (\A earlier \in 0..(index - 1) : agrees(earlier)) => agrees(index)
        <2>. SUFFICES ASSUME NEW index \in 1..count, \A earlier \in 0..(index - 1) : agrees(earlier)
                     PROVE agrees(index)
            OBVIOUS
        <2>bounds. /\ index \in Nat \ {0} /\ index - 1 \in 0..(index - 1) /\ index - 1 \in 0..count
            BY ONLY <1>shape, (index \in 1..count), SMT
        <2>prior. /\ agrees(index - 1) /\ source[index - 1] \in AssignmentPrefixStates
            BY ONLY <2>bounds, <1>shape, (\A earlier \in 0..(index - 1) : agrees(earlier)), SMT
        <2>step. AssignmentListStep(FALSE, source[index - 1], rows[index], index) =
                     AssignmentListStep(TRUE, source[index - 1], rows[index], index)
            BY ONLY <2>bounds, <1>shape, <2>prior, (index \in 1..count), CertifiedAssignmentStepIsTypedAndShared, SMT
        <2>. QED BY <2>prior, <2>step, (index \in 1..count), SMT DEF agrees, AssignmentListHistory, count
    <1>. HIDE DEF agrees
    <1>all. \A index \in 0..count : agrees(index)
        BY ONLY <1>shape, <1>entry, <1>step, FiniteIndexedPrefixProperty, Isa
    <1>. QED BY ONLY <1>shape, <1>all, SMT DEF agrees, count

THEOREM CertifiedOrderedAssignmentListConstructsCompleteActionOutcome ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings
    PROVE \E history :
        /\ AssignmentListHistory(FALSE, before, rows, history)
        /\ AssignmentListHistory(TRUE, before, rows, history)
        /\ \A index \in 0..Len(rows) : AssignmentPrefixMeaning(before, rows, history, index)
    PROOF
    <1>histories. PICK history : AssignmentListHistory(FALSE, before, rows, history)
                                  /\ AssignmentListHistory(TRUE, before, rows, history)
        BY ONLY (SupportedAssignmentList(rows)), (before \in AssignmentBindings), CertifiedAssignmentListsConstructTheirHistories
    <1>prefixes. \A index \in 0..Len(rows) : AssignmentPrefixMeaning(before, rows, history, index)
        BY ONLY <1>histories, (SupportedAssignmentList(rows)), (before \in AssignmentBindings),
            OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix, SMT
    <1>. WITNESS history
    <1>. QED BY ONLY <1>histories, <1>prefixes

====
