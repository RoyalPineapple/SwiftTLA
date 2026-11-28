---- MODULE NativePendingWriteFold ----
EXTENDS PendingWriteOutcomeRule, IndexedHistoryRules

PendingWriteKeys(writes, count) == {writes[index][1] : index \in 1..count}

EmptyPendingSlots == [key \in {} |-> key]

NativeMergeResult(pending, write) == GeneratedPendingWrite(pending, write[1], write[2])

SuccessfulNativeMergeHistory(count, writes, history) ==
    /\ DOMAIN history = 0..count
    /\ history[0] = EmptyPendingSlots
    /\ \A index \in 1..count :
           LET next == NativeMergeResult(history[index - 1], writes[index])
           IN /\ Len(next.updates) = 1
              /\ history[index] = next.updates[1]

NativeMaterializedSlots(fields, before, pending) ==
    [key \in fields |-> IF key \in DOMAIN pending THEN pending[key] ELSE before[key]]

NativePendingMergesEmit(fields, before, after, count, writes) ==
    \E history : SuccessfulNativeMergeHistory(count, writes, history)
        /\ [key \in fields |-> after[key]] =
               NativeMaterializedSlots(fields, before, history[count])

NativePendingWriteConstraints(fields, before, after, count, writes) ==
    /\ \A index \in 1..count : after[writes[index][1]] = writes[index][2]
    /\ \A key \in fields \ PendingWriteKeys(writes, count) : after[key] = before[key]

THEOREM GeneratedMergeAcceptsOnlyACompatibleSlot ==
    ASSUME NEW pending, NEW write, NEW result
    PROVE LET next == NativeMergeResult(pending, write)
          IN (Len(next.updates) = 1 /\ result = next.updates[1])
             <=> /\ (write[1] \notin DOMAIN pending \/ pending[write[1]] = write[2])
                 /\ result = [key \in DOMAIN pending \cup {write[1]} |->
                                  IF key = write[1] THEN write[2] ELSE pending[key]]
    BY SMT DEF NativeMergeResult, GeneratedPendingWrite, Outcomes!EmptyOrdered

THEOREM SuccessfulMergesRetainEveryWriteInThePrefix ==
    ASSUME NEW count \in Nat, NEW writes, NEW history,
           SuccessfulNativeMergeHistory(count, writes, history)
    PROVE \A prefix \in 0..count :
          /\ DOMAIN history[prefix] = PendingWriteKeys(writes, prefix)
          /\ \A index \in 1..prefix : history[prefix][writes[index][1]] = writes[index][2]
    PROOF
    <1>. DEFINE retained(index) ==
                    /\ DOMAIN history[index] = PendingWriteKeys(writes, index)
                    /\ \A visit \in 1..index :
                          history[index][writes[visit][1]] = writes[visit][2]
    <1>seed. retained(0)
        BY SMT DEF retained, SuccessfulNativeMergeHistory, EmptyPendingSlots, PendingWriteKeys
    <1>advance. ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : retained(prior)
                 PROVE retained(index)
        <2>prior. retained(index - 1)
            BY (index \in 1..count), (\A prior \in 0..(index - 1) : retained(prior)), SMT
        <2>. DEFINE previous == history[index - 1]
                    current == history[index]
                    target == writes[index][1]
                    value == writes[index][2]
        <2>actual. /\ Len(NativeMergeResult(previous, writes[index]).updates) = 1
                   /\ current = NativeMergeResult(previous, writes[index]).updates[1]
            BY (index \in 1..count), SMT DEF SuccessfulNativeMergeHistory, previous, current
        <2>rule. LET next == NativeMergeResult(previous, writes[index])
                 IN (Len(next.updates) = 1 /\ current = next.updates[1])
                    <=> /\ (target \notin DOMAIN previous \/ previous[target] = value)
                        /\ current = [key \in DOMAIN previous \cup {target} |->
                                           IF key = target THEN value ELSE previous[key]]
            BY ONLY GeneratedMergeAcceptsOnlyACompatibleSlot DEF target, value
        <2>step. /\ (target \notin DOMAIN previous \/ previous[target] = value)
                 /\ current = [key \in DOMAIN previous \cup {target} |->
                                    IF key = target THEN value ELSE previous[key]]
            BY ONLY <2>actual, <2>rule
        <2>keys. PendingWriteKeys(writes, index) = PendingWriteKeys(writes, index - 1) \cup {target}
            BY (index \in 1..count), SMT DEF PendingWriteKeys, target
        <2>domain. DOMAIN current = PendingWriteKeys(writes, index)
            BY <2>prior, <2>step, <2>keys, SMT DEF retained, previous
        <2>values. \A visit \in 1..index : current[writes[visit][1]] = writes[visit][2]
            PROOF
            <3>. SUFFICES ASSUME NEW visit \in 1..index
                         PROVE current[writes[visit][1]] = writes[visit][2]
                OBVIOUS
            <3>last. visit = index => current[writes[visit][1]] = writes[visit][2]
                BY <2>step, SMT DEF target, value
            <3>earlier. visit \in 1..(index - 1) => current[writes[visit][1]] = writes[visit][2]
                BY <2>prior, <2>step, SMT DEF retained, previous, PendingWriteKeys
            <3>. QED BY <3>last, <3>earlier, (visit \in 1..index), SMT
        <2>. QED BY <2>domain, <2>values DEF retained, current
    <1>induction. \A index \in 1..count :
        (\A prior \in 0..(index - 1) : retained(prior)) => retained(index)
        BY ONLY <1>advance, SMT
    <1>. DEFINE flags == [index \in 0..count |-> retained(index)]
    <1>flags. /\ flags \in [0..count -> BOOLEAN] /\ flags[0]
              /\ \A index \in 1..count :
                    (\A earlier \in 0..(index - 1) : flags[earlier]) => flags[index]
        BY ONLY (count \in Nat), <1>seed, <1>induction, SMT DEF flags
    <1>allFlags. \A index \in 0..count : flags[index]
        BY ONLY (count \in Nat), <1>flags, FiniteBooleanPrefixProperty
    <1>all. \A index \in 0..count : retained(index)
        BY ONLY (count \in Nat), <1>allFlags DEF flags
    <1>. QED BY <1>all DEF retained

THEOREM PendingMergeFoldMaterializesExactlyTheCompatibleWrites ==
    ASSUME NEW fields, NEW before, NEW after, NEW count \in Nat, NEW writes,
           \A index \in 1..count : writes[index][1] \in fields
    PROVE NativePendingMergesEmit(fields, before, after, count, writes)
          <=> NativePendingWriteConstraints(fields, before, after, count, writes)
    PROOF
    <1>forward. ASSUME NativePendingMergesEmit(fields, before, after, count, writes)
                 PROVE NativePendingWriteConstraints(fields, before, after, count, writes)
        <2>observed. PICK history :
            /\ SuccessfulNativeMergeHistory(count, writes, history)
            /\ [key \in fields |-> after[key]] = NativeMaterializedSlots(fields, before, history[count])
            BY NativePendingMergesEmit(fields, before, after, count, writes) DEF NativePendingMergesEmit
        <2>retained. /\ DOMAIN history[count] = PendingWriteKeys(writes, count)
                     /\ \A index \in 1..count : history[count][writes[index][1]] = writes[index][2]
            BY <2>observed, SuccessfulMergesRetainEveryWriteInThePrefix, SMT
        <2>. QED BY <2>observed, <2>retained, SMT
            DEF NativePendingWriteConstraints, NativeMaterializedSlots, PendingWriteKeys
    <1>reverse. ASSUME NativePendingWriteConstraints(fields, before, after, count, writes)
                 PROVE NativePendingMergesEmit(fields, before, after, count, writes)
        <2>. DEFINE pending(index) == [key \in PendingWriteKeys(writes, index) |-> after[key]]
                    history == [index \in 0..count |-> pending(index)]
        <2>zeroKeys. PendingWriteKeys(writes, 0) = {}
            BY ONLY SMT DEF PendingWriteKeys
        <2>empty. pending(0) = EmptyPendingSlots
            BY ONLY <2>zeroKeys, SMT DEF pending, EmptyPendingSlots
        <2>seed. /\ DOMAIN history = 0..count /\ history[0] = EmptyPendingSlots
            BY ONLY (count \in Nat), <2>empty, SMT DEF history
        <2>advance. \A index \in 1..count :
            LET next == NativeMergeResult(history[index - 1], writes[index])
            IN /\ Len(next.updates) = 1 /\ history[index] = next.updates[1]
            PROOF
            <3>. SUFFICES ASSUME NEW index \in 1..count
                         PROVE LET next == NativeMergeResult(history[index - 1], writes[index])
                               IN /\ Len(next.updates) = 1 /\ history[index] = next.updates[1]
                OBVIOUS
            <3>. DEFINE previous == pending(index - 1)
                        target == writes[index][1]
                        value == writes[index][2]
            <3>keys. PendingWriteKeys(writes, index) = PendingWriteKeys(writes, index - 1) \cup {target}
                BY (index \in 1..count), SMT DEF PendingWriteKeys, target
            <3>assigned. after[target] = value
                BY (index \in 1..count), NativePendingWriteConstraints(fields, before, after, count, writes),
                    SMT DEF NativePendingWriteConstraints, target, value
            <3>step. /\ (target \notin DOMAIN previous \/ previous[target] = value)
                     /\ pending(index) = [key \in DOMAIN previous \cup {target} |->
                                             IF key = target THEN value ELSE previous[key]]
                BY <3>keys, <3>assigned, SMT DEF pending, previous
            <3>rule. LET next == NativeMergeResult(previous, writes[index])
                     IN (Len(next.updates) = 1 /\ pending(index) = next.updates[1])
                        <=> /\ (target \notin DOMAIN previous \/ previous[target] = value)
                            /\ pending(index) = [key \in DOMAIN previous \cup {target} |->
                                                     IF key = target THEN value ELSE previous[key]]
                BY ONLY GeneratedMergeAcceptsOnlyACompatibleSlot DEF target, value
            <3>merged. LET next == NativeMergeResult(previous, writes[index])
                       IN /\ Len(next.updates) = 1 /\ pending(index) = next.updates[1]
                BY ONLY <3>step, <3>rule
            <3>states. /\ history[index - 1] = previous /\ history[index] = pending(index)
                BY ONLY (index \in 1..count), SMT DEF history, previous
            <3>. QED BY ONLY <3>merged, <3>states, SMT
        <2>successful. SuccessfulNativeMergeHistory(count, writes, history)
            BY <2>seed, <2>advance DEF SuccessfulNativeMergeHistory
        <2>complete. [key \in fields |-> after[key]] = NativeMaterializedSlots(fields, before, history[count])
            BY NativePendingWriteConstraints(fields, before, after, count, writes), SMT
                DEF history, pending, NativePendingWriteConstraints, NativeMaterializedSlots
        <2>exists. \E observed : SuccessfulNativeMergeHistory(count, writes, observed)
                                   /\ [key \in fields |-> after[key]] =
                                          NativeMaterializedSlots(fields, before, observed[count])
            PROOF
            <3>. WITNESS history
            <3>. QED BY <2>successful, <2>complete
        <2>. QED BY <2>exists DEF NativePendingMergesEmit
    <1>. QED BY <1>forward, <1>reverse
====
