---- MODULE NativeScalarCopyRule ----
EXTENDS NativePendingWriteFold, OrderedScalarCopyRule

NativeCopyControlSlot == ""

NativeCopyPhysicalKeys(fields, names, counter) == {names[key] : key \in fields} \cup {counter}

NativeCopyKnownRoles(plan, fields, names, counter) ==
    LET physical == NativeCopyPhysicalKeys(fields, names, counter)
        known(reference) == reference[1] = "state" => reference[2] \in physical
    IN /\ fields \subseteq STRING
       /\ DOMAIN names = fields
       /\ \A key \in fields : names[key] # counter
       /\ \A key, other \in fields : names[key] = names[other] => key = other
       /\ \A index \in DOMAIN plan.captures : known(plan.captures[index])
       /\ \A index \in DOMAIN plan.writes :
             /\ plan.writes[index][1] \in physical
             /\ known(plan.writes[index][2])

NativeCopyKey(fields, names, counter, physical) ==
    IF physical = counter THEN NativeCopyControlSlot
    ELSE CHOOSE key \in fields : names[key] = physical

NativeCopyRekey(plan, fields, names, counter) ==
    LET rekey(key) == NativeCopyKey(fields, names, counter, key)
        reference(value) == IF value[1] = "state" THEN <<"state", rekey(value[2])>> ELSE value
    IN [captures |-> [index \in DOMAIN plan.captures |-> reference(plan.captures[index])],
        guards |-> plan.guards,
        writes |-> [index \in DOMAIN plan.writes |->
            <<rekey(plan.writes[index][1]), reference(plan.writes[index][2])>>]]

NativeCopyFields(keys) == keys \cup {NativeCopyControlSlot}
NativeCopySnapshot(keys, state, control) ==
    [key \in NativeCopyFields(keys) |-> IF key = NativeCopyControlSlot THEN control ELSE state[key]]

NativeCopyValue(before, captures, reference) ==
    IF reference[1] = "control" THEN reference[2] ELSE CopyReferenceValue(before, captures, reference)

NativeCopyWrites(plan, before, captures) ==
    [index \in DOMAIN plan.writes |->
        <<plan.writes[index][1], NativeCopyValue(before, captures, plan.writes[index][2])>>]

NativeCopyVisits(plan, keys, before, after, entry, destination) ==
    LET source == NativeCopySnapshot(keys, before, entry)
        target == NativeCopySnapshot(keys, after, destination)
    IN /\ \A index \in DOMAIN plan.guards : entry = plan.guards[index]
       /\ \E captures :
            /\ CopyCaptureHistory(source, plan.captures, captures)
            /\ NativePendingMergesEmit(NativeCopyFields(keys), source, target, Len(plan.writes),
                    NativeCopyWrites(plan, source, captures))

\* The decoded straight-line visitor has one emit continuation. Its pending
\* write fold either reaches that call once or stops before the call.
NativeCopyCallbackSnapshots(plan, keys, before, pcBefore, captures) ==
    LET fields == NativeCopyFields(keys)
        source == NativeCopySnapshot(keys, before, pcBefore)
        writes == NativeCopyWrites(plan, source, captures)
        count == Len(plan.writes)
        merges == CHOOSE h : SuccessfulNativeMergeHistory(count, writes, h)
        target == NativeMaterializedSlots(fields, source, merges[count])
    IN IF /\ \A index \in DOMAIN plan.guards : pcBefore = plan.guards[index]
          /\ \E h : SuccessfulNativeMergeHistory(count, writes, h)
       THEN << <<target[NativeCopyControlSlot], [key \in keys |-> target[key]]>> >>
       ELSE <<>>

THEOREM NativeCopyCallbackUsesTheMaterializedWriteHistory ==
    ASSUME NEW plan, NEW keys, NativeCopyControlSlot \notin keys, NEW before, NEW after,
           NEW pcBefore, NEW pcAfter, NEW captures, Len(plan.writes) \in Nat,
           after = [key \in keys |-> after[key]],
           NativeCopyVisits(plan, keys, before, after, pcBefore, pcAfter),
           \A witness : CopyCaptureHistory(NativeCopySnapshot(keys, before, pcBefore),
                                                plan.captures, witness) => witness = captures
    PROVE NativeCopyCallbackSnapshots(plan, keys, before, pcBefore, captures) = << <<pcAfter, after>> >>
PROOF
<1>. DEFINE fields == NativeCopyFields(keys)
            source == NativeCopySnapshot(keys, before, pcBefore)
            expected == NativeCopySnapshot(keys, after, pcAfter)
            writes == NativeCopyWrites(plan, source, captures)
            count == Len(plan.writes)
            merges == CHOOSE h : SuccessfulNativeMergeHistory(count, writes, h)
<1>visit.
    /\ \A index \in DOMAIN plan.guards : pcBefore = plan.guards[index]
    /\ NativePendingMergesEmit(fields, source, expected, count, writes)
    BY ONLY NativeCopyVisits(plan, keys, before, after, pcBefore, pcAfter),
        (\A witness : CopyCaptureHistory(NativeCopySnapshot(keys, before, pcBefore),
                                          plan.captures, witness) => witness = captures), SMT
        DEF NativeCopyVisits, fields, source, expected, writes, count
<1>witness. PICK actual :
    /\ SuccessfulNativeMergeHistory(count, writes, actual)
    /\ expected = NativeMaterializedSlots(fields, source, actual[count])
    BY ONLY <1>visit, SMT DEF NativePendingMergesEmit, expected, NativeCopySnapshot, fields, NativeCopyFields
<1>chosen. SuccessfulNativeMergeHistory(count, writes, merges)
    BY ONLY <1>witness, SMT DEF merges
<1>keys.
    /\ DOMAIN merges[count] = PendingWriteKeys(writes, count)
    /\ DOMAIN actual[count] = PendingWriteKeys(writes, count)
    /\ \A index \in 1..count :
        merges[count][writes[index][1]] = actual[count][writes[index][1]]
    BY ONLY <1>chosen, <1>witness, (Len(plan.writes) \in Nat), SuccessfulMergesRetainEveryWriteInThePrefix, SMT
        DEF count
<1>same. merges[count] = actual[count]
    BY ONLY <1>keys, SMT DEF PendingWriteKeys
<1>target.
    <<NativeMaterializedSlots(fields, source, merges[count])[NativeCopyControlSlot],
        [key \in keys |-> NativeMaterializedSlots(fields, source, merges[count])[key]]>> = <<pcAfter, after>>
    BY ONLY <1>same, <1>witness, (NativeCopyControlSlot \notin keys),
        (after = [key \in keys |-> after[key]]), SMT DEF expected, NativeCopySnapshot, NativeCopyFields
<1>. QED BY ONLY <1>target, <1>chosen, <1>visit, SMT
    DEF NativeCopyCallbackSnapshots, fields, source, writes, count, merges

NativeCompleteCopyPlan(plan, keys, reads, refs, guard, control) ==
    /\ keys \subseteq STRING
    /\ NativeCopyControlSlot \notin keys
    /\ plan.guards = <<guard>>
    /\ plan.captures = reads
    /\ \A index \in DOMAIN reads :
        /\ reads[index][1] \in {"state", "capture", "literal"}
        /\ reads[index][1] = "state" => reads[index][2] \in keys
    /\ Len(plan.writes) \in Nat
    /\ DOMAIN plan.writes = 1..Len(plan.writes)
    /\ \A index \in DOMAIN plan.writes :
        LET key == plan.writes[index][1]
        IN /\ key \in NativeCopyFields(keys)
           /\ plan.writes[index][2] = (IF key = NativeCopyControlSlot THEN control ELSE refs[key])
    /\ \A key \in NativeCopyFields(keys) : \E index \in DOMAIN plan.writes : plan.writes[index][1] = key
    /\ \A key \in keys : refs[key][1] = "state" => refs[key][2] \in keys
    /\ \A key \in keys : refs[key][1] \in {"state", "capture", "literal"}
    /\ (control[1] = "control" \/ control = <<"state", NativeCopyControlSlot>>)

THEOREM ValidatedNativeCopyPlansHaveTheCompleteCompiledObservation ==
    ASSUME NEW plan, NEW keys, NEW reads, NEW refs, NEW guard, NEW control,
           NEW before, NEW after, NEW pcBefore, NEW pcAfter,
           after = [key \in keys |-> after[key]],
           NativeCompleteCopyPlan(plan, keys, reads, refs, guard, control)
    PROVE NativeCopyVisits(plan, keys, before, after, pcBefore, pcAfter)
        <=> /\ pcBefore = guard
            /\ pcAfter = (IF control[1] = "control" THEN control[2] ELSE pcBefore)
            /\ CompiledCopyBranch(keys, before, reads, refs, after)
    PROOF
    <1>. DEFINE prior == NativeCopySnapshot(keys, before, pcBefore)
                later == NativeCopySnapshot(keys, after, pcAfter)
                fields == NativeCopyFields(keys)
                count == Len(plan.writes)
                writes(c) == NativeCopyWrites(plan, prior, c)
                result(c) == [key \in fields |->
                    IF key = NativeCopyControlSlot
                    THEN IF control[1] = "control" THEN control[2] ELSE pcBefore
                    ELSE CopyReferenceValue(before, c, refs[key])]
    <1>shape. /\ count \in Nat /\ DOMAIN plan.writes = 1..count
              /\ \A index \in 1..count : plan.writes[index][1] \in fields
              /\ \A key \in fields : \E index \in 1..count : plan.writes[index][1] = key
        BY ONLY NativeCompleteCopyPlan(plan, keys, reads, refs, guard, control), SMT
            DEF NativeCompleteCopyPlan, count, fields
    <1>capture. \A c : CopyCaptureHistory(prior, plan.captures, c) <=> CopyCaptureHistory(before, reads, c)
        BY ONLY NativeCompleteCopyPlan(plan, keys, reads, refs, guard, control), SMT
            DEF NativeCompleteCopyPlan, CopyCaptureHistory, NativeCopySnapshot, NativeCopyFields, CopyReferenceValue, prior
    <1>merge. \A c :
           NativePendingMergesEmit(fields, prior, later, count, writes(c)) <=> later = result(c)
        PROOF
        <2>. SUFFICES ASSUME NEW c
            PROVE NativePendingMergesEmit(fields, prior, later, count, writes(c)) <=> later = result(c)
            OBVIOUS
        <2>actual. \A index \in 1..count :
                /\ writes(c)[index][1] = plan.writes[index][1]
                /\ writes(c)[index][2] = result(c)[plan.writes[index][1]]
            BY ONLY <1>shape, NativeCompleteCopyPlan(plan, keys, reads, refs, guard, control), SMT
                DEF NativeCompleteCopyPlan, NativeCopyWrites, writes, result, NativeCopyValue,
                    NativeCopySnapshot, CopyReferenceValue, prior, NativeCopyFields, fields
        <2>keys. PendingWriteKeys(writes(c), count) = fields
            BY ONLY <1>shape, <2>actual, SetExtensionality, SMT DEF PendingWriteKeys
        <2>fold. NativePendingMergesEmit(fields, prior, later, count, writes(c)) <=>
                 NativePendingWriteConstraints(fields, prior, later, count, writes(c))
            BY ONLY <1>shape, <2>actual, PendingMergeFoldMaterializesExactlyTheCompatibleWrites, SMT
        <2>same. NativePendingWriteConstraints(fields, prior, later, count, writes(c)) <=>
                 \A key \in fields : later[key] = result(c)[key]
            BY ONLY <1>shape, <2>keys, <2>actual, SMT DEF NativePendingWriteConstraints
        <2>. QED BY ONLY <2>fold, <2>same, SetExtensionality, SMT DEF result, later, NativeCopySnapshot, fields
    <1>finish. \A c :
        later = result(c) <=>
            /\ pcAfter = (IF control[1] = "control" THEN control[2] ELSE pcBefore)
            /\ after = CopyMaterializedState(keys, before, c, refs)
        BY ONLY NativeCompleteCopyPlan(plan, keys, reads, refs, guard, control),
            (after = [key \in keys |-> after[key]]), SetExtensionality, SMT
            DEF NativeCompleteCopyPlan, result, later, fields, NativeCopySnapshot,
                NativeCopyFields, CopyMaterializedState
    <1>guard. (\A index \in DOMAIN plan.guards : pcBefore = plan.guards[index]) <=> pcBefore = guard
        BY ONLY NativeCompleteCopyPlan(plan, keys, reads, refs, guard, control), SMT DEF NativeCompleteCopyPlan
    <1>visit. \A c :
        (CopyCaptureHistory(prior, plan.captures, c) /\ NativePendingMergesEmit(fields, prior, later, count, writes(c)))
        <=> /\ pcAfter = (IF control[1] = "control" THEN control[2] ELSE pcBefore)
            /\ CopyCaptureHistory(before, reads, c)
            /\ after = CopyMaterializedState(keys, before, c, refs)
        BY ONLY <1>capture, <1>merge, <1>finish
    <1>. QED BY ONLY <1>guard, <1>visit, SMT
        DEF NativeCopyVisits, CompiledCopyBranch, prior, later, fields, writes, count

THEOREM EmptyCopyPlanRetainsTheCompleteState ==
    ASSUME NEW keys, NEW before, NEW after, before = [key \in keys |-> before[key]]
    PROVE CompiledCopyBranch(keys, before, <<>>, CopyEntryRoutes(keys), after) <=> before = after
    PROOF
    <1>empty. CopyCaptureHistory(before, <<>>, <<>>)
        BY SMT DEF CopyCaptureHistory
    <1>frame. \A captured :
        CopyMaterializedState(keys, before, captured, CopyEntryRoutes(keys)) = before
        BY SMT DEF CopyMaterializedState, CopyEntryRoutes, CopyReferenceValue
    <1>. QED BY ONLY <1>empty, <1>frame, SMT DEF CompiledCopyBranch
====
