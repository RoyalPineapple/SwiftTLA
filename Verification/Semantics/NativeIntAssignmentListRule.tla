---- MODULE NativeIntAssignmentListRule ----
EXTENDS PhysicalIntAssignmentRhsRule, NativeScalarCopyRule

NativeAssignmentRhsPlan(reference) ==
    IF reference[1] = "expression" THEN reference[2]
    ELSE
        LET literal == reference[1] = "literal"
        IN [count |-> 1, kinds |-> <<IF literal THEN "literal" ELSE "read">>,
            literals |-> <<IF literal THEN reference[2] ELSE 0>>,
            reads |-> <<reference>>, left |-> <<0>>, right |-> <<0>>]

NativeAssignmentReadNamesAreKnown(raw, names) ==
    \A index \in DOMAIN raw.captures :
        LET physical == NativeAssignmentRhsPlan(raw.captures[index])
        IN \A node \in 1..physical.count :
               (physical.kinds[node] = "read" /\ physical.reads[node][1] = "state") =>
                   physical.reads[node][2] \in {names[key] : key \in Keys}

NativeAssignmentRekey(raw, names, counter) ==
    LET entry == NativeCopyRekey(raw, Keys, names, counter)
        rekey(reference) ==
            IF reference[1] = "state"
            THEN <<"state", NativeCopyKey(Keys, names, counter, reference[2])>>
            ELSE reference
    IN [captures |-> [index \in DOMAIN raw.captures |->
            LET physical == NativeAssignmentRhsPlan(raw.captures[index])
            IN [physical EXCEPT !.reads = [node \in 1..physical.count |->
                IF physical.kinds[node] = "read" THEN rekey(physical.reads[node]) ELSE <<>>]]],
        guards |-> entry.guards, writes |-> entry.writes]

NativeAssignmentFinalRoutes(rows) == DirectCopyRoutes(Keys, rows)[Len(rows)]

NativeAssignmentWritesNameLastTargets(rows, plan, entry, destination) ==
    /\ Keys \subseteq STRING
    /\ NativeCopyControlSlot \notin Keys
    /\ plan.guards = <<entry>>
    /\ Len(plan.writes) \in Nat
    /\ DOMAIN plan.writes = 1..Len(plan.writes)
    /\ \A index \in DOMAIN plan.writes :
           LET key == plan.writes[index][1]
               reference == plan.writes[index][2]
           IN /\ key \in NativeCopyFields(Keys)
              /\ IF key = NativeCopyControlSlot THEN reference = <<"control", destination>>
                 ELSE CopyReceiptNamesWriter(rows, Len(rows), key, reference)
    /\ \A key \in NativeCopyFields(Keys) : \E index \in DOMAIN plan.writes : plan.writes[index][1] = key

NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination) ==
    LET plan == NativeAssignmentRekey(raw, names, counter)
    IN /\ NativeCopyKnownRoles(raw, Keys, names, counter)
       /\ NativeAssignmentReadNamesAreKnown(raw, names)
       /\ DOMAIN plan.captures = 1..Len(rows)
       /\ \A index \in 1..Len(rows) : PhysicalAssignmentReadsNameWriters(rows, index, plan.captures[index])
       /\ NativeAssignmentWritesNameLastTargets(rows, plan, entry, destination)

NativeAssignmentStart == [completed |-> <<>>, failure |-> <<>>]

NativeAssignmentStep(before, rhs, site, previous) ==
    IF previous.failure # <<>> THEN previous
    ELSE
        LET outcome == PhysicalAssignmentRhs(rhs, before, previous.completed)
        IN IF outcome.ok THEN [completed |-> Append(previous.completed, outcome.value), failure |-> <<>>]
           ELSE [completed |-> previous.completed, failure |-> [site |-> site, payload |-> outcome.failure]]

NativeAssignmentCaptureHistory(before, plan, count, history) ==
    /\ DOMAIN history = 0..count
    /\ history[0] = NativeAssignmentStart
    /\ \A index \in 1..count :
           history[index] = NativeAssignmentStep(before, plan.captures[index], index, history[index - 1])

NativeAssignmentPrefix(prefix) ==
    [completed |-> prefix.completed,
     failure |-> IF prefix.failure = <<>> THEN <<>>
                 ELSE [site |-> prefix.failure.site, payload |-> prefix.failure.payload]]

NativeAssignmentProjectedHistory(shared, count) ==
    [index \in 0..count |-> NativeAssignmentPrefix(shared[index])]

THEOREM PhysicalNativeCapturesUseTheCertifiedAssignmentHistory ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings,
           NEW raw, NEW names, NEW counter, NEW entry, NEW destination,
           NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination),
           NEW shared, AssignmentListHistory(FALSE, before, rows, shared)
    PROVE NativeAssignmentCaptureHistory(before, NativeAssignmentRekey(raw, names, counter), Len(rows),
              NativeAssignmentProjectedHistory(shared, Len(rows)))
    PROOF
    <1>. DEFINE count == Len(rows)
                plan == NativeAssignmentRekey(raw, names, counter)
                native == NativeAssignmentProjectedHistory(shared, count)
    <1>shape. /\ count \in Nat
              /\ shared \in [0..count -> AssignmentPrefixStates]
              /\ \A index \in 1..count : PhysicalAssignmentReadsNameWriters(rows, index, plan.captures[index])
        BY SMT DEF AssignmentListHistory, SupportedAssignmentList,
            NativeAssignmentsNameTheirOperandsAndWrites, plan, count
    <1>prefixes. \A index \in 0..count : AssignmentPrefixMeaning(before, rows, shared, index)
        BY ONLY (SupportedAssignmentList(rows)), (before \in AssignmentBindings),
            AssignmentListHistory(FALSE, before, rows, shared),
            OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix DEF count
    <1>seed. /\ DOMAIN native = 0..count /\ native[0] = NativeAssignmentStart
        BY ONLY <1>shape, AssignmentListHistory(FALSE, before, rows, shared), SMT
            DEF native, NativeAssignmentProjectedHistory, AssignmentListHistory, AssignmentListStart,
                NativeAssignmentStart, NativeAssignmentPrefix, count
    <1>step. \A index \in 1..count :
        native[index] = NativeAssignmentStep(before, plan.captures[index], index, native[index - 1])
        <2>. TAKE index \in 1..count
        <2>. DEFINE previous == shared[index - 1]
                    current == shared[index]
                    rhs == plan.captures[index]
        <2>source. current = AssignmentListStep(FALSE, previous, rows[index], index)
            BY ONLY (index \in 1..count), AssignmentListHistory(FALSE, before, rows, shared), SMT
                DEF AssignmentListHistory, previous, current, count
        <2>rows. /\ native[index] = NativeAssignmentPrefix(current)
                 /\ native[index - 1] = NativeAssignmentPrefix(previous)
                 /\ previous \in AssignmentPrefixStates
            BY ONLY <1>shape, (index \in 1..count), SMT DEF native, NativeAssignmentProjectedHistory, current, previous
        <2>first. CASE previous.failure = <<>>
            <3>prior. /\ Len(previous.completed) = index - 1
                       /\ previous.bindings = CompletedAssignmentBindings(before, rows, previous.completed)
                       /\ previous.completed \in Seq(AssignmentIntValues)
                BY ONLY <2>first, <2>rows, <1>prefixes, <1>shape, (index \in 1..count), SMT
                    DEF AssignmentPrefixMeaning, AssignmentPrefixStates, previous
            <3>decoded. PhysicalAssignmentReadsMatchRoutes(rows, index, rhs)
                BY ONLY <1>shape, (index \in 1..count), NamedAssignmentOperandsMatchTheirRoutes, SMT DEF rhs, count
            <3>rhs. PhysicalAssignmentRhs(rhs, before, previous.completed) =
                      SourceAssignmentRHS(rows[index], previous.bindings)
                BY ONLY (SupportedAssignmentList(rows)), (before \in AssignmentBindings), <3>decoded,
                    <3>prior, (index \in 1..count), PhysicalAssignmentRhsHasCertifiedOutcome, SMT DEF count
            <3>. QED BY ONLY <2>first, <2>source, <2>rows, <3>rhs, SMT
                DEF NativeAssignmentStep, AssignmentListStep, NativeAssignmentPrefix, rhs
        <2>stopped. CASE previous.failure # <<>>
            BY ONLY <2>stopped, <2>source, <2>rows, SMT
                DEF NativeAssignmentStep, AssignmentListStep, NativeAssignmentPrefix
        <2>. QED BY ONLY <2>first, <2>stopped, SMT
    <1>. QED BY ONLY <1>seed, <1>step DEF NativeAssignmentCaptureHistory, native, plan, count

THEOREM NativeAssignmentCaptureHistoriesAgree ==
    ASSUME NEW before, NEW plan, NEW count \in Nat, NEW left, NEW right,
           NativeAssignmentCaptureHistory(before, plan, count, left),
           NativeAssignmentCaptureHistory(before, plan, count, right)
    PROVE \A index \in 0..count : left[index] = right[index]
    PROOF
    <1>. DEFINE agrees(index) == left[index] = right[index]
    <1>seed. agrees(0)
        BY SMT DEF NativeAssignmentCaptureHistory, agrees
    <1>step. \A index \in 1..count : (\A prior \in 0..(index - 1) : agrees(prior)) => agrees(index)
        <2>. SUFFICES ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : agrees(prior)
                     PROVE agrees(index)
            OBVIOUS
        <2>previous. agrees(index - 1)
            BY ONLY (index \in 1..count), (\A prior \in 0..(index - 1) : agrees(prior)), SMT
        <2>. QED BY <2>previous, SMT DEF NativeAssignmentCaptureHistory, agrees
    <1>. HIDE DEF agrees
    <1>all. \A index \in 0..count : agrees(index)
        <2>. TAKE index \in 0..count
        <2>. SUFFICES ASSUME ~agrees(index)
                     PROVE FALSE
            BY PTL
        <2>. DEFINE differs(position) == position \in 0..count /\ ~agrees(position)
        <2>different. index \in Nat /\ differs(index)
            BY ONLY (count \in Nat), (index \in 0..count), ~agrees(index), SMT DEF differs
        <2>. HIDE DEF differs
        <2>first. PICK first \in Nat :
            differs(first) /\ \A prior \in 0..(first - 1) : ~differs(prior)
            BY ONLY <2>different, SmallestNatural, Isa
        <2>bounds. first \in 1..count /\ ~agrees(first)
            BY ONLY <2>first, <1>seed, (count \in Nat), SMT DEF differs
        <2>prior. \A prior \in 0..(first - 1) : agrees(prior)
            BY ONLY <2>first, <2>bounds, (count \in Nat), SMT DEF differs
        <2>equal. agrees(first)
            BY ONLY <1>step, <2>bounds, <2>prior, SMT
        <2>. QED BY ONLY <2>bounds, <2>equal, PTL
    <1>. QED BY ONLY <1>all DEF agrees

THEOREM PhysicalNativePrefixAgreesWithTheCertifiedAssignments ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings,
           NEW raw, NEW names, NEW counter, NEW entry, NEW destination,
           NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination),
           NEW shared, AssignmentListHistory(FALSE, before, rows, shared),
           NEW visited, NativeAssignmentCaptureHistory(before,
               NativeAssignmentRekey(raw, names, counter), Len(rows), visited)
    PROVE \A index \in 0..Len(rows) : visited[index] = NativeAssignmentPrefix(shared[index])
    PROOF
    <1>. DEFINE expected == NativeAssignmentProjectedHistory(shared, Len(rows))
    <1>count. Len(rows) \in Nat
        BY SupportedAssignmentList(rows) DEF SupportedAssignmentList
    <1>history. NativeAssignmentCaptureHistory(before,
                    NativeAssignmentRekey(raw, names, counter), Len(rows), expected)
        BY PhysicalNativeCapturesUseTheCertifiedAssignmentHistory DEF expected
    <1>same. \A index \in 0..Len(rows) : visited[index] = expected[index]
        BY ONLY <1>count, <1>history,
            NativeAssignmentCaptureHistory(before, NativeAssignmentRekey(raw, names, counter), Len(rows), visited),
            NativeAssignmentCaptureHistoriesAgree, SMT
    <1>. QED BY ONLY <1>same, SMT DEF expected, NativeAssignmentProjectedHistory

NativeAssignmentCheckedCallback(original, label, actionOrdinal, selected, result) ==
    IF selected /\ result.failure # <<>>
    THEN {[label |-> label, actionOrdinal |-> actionOrdinal,
           site |-> result.failure.site, completed |-> result.completed,
           payload |-> result.failure.payload, before |-> original]}
    ELSE {}

NativeAssignmentDispatchMatches(rows, dispatch, actionOrdinal, sourceLabel, formalLabel) ==
    /\ actionOrdinal \in Nat
    /\ actionOrdinal + 1 \in DOMAIN rows
    /\ actionOrdinal + 1 \in DOMAIN dispatch
    /\ rows[actionOrdinal + 1][1] = sourceLabel
    /\ dispatch[actionOrdinal + 1] = formalLabel

NativeAssignmentLiteralCaptures(completed) ==
    [index \in DOMAIN completed |-> <<"literal", completed[index]>>]

NativeAssignmentMaterializationPlan(plan, completed) ==
    [captures |-> NativeAssignmentLiteralCaptures(completed), guards |-> plan.guards, writes |-> plan.writes]

THEOREM SuccessfulNativeAssignmentsUseTheCompleteLastWriteFrame ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings,
           NEW raw, NEW names, NEW counter, NEW entry, NEW destination,
           NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination),
           NEW shared, AssignmentListHistory(FALSE, before, rows, shared),
           shared[Len(rows)].failure = <<>>,
           NEW after \in AssignmentBindings, NEW pcBefore, NEW pcAfter
    PROVE LET plan == NativeAssignmentRekey(raw, names, counter)
              final == shared[Len(rows)]
          IN NativeCopyVisits(NativeAssignmentMaterializationPlan(plan, final.completed),
                              Keys, before, after, pcBefore, pcAfter)
             <=> (pcBefore = entry /\ pcAfter = destination /\ after = final.bindings)
    PROOF
    <1>. DEFINE count == Len(rows)
                plan == NativeAssignmentRekey(raw, names, counter)
                final == shared[count]
                reads == NativeAssignmentLiteralCaptures(final.completed)
                refs == NativeAssignmentFinalRoutes(rows)
                emitted == NativeAssignmentMaterializationPlan(plan, final.completed)
    <1>shape. /\ count \in Nat
              /\ shared \in [0..count -> AssignmentPrefixStates]
              /\ NativeAssignmentWritesNameLastTargets(rows, plan, entry, destination)
        BY SMT DEF SupportedAssignmentList, AssignmentListHistory, count, NativeAssignmentsNameTheirOperandsAndWrites, plan
    <1>values. /\ final.completed \in Seq(AssignmentIntValues)
               /\ Len(final.completed) = count
               /\ final.bindings = CopyMaterializedState(Keys, before, final.completed, refs)
        PROOF
        <2>complete. AssignmentPrefixMeaning(before, rows, shared, count)
            BY ONLY <1>shape, SupportedAssignmentList(rows), (before \in AssignmentBindings),
                AssignmentListHistory(FALSE, before, rows, shared),
                OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix, SMT DEF count
        <2>. QED BY ONLY <2>complete, <1>shape, (shared[Len(rows)].failure = <<>>), SMT
            DEF AssignmentPrefixMeaning, CompletedAssignmentBindings, AssignmentPrefixStates, final, count, refs,
                NativeAssignmentFinalRoutes
    <1>writes. \A index \in DOMAIN plan.writes :
        LET key == plan.writes[index][1]
        IN plan.writes[index][2] = IF key = NativeCopyControlSlot THEN <<"control", destination>> ELSE refs[key]
        PROOF
        <2>. TAKE index \in DOMAIN plan.writes
        <2>. DEFINE key == plan.writes[index][1]
                    reference == plan.writes[index][2]
        <2>named. /\ key \in NativeCopyFields(Keys)
                  /\ IF key = NativeCopyControlSlot THEN reference = <<"control", destination>>
                     ELSE CopyReceiptNamesWriter(rows, count, key, reference)
            BY ONLY <1>shape, (index \in DOMAIN plan.writes), SMT DEF NativeAssignmentWritesNameLastTargets, key, reference, count
        <2>ordinary. key # NativeCopyControlSlot => reference = refs[key]
            BY ONLY <1>shape, <2>named, NamedAssignmentReadRouteIsTheScheduledRoute, SMT
                DEF NativeCopyFields, refs, NativeAssignmentFinalRoutes, count
        <2>. QED BY ONLY <2>named, <2>ordinary DEF key, reference
    <1>routes. \A key \in Keys :
        /\ refs[key][1] \in {"state", "capture"}
        /\ (refs[key][1] = "state" => refs[key][2] \in Keys)
        /\ (refs[key][1] = "capture" => refs[key][2] \in DOMAIN final.completed)
        <2>. TAKE key \in Keys
        <2>reference. refs[key] = DirectCopyReference(key, DirectCopyWriter(rows, count, key))
            BY ONLY <1>shape, (key \in Keys), SMT DEF refs, NativeAssignmentFinalRoutes, DirectCopyRoutes, count
        <2>earlier. refs[key][1] = "capture" => refs[key][2] \in 1..count
            BY ONLY <1>shape, (key \in Keys), ReachedAssignmentRoutesUseOnlyEarlierCaptures, SMT
                DEF refs, NativeAssignmentFinalRoutes, count
        <2>. QED BY ONLY <2>reference, <2>earlier, <1>values, (key \in Keys), LenProperties, SMT DEF DirectCopyReference
    <1>plan. NativeCompleteCopyPlan(emitted, Keys, reads, refs, entry, <<"control", destination>>)
        BY ONLY <1>shape, <1>writes, <1>routes, SMT DEF NativeAssignmentWritesNameLastTargets,
            NativeCompleteCopyPlan, emitted, NativeAssignmentMaterializationPlan, reads, NativeAssignmentLiteralCaptures
    <1>witness. CopyCaptureHistory(before, reads, final.completed)
        BY ONLY SMT DEF reads, NativeAssignmentLiteralCaptures, CopyCaptureHistory, CopyReferenceValue
    <1>unique. \A values : CopyCaptureHistory(before, reads, values) =>
        CopyMaterializedState(Keys, before, values, refs) = final.bindings
        <2>. SUFFICES ASSUME NEW values, CopyCaptureHistory(before, reads, values)
                     PROVE CopyMaterializedState(Keys, before, values, refs) = final.bindings
            OBVIOUS
        <2>same. \A index \in DOMAIN final.completed : values[index] = final.completed[index]
            BY ONLY CopyCaptureHistory(before, reads, values), SMT
                DEF reads, NativeAssignmentLiteralCaptures, CopyCaptureHistory, CopyReferenceValue
        <2>. QED BY ONLY <2>same, <1>routes, <1>values, SMT DEF CopyMaterializedState, CopyReferenceValue
    <1>materialized. CompiledCopyBranch(Keys, before, reads, refs, after) <=> after = final.bindings
        BY ONLY <1>witness, <1>unique, SMT DEF CompiledCopyBranch
    <1>eta. after = [key \in Keys |-> after[key]]
        BY ONLY (after \in AssignmentBindings), SMT DEF AssignmentBindings
    <1>physical. NativeCopyVisits(emitted, Keys, before, after, pcBefore, pcAfter) <=>
                         (pcBefore = entry /\ pcAfter = destination /\
                          CompiledCopyBranch(Keys, before, reads, refs, after))
        BY ONLY <1>eta, <1>plan, ValidatedNativeCopyPlansHaveTheCompleteCompiledObservation, SMT
    <1>. QED BY ONLY <1>physical, <1>materialized DEF emitted, plan, final, count

THEOREM CheckedNativeDispatchConstructsTheSharedPrefixAndCallback ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW rawRows, NEW dispatch, NEW actionOrdinal,
           NEW label, NEW formalLabel, NativeAssignmentDispatchMatches(rawRows, dispatch, actionOrdinal, label, formalLabel),
           NEW names, NEW counter, NEW entry, NEW destination, NEW original,
           [key \in Keys |-> original[names[key]]] \in AssignmentBindings,
           NativeAssignmentsNameTheirOperandsAndWrites(rows, rawRows[actionOrdinal + 1][2],
               names, counter, entry, destination)
    PROVE LET before == [key \in Keys |-> original[names[key]]]
              raw == rawRows[actionOrdinal + 1][2]
              plan == NativeAssignmentRekey(raw, names, counter)
              count == Len(rows)
          IN \E shared, native :
                /\ AssignmentListHistory(FALSE, before, rows, shared)
                /\ NativeAssignmentCaptureHistory(before, plan, count, native)
                /\ \A index \in 0..count : AssignmentPrefixMeaning(before, rows, shared, index)
                /\ \A index \in 0..count : native[index] = NativeAssignmentPrefix(shared[index])
                /\ LET final == shared[count]
                   IN NativeAssignmentCheckedCallback(original, label, actionOrdinal, original[counter] = entry, native[count]) =
                       IF original[counter] = entry /\ final.failure # <<>>
                       THEN {[label |-> label, actionOrdinal |-> actionOrdinal,
                              site |-> final.failure.site, completed |-> final.completed,
                              payload |-> final.failure.payload, before |-> original]}
                       ELSE {}
    PROOF
    <1>. DEFINE before == [key \in Keys |-> original[names[key]]]
                raw == rawRows[actionOrdinal + 1][2]
                plan == NativeAssignmentRekey(raw, names, counter)
                count == Len(rows)
    <1>shared. PICK shared : AssignmentListHistory(FALSE, before, rows, shared)
         /\ \A index \in 0..count : AssignmentPrefixMeaning(before, rows, shared, index)
        BY CertifiedOrderedAssignmentListConstructsCompleteActionOutcome, SMT DEF before, count
    <1>. DEFINE final == shared[count]
                native == NativeAssignmentProjectedHistory(shared, count)
    <1>native. NativeAssignmentCaptureHistory(before, plan, count, native)
        BY ONLY <1>shared, SupportedAssignmentList(rows), (before \in AssignmentBindings),
            NativeAssignmentsNameTheirOperandsAndWrites(rows, rawRows[actionOrdinal + 1][2], names, counter, entry, destination),
            PhysicalNativeCapturesUseTheCertifiedAssignmentHistory DEF before, raw, plan, count, native
    <1>prefix. \A index \in 0..count : native[index] = NativeAssignmentPrefix(shared[index])
        BY ONLY SMT DEF native, NativeAssignmentProjectedHistory
    <1>callbacks. NativeAssignmentCheckedCallback(original, label, actionOrdinal, original[counter] = entry, native[count]) =
        IF original[counter] = entry /\ final.failure # <<>>
        THEN {[label |-> label, actionOrdinal |-> actionOrdinal,
               site |-> final.failure.site, completed |-> final.completed,
               payload |-> final.failure.payload, before |-> original]}
        ELSE {}
        BY ONLY <1>prefix, SupportedAssignmentList(rows), SMT
            DEF NativeAssignmentCheckedCallback, NativeAssignmentPrefix, SupportedAssignmentList, count, final
    <1>joint. \E sourceHistory, nativeHistory :
        /\ AssignmentListHistory(FALSE, before, rows, sourceHistory)
        /\ NativeAssignmentCaptureHistory(before, plan, count, nativeHistory)
        /\ \A index \in 0..count : AssignmentPrefixMeaning(before, rows, sourceHistory, index)
        /\ \A index \in 0..count : nativeHistory[index] = NativeAssignmentPrefix(sourceHistory[index])
        /\ LET tail == sourceHistory[count]
           IN NativeAssignmentCheckedCallback(original, label, actionOrdinal, original[counter] = entry, nativeHistory[count]) =
               IF original[counter] = entry /\ tail.failure # <<>>
               THEN {[label |-> label, actionOrdinal |-> actionOrdinal,
                      site |-> tail.failure.site, completed |-> tail.completed,
                      payload |-> tail.failure.payload, before |-> original]}
               ELSE {}
        <2>. WITNESS shared, native
        <2>. QED BY ONLY <1>shared, <1>native, <1>prefix, <1>callbacks DEF final
    <1>. QED BY ONLY <1>joint DEF before, raw, plan, count


THEOREM NativeAssignmentRekeyPreservesTheWriteCount ==
    ASSUME NEW raw, NEW names, NEW counter,
           Len(raw.writes) \in Nat, DOMAIN raw.writes = 1..Len(raw.writes)
    PROVE LET writes == NativeAssignmentRekey(raw, names, counter).writes
          IN /\ Len(writes) = Len(raw.writes) /\ DOMAIN writes = DOMAIN raw.writes
PROOF
<1>. DEFINE writes == NativeAssignmentRekey(raw, names, counter).writes
            values == {writes[index] : index \in DOMAIN writes}
<1>domain. DOMAIN writes = DOMAIN raw.writes
    BY ONLY SMT DEF writes, NativeAssignmentRekey, NativeCopyRekey
<1>function. writes \in [1..Len(raw.writes) -> values]
    BY ONLY <1>domain, (DOMAIN raw.writes = 1..Len(raw.writes)), SMT DEF values, writes, NativeAssignmentRekey, NativeCopyRekey
<1>sequence. writes \in Seq(values)
    BY ONLY <1>function, (Len(raw.writes) \in Nat), SeqDef, SMT
<1>. QED BY ONLY <1>domain, <1>sequence, LenProperties, SMT


\* Artifact input: the SwiftSyntax decoder supplies the routed visitor's capture
\* records, final writes and lexical model-error append sites. The history is the
\* existing interpretation of the decoded sequential capture instructions.
DecodedNativeAssignmentFinal(rows, raw, names, counter, before) ==
    LET instruction == NativeAssignmentRekey(raw, names, counter)
        history == CHOOSE history : NativeAssignmentCaptureHistory(before, instruction, Len(rows), history)
    IN history[Len(rows)]

DecodedNativeAssignmentStep(rows, raw, names, counter, before, after, pcBefore, pcAfter) ==
    LET result == DecodedNativeAssignmentFinal(rows, raw, names, counter, before)
        instruction == NativeAssignmentRekey(raw, names, counter)
    IN /\ result.failure = <<>>
       /\ after \in AssignmentBindings
       /\ NativeCopyVisits(NativeAssignmentMaterializationPlan(instruction, result.completed),
                              Keys, before, after, pcBefore, pcAfter)

DecodedNativeAssignmentFailures(rows, raw, names, counter, before, pcBefore, appendSites) ==
    LET result == DecodedNativeAssignmentFinal(rows, raw, names, counter, before)
        site == result.failure.site
    IN IF /\ \A guard \in DOMAIN raw.guards : raw.guards[guard] = pcBefore
          /\ result.failure # <<>>
          /\ site \in appendSites
       THEN {[site |-> site, target |-> rows[site].target, payload |-> result.failure.payload,
              completed |-> result.completed, before |-> CompletedAssignmentBindings(before, rows, result.completed)]}
       ELSE {}

THEOREM DecodedNativeAssignmentsUseTheCertifiedActionObservation ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW raw, NEW names, NEW counter,
           NEW entry, NEW destination, NEW before \in AssignmentBindings, NEW after,
           NEW pcBefore, NEW pcAfter, NEW appendSites, NEW shared,
           NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination),
           AssignmentListHistory(FALSE, before, rows, shared),
           (pcBefore = entry /\ shared[Len(rows)].failure # <<>> =>
               shared[Len(rows)].failure.site \in appendSites)
    PROVE LET final == shared[Len(rows)]
          IN /\ (DecodedNativeAssignmentStep(rows, raw, names, counter, before, after, pcBefore, pcAfter)
                 <=> (pcBefore = entry /\ final.failure = <<>> /\ pcAfter = destination /\ after = final.bindings))
             /\ DecodedNativeAssignmentFailures(rows, raw, names, counter, before, pcBefore, appendSites) =
                IF pcBefore = entry /\ final.failure # <<>>
                THEN {[site |-> final.failure.site, target |-> rows[final.failure.site].target,
                       payload |-> final.failure.payload, completed |-> final.completed, before |-> final.failure.before]}
                ELSE {}
PROOF
<1>. DEFINE count == Len(rows)
            instruction == NativeAssignmentRekey(raw, names, counter)
            final == shared[count]
            result == DecodedNativeAssignmentFinal(rows, raw, names, counter, before)
            history == CHOOSE visited : NativeAssignmentCaptureHistory(before, instruction, count, visited)
<1>history. NativeAssignmentCaptureHistory(before, instruction, count, history)
    <2>exists. \E visited : NativeAssignmentCaptureHistory(before, instruction, count, visited)
        BY ONLY PhysicalNativeCapturesUseTheCertifiedAssignmentHistory,
            SupportedAssignmentList(rows), (before \in AssignmentBindings),
            NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination),
            AssignmentListHistory(FALSE, before, rows, shared) DEF instruction, count
    <2>. QED BY ONLY <2>exists, SMT DEF history
<1>record. result = NativeAssignmentPrefix(final)
    <2>prefix. \A index \in 0..count : history[index] = NativeAssignmentPrefix(shared[index])
        BY ONLY <1>history, PhysicalNativePrefixAgreesWithTheCertifiedAssignments,
            SupportedAssignmentList(rows), (before \in AssignmentBindings),
            NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination),
            AssignmentListHistory(FALSE, before, rows, shared)
            DEF instruction, count
    <2>index. count \in 0..count
        BY ONLY SupportedAssignmentList(rows), SMT DEF SupportedAssignmentList, count
    <2>last. history[count] = NativeAssignmentPrefix(final)
        BY ONLY <2>prefix, <2>index, SMT DEF final
    <2>decoded. result = history[count]
        BY ONLY DEF result, DecodedNativeAssignmentFinal, history, instruction, count
    <2>. QED BY ONLY <2>last, <2>decoded, SMT
<1>meaning. /\ final.bindings \in AssignmentBindings
           /\ (final.failure # <<>> =>
                final.failure.before = CompletedAssignmentBindings(before, rows, final.completed))
    <2>domain. /\ count \in Nat /\ final \in AssignmentPrefixStates
        BY ONLY SupportedAssignmentList(rows), AssignmentListHistory(FALSE, before, rows, shared), SMT
            DEF SupportedAssignmentList, AssignmentListHistory, count, final
    <2>prefix. AssignmentPrefixMeaning(before, rows, shared, count)
        BY ONLY <2>domain, SupportedAssignmentList(rows), (before \in AssignmentBindings),
            AssignmentListHistory(FALSE, before, rows, shared), OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix
            DEF count
    <2>. QED BY ONLY <2>domain, <2>prefix, SMT DEF AssignmentPrefixStates, AssignmentPrefixMeaning, count, final
<1>success. DecodedNativeAssignmentStep(rows, raw, names, counter, before, after, pcBefore, pcAfter)
          <=> (pcBefore = entry /\ final.failure = <<>> /\ pcAfter = destination /\ after = final.bindings)
    <2>frame. final.failure = <<>> /\ after \in AssignmentBindings =>
        (NativeCopyVisits(NativeAssignmentMaterializationPlan(instruction, final.completed),
               Keys, before, after, pcBefore, pcAfter)
          <=> (pcBefore = entry /\ pcAfter = destination /\ after = final.bindings))
        BY ONLY SuccessfulNativeAssignmentsUseTheCompleteLastWriteFrame,
            SupportedAssignmentList(rows), (before \in AssignmentBindings),
            NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination),
            AssignmentListHistory(FALSE, before, rows, shared), SMT DEF instruction, final, count
    <2>. QED BY ONLY <1>record, <1>meaning, <2>frame, SMT
        DEF DecodedNativeAssignmentStep, result, NativeAssignmentPrefix, instruction
<1>failures. DecodedNativeAssignmentFailures(rows, raw, names, counter, before, pcBefore, appendSites) =
    IF pcBefore = entry /\ final.failure # <<>>
    THEN {[site |-> final.failure.site, target |-> rows[final.failure.site].target,
           payload |-> final.failure.payload, completed |-> final.completed, before |-> final.failure.before]}
    ELSE {}
    <2>guard. raw.guards = <<entry>>
        BY ONLY NativeAssignmentsNameTheirOperandsAndWrites(rows, raw, names, counter, entry, destination), SMT
           DEF NativeAssignmentsNameTheirOperandsAndWrites, NativeAssignmentWritesNameLastTargets,
               NativeAssignmentRekey, NativeCopyRekey
    <2>. QED BY ONLY <2>guard, <1>record, <1>meaning,
        (pcBefore = entry /\ shared[Len(rows)].failure # <<>> => shared[Len(rows)].failure.site \in appendSites), SMT
        DEF DecodedNativeAssignmentFailures, result, NativeAssignmentPrefix, final, count
<1>. QED BY ONLY <1>success, <1>failures DEF final, count

====
