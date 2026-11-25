---- MODULE OrderedScalarCopyRule ----
EXTENDS IndexedHistoryRules, Sequences
LOCAL INSTANCE SequenceTheorems_proofs
LOCAL BuilderFinite == INSTANCE FiniteSetTheorems

CopyReferenceValue(before, captures, reference) ==
    IF reference[1] = "capture" THEN captures[reference[2]]
    ELSE IF reference[1] = "literal" THEN reference[2] ELSE before[reference[2]]

CopyMaterializedState(keys, before, captures, writes) ==
    [key \in keys |-> CopyReferenceValue(before, captures, writes[key])]

CopyCaptureHistory(before, reads, captures) ==
    /\ DOMAIN captures = DOMAIN reads
    /\ \A index \in DOMAIN reads :
           captures[index] = CopyReferenceValue(before, captures, reads[index])

CopyEntryRoutes(keys) == [key \in keys |-> <<"state", key>>]

CopyReplace(keys, before, target, value) ==
    [key \in keys |-> IF key = target THEN value ELSE before[key]]

\* A capture is a lexical LET in visit order. The final routes describe actual primed equalities or UNCHANGED fields.
CopyPlan(keys, copies, reads, writes, routes) ==
    /\ Len(copies) \in Nat
    /\ DOMAIN copies = 1..Len(copies)
    /\ DOMAIN reads = 1..Len(copies)
    /\ routes[0] = CopyEntryRoutes(keys)
    /\ \A index \in 1..Len(copies) :
           /\ copies[index].target \in keys
           /\ copies[index].read \in keys
           /\ reads[index] = routes[index - 1][copies[index].read]
           /\ routes[index] = CopyReplace(keys, routes[index - 1],
                                  copies[index].target, <<"capture", index>>)
    /\ writes = routes[Len(copies)]

SourceCopyStateHistory(keys, copies, before, states) ==
    /\ DOMAIN states = 0..Len(copies)
    /\ states[0] = [key \in keys |-> before[key]]
    /\ \A index \in 1..Len(copies) :
           states[index] = CopyReplace(keys, states[index - 1], copies[index].target,
                               states[index - 1][copies[index].read])

SourceCopyBranch(keys, copies, before, after) ==
    \E states : SourceCopyStateHistory(keys, copies, before, states) /\ after = states[Len(copies)]

CompiledCopyBranch(keys, before, reads, writes, after) ==
    \E captures : CopyCaptureHistory(before, reads, captures)
                  /\ after = CopyMaterializedState(keys, before, captures, writes)

THEOREM CopyMaterializationCommutesWithRecordingOneWrite ==
    ASSUME NEW keys, NEW before, NEW captures, NEW routes, NEW target \in keys, NEW index
    PROVE CopyMaterializedState(keys, before, captures,
              CopyReplace(keys, routes, target, <<"capture", index>>))
          = CopyReplace(keys, CopyMaterializedState(keys, before, captures, routes),
                target, captures[index])
    BY SMT DEF CopyMaterializedState, CopyReplace, CopyReferenceValue

THEOREM OrderedScalarCopyPlanPreservesTheCompleteBranch ==
    ASSUME NEW keys, NEW copies, NEW before, NEW after, NEW reads, NEW writes, NEW routes,
           CopyPlan(keys, copies, reads, writes, routes)
    PROVE SourceCopyBranch(keys, copies, before, after)
          <=> CompiledCopyBranch(keys, before, reads, writes, after)
    PROOF
    <1>. DEFINE count == Len(copies)
                materialized(captures, index) == CopyMaterializedState(keys, before, captures, routes[index])
    <1>shape. /\ count \in Nat /\ DOMAIN reads = 1..count
              /\ writes = routes[count]
        BY SMT DEF CopyPlan, count
    <1>seed. \A captures : materialized(captures, 0) = [key \in keys |-> before[key]]
        BY SMT DEF CopyPlan, materialized, CopyEntryRoutes, CopyMaterializedState, CopyReferenceValue
    <1>step. \A captures : \A index \in 1..count :
        /\ CopyReferenceValue(before, captures, reads[index])
                = materialized(captures, index - 1)[copies[index].read]
        /\ materialized(captures, index) =
               CopyReplace(keys, materialized(captures, index - 1), copies[index].target, captures[index])
        PROOF
        <2>. SUFFICES ASSUME NEW captures, NEW index \in 1..count
                     PROVE /\ CopyReferenceValue(before, captures, reads[index])
                                  = materialized(captures, index - 1)[copies[index].read]
                           /\ materialized(captures, index) =
                                  CopyReplace(keys, materialized(captures, index - 1),
                                      copies[index].target, captures[index])
            OBVIOUS
        <2>route. /\ copies[index].target \in keys /\ copies[index].read \in keys
                  /\ reads[index] = routes[index - 1][copies[index].read]
                  /\ routes[index] = CopyReplace(keys, routes[index - 1], copies[index].target,
                                        <<"capture", index>>)
            BY SMT DEF CopyPlan, count
        <2>read. CopyReferenceValue(before, captures, reads[index])
                   = materialized(captures, index - 1)[copies[index].read]
            BY <2>route, SMT DEF materialized, CopyMaterializedState
        <2>write. materialized(captures, index) =
                     CopyReplace(keys, materialized(captures, index - 1), copies[index].target, captures[index])
            BY <2>route, CopyMaterializationCommutesWithRecordingOneWrite, SMT DEF materialized
        <2>. QED BY <2>read, <2>write
    <1>compiled. ASSUME CompiledCopyBranch(keys, before, reads, writes, after)
                  PROVE SourceCopyBranch(keys, copies, before, after)
        <2>physical. PICK captures : CopyCaptureHistory(before, reads, captures)
                           /\ after = CopyMaterializedState(keys, before, captures, writes)
            BY CompiledCopyBranch(keys, before, reads, writes, after) DEF CompiledCopyBranch
        <2>. DEFINE states == [index \in 0..count |-> materialized(captures, index)]
        <2>seed. states[0] = [key \in keys |-> before[key]]
            BY <1>shape, <1>seed, SMT DEF states
        <2>advance. \A index \in 1..count :
            states[index] = CopyReplace(keys, states[index - 1], copies[index].target,
                                states[index - 1][copies[index].read])
            BY <1>shape, <1>step, <2>physical, SMT DEF states, CopyCaptureHistory
        <2>complete. SourceCopyStateHistory(keys, copies, before, states) /\ after = states[count]
            BY <1>shape, <2>physical, <2>seed, <2>advance, SMT
               DEF count, states, materialized, SourceCopyStateHistory
        <2>exists. \E witness : SourceCopyStateHistory(keys, copies, before, witness)
                               /\ after = witness[count]
            PROOF
            <3>. WITNESS states
            <3>. QED BY <2>complete
        <2>. QED BY <2>exists DEF SourceCopyBranch, count
    <1>authored. ASSUME SourceCopyBranch(keys, copies, before, after)
                  PROVE CompiledCopyBranch(keys, before, reads, writes, after)
        <2>source. PICK states : SourceCopyStateHistory(keys, copies, before, states) /\ after = states[count]
            BY SourceCopyBranch(keys, copies, before, after) DEF SourceCopyBranch, count
        <2>. DEFINE captures == [index \in 1..count |-> states[index - 1][copies[index].read]]
                    agrees(index) == materialized(captures, index) = states[index]
        <2>seed. agrees(0)
            BY <1>seed, <2>source, SMT DEF agrees, SourceCopyStateHistory
        <2>advance. ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : agrees(prior)
                     PROVE agrees(index)
            <3>prior. agrees(index - 1)
                BY (index \in 1..count), (\A prior \in 0..(index - 1) : agrees(prior)), SMT
            <3>write. materialized(captures, index) =
                         CopyReplace(keys, materialized(captures, index - 1), copies[index].target, captures[index])
                BY <1>step, (index \in 1..count), SMT
            <3>source. states[index] = CopyReplace(keys, states[index - 1], copies[index].target,
                                           states[index - 1][copies[index].read])
                BY <2>source, (index \in 1..count), SMT DEF count, SourceCopyStateHistory
            <3>. QED BY <3>prior, <3>write, <3>source, (index \in 1..count), SMT DEF agrees, captures
        <2>prefix. \A index \in 0..count : agrees(index)
            BY <1>shape, <2>seed, <2>advance, FiniteIndexedPrefixProperty
        <2>history. CopyCaptureHistory(before, reads, captures)
            BY <1>shape, <1>step, <2>prefix, SMT DEF CopyCaptureHistory, agrees, captures
        <2>complete. after = CopyMaterializedState(keys, before, captures, writes)
            BY <1>shape, <2>source, <2>prefix, SMT DEF agrees, materialized
        <2>exists. \E witness : CopyCaptureHistory(before, reads, witness)
                               /\ after = CopyMaterializedState(keys, before, witness, writes)
            PROOF
            <3>. WITNESS captures
            <3>. QED BY <2>history, <2>complete
        <2>. QED BY <2>exists DEF CompiledCopyBranch
    <1>. QED BY <1>compiled, <1>authored

LastDirectCopy(copies, prefix, key, writer) ==
    /\ writer \in 0..prefix
    /\ (writer = 0 \/ copies[writer].target = key)
    /\ \A earlier \in 1..prefix : copies[earlier].target = key => earlier <= writer

DirectCopyWriter(copies, prefix, key) ==
    CHOOSE writer \in 0..prefix : LastDirectCopy(copies, prefix, key, writer)

DirectCopyReference(key, writer) == IF writer = 0 THEN <<"state", key>> ELSE <<"capture", writer>>

DirectCopyRoutes(keys, copies) ==
    [prefix \in 0..Len(copies) |-> [key \in keys |->
        DirectCopyReference(key, DirectCopyWriter(copies, prefix, key))]]

THEOREM TwoLastDirectCopiesHaveTheSamePosition ==
    ASSUME NEW copies, NEW prefix \in Nat, NEW key, NEW left, NEW right,
           LastDirectCopy(copies, prefix, key, left), LastDirectCopy(copies, prefix, key, right)
    PROVE left = right
    BY SMT DEF LastDirectCopy

THEOREM RecordingTheTargetDeterminesTheNextWriter ==
    ASSUME NEW copies, NEW index \in Nat, index > 0, NEW key, NEW writer,
           LastDirectCopy(copies, index - 1, key, writer)
    PROVE LastDirectCopy(copies, index, key,
              IF copies[index].target = key THEN index ELSE writer)
    PROOF
    <1>write. CASE copies[index].target = key
        BY <1>write, SMT DEF LastDirectCopy
    <1>keep. CASE copies[index].target # key
        BY <1>keep, SMT DEF LastDirectCopy
    <1>. QED BY <1>write, <1>keep

THEOREM EveryFiniteCopyPrefixHasALastWriter ==
    ASSUME NEW copies, NEW count \in Nat, NEW key
    PROVE \A prefix \in 0..count : \E writer \in 0..prefix : LastDirectCopy(copies, prefix, key, writer)
    PROOF
    <1>. DEFINE found(prefix) == \E writer \in 0..prefix : LastDirectCopy(copies, prefix, key, writer)
    <1>base. LastDirectCopy(copies, 0, key, 0)
        BY SMT DEF LastDirectCopy
    <1>init. found(0)
        BY ONLY <1>base, SMT DEF found
    <1>advance. ASSUME NEW prefix \in 1..count,
                       \A prior \in 0..(prefix - 1) : found(prior)
                 PROVE found(prefix)
        <2>positive. /\ prefix \in Nat /\ prefix > 0 /\ prefix - 1 \in 0..(prefix - 1)
            BY ONLY (count \in Nat), (prefix \in 1..count), SMT
        <2>previous. found(prefix - 1)
            BY ONLY <2>positive, (\A prior \in 0..(prefix - 1) : found(prior)), SMT
        <2>pick. PICK writer \in 0..(prefix - 1) : LastDirectCopy(copies, prefix - 1, key, writer)
            BY ONLY <2>previous DEF found
        <2>next. LastDirectCopy(copies, prefix, key,
                    IF copies[prefix].target = key THEN prefix ELSE writer)
            BY ONLY <2>positive, <2>pick, RecordingTheTargetDeterminesTheNextWriter, SMT
        <2>. QED BY ONLY <2>next, SMT DEF found, LastDirectCopy
    <1>. HIDE DEF found
    <1>induction. \A prefix \in 1..count :
        (\A prior \in 0..(prefix - 1) : found(prior)) => found(prefix)
        BY ONLY <1>advance, SMT
    <1>. DEFINE flags == [prefix \in 0..count |-> IF found(prefix) THEN TRUE ELSE FALSE]
    <1>flagType. flags \in [0..count -> BOOLEAN]
        BY ONLY SMT DEF flags
    <1>flagValue. \A prefix \in 0..count : flags[prefix] <=> found(prefix)
        BY ONLY SMT DEF flags
    <1>flagSeed. flags[0]
        BY ONLY (count \in Nat), <1>init, <1>flagValue, SMT
    <1>flagStep. \A prefix \in 1..count :
        (\A prior \in 0..(prefix - 1) : flags[prior]) => flags[prefix]
        <2>. SUFFICES ASSUME NEW prefix \in 1..count,
                             \A prior \in 0..(prefix - 1) : flags[prior]
                     PROVE flags[prefix]
            OBVIOUS
        <2>bounds. 0..(prefix - 1) \subseteq 0..count /\ prefix \in 0..count
            BY ONLY (count \in Nat), (prefix \in 1..count), SMT
        <2>found. \A prior \in 0..(prefix - 1) : found(prior)
            BY ONLY <2>bounds, <1>flagValue, (\A prior \in 0..(prefix - 1) : flags[prior]), SMT
        <2>. QED BY ONLY <2>bounds, <2>found, <1>induction, <1>flagValue, (prefix \in 1..count), SMT
    <1>allFlags. \A prefix \in 0..count : flags[prefix]
        BY ONLY (count \in Nat), <1>flagType, <1>flagSeed, <1>flagStep, FiniteBooleanPrefixProperty
    <1>all. \A prefix \in 0..count : found(prefix)
        BY ONLY <1>allFlags, <1>flagValue, SMT
    <1>. QED BY ONLY <1>all DEF found

THEOREM DirectCopyRoutesFollowEveryCapture ==
    ASSUME NEW keys, NEW copies, Len(copies) \in Nat
    PROVE /\ DirectCopyRoutes(keys, copies)[0] = CopyEntryRoutes(keys)
          /\ \A index \in 1..Len(copies) :
                 DirectCopyRoutes(keys, copies)[index] =
                     CopyReplace(keys, DirectCopyRoutes(keys, copies)[index - 1],
                         copies[index].target, <<"capture", index>>)
    PROOF
    <1>. DEFINE count == Len(copies)
                routes == DirectCopyRoutes(keys, copies)
    <1>exists. \A key \in keys : \A prefix \in 0..count :
        \E writer \in 0..prefix : LastDirectCopy(copies, prefix, key, writer)
        <2>. TAKE key \in keys
        <2>. QED BY ONLY (Len(copies) \in Nat), EveryFiniteCopyPrefixHasALastWriter, SMT DEF count
    <1>chosen. \A key \in keys : \A prefix \in 0..count :
        LastDirectCopy(copies, prefix, key, DirectCopyWriter(copies, prefix, key))
        BY <1>exists, SMT DEF DirectCopyWriter
    <1>initial. \A key \in keys : DirectCopyWriter(copies, 0, key) = 0
        BY <1>chosen, SMT DEF LastDirectCopy, count
    <1>seed. routes[0] = CopyEntryRoutes(keys)
        BY <1>initial, SMT DEF routes, DirectCopyRoutes, CopyEntryRoutes, DirectCopyReference, count
    <1>step. \A index \in 1..count :
        routes[index] = CopyReplace(keys, routes[index - 1], copies[index].target, <<"capture", index>>)
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..count
                     PROVE routes[index] =
                         CopyReplace(keys, routes[index - 1], copies[index].target, <<"capture", index>>)
            OBVIOUS
        <2>bounds. index \in 0..count /\ index - 1 \in 0..count /\ index - 1 \in Nat /\ index # 0
            BY (index \in 1..count), SMT
        <2>previous. \A key \in keys :
            LastDirectCopy(copies, index - 1, key, DirectCopyWriter(copies, index - 1, key))
            BY <1>chosen, <2>bounds, SMT
        <2>positive. /\ index \in Nat /\ index > 0
            BY ONLY (index \in 1..count), SMT
        <2>recorded. \A key \in keys :
            LastDirectCopy(copies, index, key,
                IF copies[index].target = key THEN index ELSE DirectCopyWriter(copies, index - 1, key))
            <3>. TAKE key \in keys
            <3>prior. LastDirectCopy(copies, index - 1, key, DirectCopyWriter(copies, index - 1, key))
                BY ONLY <2>previous, (key \in keys), SMT
            <3>. QED BY ONLY <3>prior, <2>positive, RecordingTheTargetDeterminesTheNextWriter, SMT
        <2>writers. \A key \in keys : DirectCopyWriter(copies, index, key) =
            IF copies[index].target = key THEN index ELSE DirectCopyWriter(copies, index - 1, key)
            BY <1>chosen, <2>bounds, <2>recorded, TwoLastDirectCopiesHaveTheSamePosition, SMT
        <2>. QED BY <2>bounds, <2>writers, SMT DEF routes, DirectCopyRoutes, DirectCopyReference, CopyReplace, count
    <1>. QED BY <1>step, <1>seed DEF routes, count

THEOREM DirectCopyRoutesAgreeWithRecordedPrefixes ==
    ASSUME NEW keys, NEW copies, Len(copies) \in Nat,
           NEW count \in 0..Len(copies), NEW maps,
           maps[1] = CopyEntryRoutes(keys),
           \A position \in 1..count :
               maps[position + 1] = CopyReplace(keys, maps[position], copies[position].target, <<"capture", position>>),
           NEW index \in 1..(count + 1)
    PROVE DirectCopyRoutes(keys, copies)[index - 1] = maps[index]
PROOF
<1>. DEFINE routes == DirectCopyRoutes(keys, copies)
            agrees(position) == routes[position] = maps[position + 1]
<1>count. count \in Nat
    BY ONLY (Len(copies) \in Nat), (count \in 0..Len(copies)), SMT
<1>routes. /\ routes[0] = CopyEntryRoutes(keys)
           /\ \A position \in 1..Len(copies) :
                  routes[position] = CopyReplace(keys, routes[position - 1], copies[position].target, <<"capture", position>>)
    BY ONLY (Len(copies) \in Nat), DirectCopyRoutesFollowEveryCapture DEF routes
<1>entry. agrees(0)
    BY ONLY <1>routes, (maps[1] = CopyEntryRoutes(keys)), SMT DEF agrees
<1>advance. ASSUME NEW position \in 1..count, \A prior \in 0..(position - 1) : agrees(prior)
             PROVE agrees(position)
    <2>bounds. /\ position - 1 \in 0..(position - 1)
               /\ (position - 1) + 1 = position
               /\ position \in 1..Len(copies)
        BY ONLY (Len(copies) \in Nat), (count \in 0..Len(copies)), <1>count, (position \in 1..count), SMT
    <2>prior. routes[position - 1] = maps[position]
        BY ONLY <2>bounds, (\A prior \in 0..(position - 1) : agrees(prior)), SMT DEF agrees
    <2>scheduled. routes[position] =
        CopyReplace(keys, routes[position - 1], copies[position].target, <<"capture", position>>)
        BY ONLY <2>bounds, <1>routes, SMT
    <2>recorded. maps[position + 1] = CopyReplace(keys, maps[position], copies[position].target, <<"capture", position>>)
        BY ONLY (position \in 1..count),
            (\A step \in 1..count : maps[step + 1] = CopyReplace(keys, maps[step], copies[step].target, <<"capture", step>>)), SMT
    <2>. QED BY ONLY <2>prior, <2>scheduled, <2>recorded, SMT DEF agrees
<1>. HIDE DEF agrees
<1>. DEFINE flags == [position \in 0..count |-> IF agrees(position) THEN TRUE ELSE FALSE]
<1>flagType. flags \in [0..count -> BOOLEAN]
    BY ONLY SMT DEF flags
<1>flagValue. \A position \in 0..count : flags[position] <=> agrees(position)
    BY ONLY SMT DEF flags
<1>flagSeed. flags[0]
    BY ONLY <1>count, <1>entry, <1>flagValue, SMT
<1>flagStep. \A position \in 1..count :
    (\A prior \in 0..(position - 1) : flags[prior]) => flags[position]
    <2>. SUFFICES ASSUME NEW position \in 1..count,
                         \A prior \in 0..(position - 1) : flags[prior]
                 PROVE flags[position]
        OBVIOUS
    <2>bounds. 0..(position - 1) \subseteq 0..count /\ position \in 0..count
        BY ONLY <1>count, (position \in 1..count), SMT
    <2>prior. \A prior \in 0..(position - 1) : agrees(prior)
        BY ONLY <2>bounds, <1>flagValue, (\A prior \in 0..(position - 1) : flags[prior]), SMT
    <2>. QED BY ONLY <2>bounds, <2>prior, <1>advance, <1>flagValue, (position \in 1..count), SMT
<1>allFlags. \A position \in 0..count : flags[position]
    BY ONLY <1>count, <1>flagType, <1>flagSeed, <1>flagStep, FiniteBooleanPrefixProperty
<1>all. \A position \in 0..count : agrees(position)
    BY ONLY <1>allFlags, <1>flagValue, SMT
<1>index. /\ index - 1 \in 0..count /\ (index - 1) + 1 = index
    BY ONLY <1>count, (index \in 1..(count + 1)), SMT
<1>prior. agrees(index - 1)
    BY ONLY <1>all, <1>index, SMT DEF agrees
<1>. QED BY ONLY <1>prior, <1>index, SMT DEF agrees, routes

\* Projection of the production loop at each visitation boundary. Captures are
\* numbered by the iteration that appended their binder, independent of its spelling.
DirectCopySchedulerStart(keys) == [reads |-> <<>>, writes |-> CopyEntryRoutes(keys)]

DirectCopySchedulerStep(keys, copy, index, prior) ==
    [reads |-> HistoryAppend(prior.reads, index - 1, prior.writes[copy.read]),
     writes |-> CopyReplace(keys, prior.writes, copy.target, <<"capture", index>>)]

DirectCopySchedulerExecution(keys, copies, states) ==
    /\ states[0] = DirectCopySchedulerStart(keys)
    /\ \A index \in 1..Len(copies) :
           states[index] = DirectCopySchedulerStep(keys, copies[index], index, states[index - 1])

DirectCopyReceiptAtPrefix(keys, copies, prefix) ==
    LET routes == DirectCopyRoutes(keys, copies)
    IN [reads |-> [index \in 1..prefix |-> routes[index - 1][copies[index].read]],
        writes |-> routes[prefix]]

DirectCopySchedulerFold(keys, copies) ==
    [prefix \in 0..Len(copies) |-> DirectCopyReceiptAtPrefix(keys, copies, prefix)]

DirectCopyScheduledReceipt(keys, copies) == DirectCopySchedulerFold(keys, copies)[Len(copies)]

THEOREM DirectCopySchedulerConstructsTheCompleteCapturePlan ==
    ASSUME NEW keys, NEW copies, Len(copies) \in Nat, DOMAIN copies = 1..Len(copies),
           \A index \in DOMAIN copies : copies[index].target \in keys /\ copies[index].read \in keys
    PROVE LET receipt == DirectCopyScheduledReceipt(keys, copies)
          IN /\ DOMAIN DirectCopySchedulerFold(keys, copies) = 0..Len(copies)
             /\ DirectCopySchedulerExecution(keys, copies, DirectCopySchedulerFold(keys, copies))
             /\ CopyPlan(keys, copies, receipt.reads, receipt.writes, DirectCopyRoutes(keys, copies))
             /\ \A states : DirectCopySchedulerExecution(keys, copies, states) => states[Len(copies)] = receipt
    PROOF
    <1>. DEFINE count == Len(copies)
                routes == DirectCopyRoutes(keys, copies)
                receipt(prefix) == DirectCopyReceiptAtPrefix(keys, copies, prefix)
    <1>routes. /\ routes[0] = CopyEntryRoutes(keys)
               /\ \A index \in 1..count :
                      routes[index] = CopyReplace(keys, routes[index - 1],
                          copies[index].target, <<"capture", index>>)
        BY DirectCopyRoutesFollowEveryCapture DEF count, routes
    <1>entry. receipt(0) = DirectCopySchedulerStart(keys)
        BY ONLY <1>routes, SMT DEF receipt, routes, DirectCopyReceiptAtPrefix, DirectCopySchedulerStart
    <1>transition. \A index \in 1..count :
        receipt(index) = DirectCopySchedulerStep(keys, copies[index], index, receipt(index - 1))
        <2>. TAKE index \in 1..count
        <2>bounds. index \in Nat /\ index > 0 /\ (index - 1) + 1 = index
            BY ONLY (index \in 1..count), SMT
        <2>write. receipt(index).writes = CopyReplace(keys, receipt(index - 1).writes,
                      copies[index].target, <<"capture", index>>)
            BY ONLY (index \in 1..count), <1>routes, SMT DEF receipt, routes, DirectCopyReceiptAtPrefix
        <2>read. receipt(index).reads = HistoryAppend(receipt(index - 1).reads, index - 1,
                     receipt(index - 1).writes[copies[index].read])
            BY ONLY <2>bounds, SMT DEF receipt, DirectCopyReceiptAtPrefix, HistoryAppend
        <2>. QED BY ONLY <2>write, <2>read, SMT DEF receipt, DirectCopyReceiptAtPrefix, DirectCopySchedulerStep
    <1>fold. /\ DOMAIN DirectCopySchedulerFold(keys, copies) = 0..Len(copies)
             /\ DirectCopySchedulerExecution(keys, copies, DirectCopySchedulerFold(keys, copies))
        BY ONLY (Len(copies) \in Nat), <1>entry, <1>transition, SMT
            DEF DirectCopySchedulerFold, DirectCopySchedulerExecution, count, receipt
    <1>plan. CopyPlan(keys, copies, receipt(count).reads, receipt(count).writes, routes)
        BY <1>routes, SMT DEF CopyPlan, receipt, DirectCopyReceiptAtPrefix, routes, count
    <1>actual. \A states : DirectCopySchedulerExecution(keys, copies, states) => states[count] = receipt(count)
        <2>. SUFFICES ASSUME NEW states, DirectCopySchedulerExecution(keys, copies, states)
                     PROVE states[count] = receipt(count)
            OBVIOUS
        <2>. DEFINE agrees(index) == states[index] = receipt(index)
        <2>initial. agrees(0)
            BY ONLY <1>entry, DirectCopySchedulerExecution(keys, copies, states), SMT
                DEF agrees, DirectCopySchedulerExecution
        <2>advance. ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : agrees(prior)
                     PROVE agrees(index)
            <3>prior. agrees(index - 1)
                BY ONLY (index \in 1..count), (\A prior \in 0..(index - 1) : agrees(prior)), SMT
            <3>step. states[index] = DirectCopySchedulerStep(keys, copies[index], index, states[index - 1])
                BY ONLY (index \in 1..count), DirectCopySchedulerExecution(keys, copies, states), SMT
                    DEF count, DirectCopySchedulerExecution
            <3>receipt. receipt(index) = DirectCopySchedulerStep(keys, copies[index], index, receipt(index - 1))
                BY ONLY (index \in 1..count), <1>transition, SMT
            <3>. QED BY ONLY <3>prior, <3>step, <3>receipt, SMT DEF agrees
        <2>. HIDE DEF agrees
        <2>all. \A index \in 0..count : agrees(index)
            BY ONLY (Len(copies) \in Nat), <2>initial, <2>advance, FiniteIndexedPrefixProperty DEF count
        <2>. QED BY ONLY (Len(copies) \in Nat), <2>all, SMT DEF agrees, count
    <1>returned. DirectCopyScheduledReceipt(keys, copies) = receipt(count)
        BY ONLY (Len(copies) \in Nat), SMT DEF DirectCopyScheduledReceipt, DirectCopySchedulerFold, receipt, count
    <1>. QED BY ONLY <1>fold, <1>plan, <1>actual, <1>returned DEF routes, count

\* Input has already been typed at the SwiftSyntax boundary. A binding is its
\* byte-identified local declaration. Its value is the associated formal state root.
DirectCopyTypedSyntax(keys, origins, raw) ==
    /\ origins \in [DOMAIN origins -> keys]
    /\ Len(raw) \in Nat \ {0}
    /\ DOMAIN raw = 1..Len(raw)
    /\ \A position \in DOMAIN raw :
           /\ raw[position].targetBinding \in DOMAIN origins
           /\ raw[position].readBinding \in DOMAIN origins

\* The parser resolves both references through its lexical scope. The builder
\* passes the corresponding SharedVariable values to Assign and flattens Do in order.
DirectCopyResolvedSyntax(origins, raw) ==
    [position \in DOMAIN raw |->
        [target |-> origins[raw[position].targetBinding], read |-> origins[raw[position].readBinding]]]

\* Assign builds .set(.root(handle.name), .variable(handle.name)).
\* Do maps its ordered wrapper array to the underlying statement array.
DirectCopyBuiltBody(origins, raw) ==
    [position \in DOMAIN raw |->
        <<"set", <<"root", origins[raw[position].targetBinding]>>,
                  <<"variable", origins[raw[position].readBinding]>>>>]

DirectCopyBuilderAccepts(keys, statement) ==
    /\ statement[1] = "set"
    /\ statement[2][1] = "root"
    /\ statement[3][1] = "variable"
    /\ statement[2][2] \in keys
    /\ statement[3][2] \in keys

DirectCopyBuilderOperands(statement) ==
    [target |-> statement[2][2], read |-> statement[3][2]]

DirectCopyBuilderBodyExecution(keys, body, count, history) ==
    /\ count \in Nat \ {0}
    /\ DOMAIN body = 1..count
    /\ history[0] = <<>>
    /\ \A position \in 1..count :
           /\ DirectCopyBuilderAccepts(keys, body[position])
           /\ history[position] = HistoryAppend(history[position - 1], position - 1,
                                      DirectCopyBuilderOperands(body[position]))

THEOREM DirectCopyBuilderBodyReturnsEveryResolvedOperandInOrder ==
    ASSUME NEW keys, NEW origins, NEW raw, DirectCopyTypedSyntax(keys, origins, raw)
    PROVE LET body == DirectCopyBuiltBody(origins, raw)
              copies == DirectCopyResolvedSyntax(origins, raw)
              count == Len(raw)
              history == [prefix \in 0..count |-> [position \in 1..prefix |-> copies[position]]]
          IN /\ DirectCopyBuilderBodyExecution(keys, body, count, history)
             /\ history[count] = copies
             /\ \A position \in DOMAIN raw :
                    /\ copies[position].target = origins[raw[position].targetBinding]
                    /\ copies[position].read = origins[raw[position].readBinding]
                    /\ copies[position].target \in keys /\ copies[position].read \in keys
    PROOF
    <1>. DEFINE body == DirectCopyBuiltBody(origins, raw)
                copies == DirectCopyResolvedSyntax(origins, raw)
                count == Len(raw)
                history == [prefix \in 0..count |-> [position \in 1..prefix |-> copies[position]]]
    <1>shape. /\ count \in Nat \ {0} /\ DOMAIN raw = 1..count
              /\ DOMAIN body = 1..count
        BY ONLY DirectCopyTypedSyntax(keys, origins, raw), SMT
            DEF DirectCopyTypedSyntax, DirectCopyBuiltBody, body, count
    <1>positions. \A position \in 1..count :
        /\ DirectCopyBuilderAccepts(keys, body[position])
        /\ DirectCopyBuilderOperands(body[position]) = copies[position]
        /\ copies[position].target = origins[raw[position].targetBinding]
        /\ copies[position].read = origins[raw[position].readBinding]
        /\ copies[position].target \in keys /\ copies[position].read \in keys
        <2>. TAKE position \in 1..count
        <2>roots. /\ origins[raw[position].targetBinding] \in keys
                  /\ origins[raw[position].readBinding] \in keys
            BY ONLY DirectCopyTypedSyntax(keys, origins, raw), <1>shape,
                (position \in 1..count), SMT DEF DirectCopyTypedSyntax
        <2>. QED BY ONLY <1>shape, <2>roots, (position \in 1..count), SMT
            DEF body, copies, DirectCopyBuiltBody, DirectCopyResolvedSyntax,
                DirectCopyBuilderAccepts, DirectCopyBuilderOperands
    <1>transition. \A position \in 1..count :
        history[position] = HistoryAppend(history[position - 1], position - 1,
                                DirectCopyBuilderOperands(body[position]))
        <2>. TAKE position \in 1..count
        <2>bounds. /\ position \in Nat \ {0} /\ position \in 0..count /\ position - 1 \in 0..count
            BY ONLY <1>shape, (position \in 1..count), SMT
        <2>prefix. HistoryPrefix(copies, position) =
                       HistoryAppend(HistoryPrefix(copies, position - 1), position - 1, copies[position])
            BY ONLY <2>bounds, SMT DEF HistoryPrefix, HistoryAppend
        <2>. QED BY ONLY <2>bounds, <2>prefix, <1>positions, (position \in 1..count), SMT DEF history, HistoryPrefix
    <1>entry. history[0] = <<>>
        BY ONLY <1>shape, SMT DEF history, HistoryPrefix
    <1>result. history[count] = copies
        BY ONLY <1>shape, SMT DEF history, HistoryPrefix, copies, DirectCopyResolvedSyntax
    <1>. QED BY ONLY <1>shape, <1>entry, <1>positions, <1>transition, <1>result, SMT
        DEF DirectCopyBuilderBodyExecution, body, copies, count, history

\* Reviewed scoped Algorithm builder order: declare shared Int handles, then
\* keep the ordered Do components. Direct-copy evidence rejects other components.
DirectCopyBuilderComponents(declarations, origins, steps) ==
    [position \in 1..(Len(declarations) + Len(steps)) |->
        IF position <= Len(declarations)
        THEN <<"shared", declarations[position], "Int">>
        ELSE LET step == steps[position - Len(declarations)]
             IN <<"step", step.label, DirectCopyBuiltBody(origins, step.copies), FALSE>>]

DirectCopyBuilderFields(components) ==
    {components[position][2] :
        position \in {index \in DOMAIN components : components[index][1] = "shared"}}

\* The increasing enumeration of the kept input positions specifies stable compactMap.
DirectCopyBuilderStepSelection(components, selected) ==
    /\ {selected[index] : index \in DOMAIN selected} =
        {position \in DOMAIN components : components[position][1] = "step"}
    /\ \A left, right \in DOMAIN selected : left < right => selected[left] < selected[right]

DirectCopyBuilderInventoryInput(keys, declarations, origins, steps) ==
    /\ Len(declarations) \in Nat \ {0}
    /\ declarations \in [1..Len(declarations) -> keys]
    /\ \A key \in keys : \E position \in 1..Len(declarations) : declarations[position] = key
    /\ \A left, right \in 1..Len(declarations) :
           declarations[left] = declarations[right] => left = right
    /\ Len(steps) \in Nat \ {0}
    /\ DOMAIN steps = 1..Len(steps)
    /\ \A index \in DOMAIN steps :
           steps[index].label \in STRING /\ DirectCopyTypedSyntax(keys, origins, steps[index].copies)

DirectCopyBuilderInventoryExecution(keys, declarations, origins, steps) ==
    LET components == DirectCopyBuilderComponents(declarations, origins, steps)
        selected == [index \in DOMAIN steps |-> Len(declarations) + index]
    IN /\ DirectCopyBuilderFields(components) = keys
       /\ keys # {}
       /\ DirectCopyBuilderStepSelection(components, selected)
       /\ BuilderFinite!Cardinality(keys) + Len(steps) = Len(components)
       /\ \A index \in DOMAIN steps :
        LET step == components[selected[index]]
            copies == DirectCopyResolvedSyntax(origins, steps[index].copies)
            count == Len(steps[index].copies)
            history == [prefix \in 0..count |-> [position \in 1..prefix |-> copies[position]]]
        IN /\ step[2] = steps[index].label /\ ~step[4]
           /\ DirectCopyBuilderBodyExecution(keys, step[3], count, history)
           /\ history[count] = copies

THEOREM DirectCopyBuilderConstructsEveryWellBoundInventory ==
    ASSUME NEW keys, NEW declarations, NEW origins, NEW steps,
           DirectCopyBuilderInventoryInput(keys, declarations, origins, steps)
    PROVE DirectCopyBuilderInventoryExecution(keys, declarations, origins, steps)
    PROOF
    <1>. DEFINE components == DirectCopyBuilderComponents(declarations, origins, steps)
                roots == Len(declarations)
                size == Len(steps)
                selected == [index \in DOMAIN steps |-> roots + index]
    <1>data. /\ roots \in Nat \ {0} /\ size \in Nat \ {0}
             /\ DOMAIN steps = 1..size
        BY ONLY DirectCopyBuilderInventoryInput(keys, declarations, origins, steps)
            DEF roots, size, DirectCopyBuilderInventoryInput
    <1>partitions. /\ DOMAIN components = 1..(roots + size)
                   /\ {index \in DOMAIN components : components[index][1] = "shared"} = 1..roots
                   /\ {index \in DOMAIN components : components[index][1] = "step"} = (roots + 1)..(roots + size)
        BY ONLY <1>data, SMT DEF components, DirectCopyBuilderComponents, roots, size
    <1>componentLength. Len(components) = roots + size
        <2>. DEFINE values == {components[position] : position \in DOMAIN components}
        <2>function. components \in [1..(roots + size) -> values]
            BY ONLY <1>partitions, SMT DEF components, DirectCopyBuilderComponents, roots, size, values
        <2>sequence. components \in Seq(values)
            BY ONLY <1>data, <2>function, SeqDef, SMT
        <2>typed. /\ Len(components) \in Nat /\ DOMAIN components = 1..Len(components)
            BY ONLY <2>sequence, LenProperties, SMT
        <2>interval. (1..Len(components)) = (1..(roots + size))
            BY ONLY <1>partitions, <2>typed, Zenon
        <2>. QED BY ONLY <1>data, <2>typed, <2>interval, SMT
    <1>nonempty. keys # {}
        BY ONLY <1>data, DirectCopyBuilderInventoryInput(keys, declarations, origins, steps), SMT
            DEF DirectCopyBuilderInventoryInput, roots
    <1>fields. DirectCopyBuilderFields(components) = keys
        BY ONLY <1>data, <1>partitions, DirectCopyBuilderInventoryInput(keys, declarations, origins, steps), SMT
            DEF DirectCopyBuilderFields, DirectCopyBuilderInventoryInput, components, DirectCopyBuilderComponents, roots
    <1>order. DirectCopyBuilderStepSelection(components, selected)
        <2>domain. DOMAIN selected = 1..size
            BY ONLY <1>data, SMT DEF selected
        <2>image. {selected[index] : index \in DOMAIN selected} = (roots + 1)..(roots + size)
            <3>forward. \A index \in DOMAIN selected : selected[index] \in (roots + 1)..(roots + size)
                BY ONLY <1>data, <2>domain, SMT DEF selected
            <3>backward. \A position \in (roots + 1)..(roots + size) :
                \E index \in DOMAIN selected : selected[index] = position
                <4>. TAKE position \in (roots + 1)..(roots + size)
                <4>index. position - roots \in DOMAIN selected
                    BY ONLY <1>data, <2>domain, (position \in (roots + 1)..(roots + size)), SMT
                <4>. WITNESS (position - roots) \in DOMAIN selected
                <4>. QED BY ONLY <1>data, <2>domain, <4>index, SMT DEF selected
            <3>. QED BY ONLY <3>forward, <3>backward, SMT
        <2>increasing. \A left, right \in DOMAIN selected : left < right => selected[left] < selected[right]
            BY ONLY <1>data, <2>domain, SMT DEF selected
        <2>. QED BY ONLY <1>partitions, <2>image, <2>increasing, SMT DEF DirectCopyBuilderStepSelection
    <1>count. BuilderFinite!Cardinality(keys) = roots
        <2>bijection. declarations \in BuilderFinite!Bijection(1..roots, keys)
            BY ONLY DirectCopyBuilderInventoryInput(keys, declarations, origins, steps), SMT
                DEF roots, DirectCopyBuilderInventoryInput, BuilderFinite!Bijection,
                    BuilderFinite!Injection, BuilderFinite!Surjection, BuilderFinite!IsInjective
        <2>exists. BuilderFinite!ExistsBijection(1..roots, keys)
            BY ONLY <2>bijection, SMT DEF BuilderFinite!ExistsBijection
        <2>. QED BY ONLY <1>data, <2>exists, BuilderFinite!FS_CountingElements, SMT
    <1>steps. \A index \in DOMAIN steps :
                    LET step == components[selected[index]]
                        copies == DirectCopyResolvedSyntax(origins, steps[index].copies)
                        count == Len(steps[index].copies)
                        history == [prefix \in 0..count |-> [position \in 1..prefix |-> copies[position]]]
                    IN /\ step[2] = steps[index].label /\ ~step[4]
                       /\ DirectCopyBuilderBodyExecution(keys, step[3], count, history)
                       /\ history[count] = copies
        <2>. TAKE index \in DOMAIN steps
        <2>position. /\ selected[index] \in (roots + 1)..(roots + size)
                      /\ selected[index] - roots = index
            BY ONLY <1>data, (index \in DOMAIN steps), SMT DEF selected
        <2>model. components[selected[index]] =
                       <<"step", steps[index].label, DirectCopyBuiltBody(origins, steps[index].copies), FALSE>>
            BY ONLY <1>data, <2>position, SMT DEF components, DirectCopyBuilderComponents, roots, size
        <2>typed. DirectCopyTypedSyntax(keys, origins, steps[index].copies)
            BY ONLY DirectCopyBuilderInventoryInput(keys, declarations, origins, steps),
                (index \in DOMAIN steps), SMT DEF DirectCopyBuilderInventoryInput
        <2>. QED BY ONLY <2>model, <2>typed, DirectCopyBuilderBodyReturnsEveryResolvedOperandInOrder, SMT
    <1>. QED BY ONLY <1>fields, <1>nonempty, <1>order, <1>count, <1>componentLength, <1>steps, SMT
        DEF DirectCopyBuilderInventoryExecution, roots, size, components, selected

THEOREM DirectCopyTypedFrontendConstructsTheCompleteCapturePlan ==
    ASSUME NEW keys, NEW origins, NEW raw, DirectCopyTypedSyntax(keys, origins, raw)
    PROVE LET copies == DirectCopyResolvedSyntax(origins, raw)
              receipt == DirectCopyScheduledReceipt(keys, copies)
          IN /\ Len(copies) = Len(raw)
             /\ DOMAIN copies = DOMAIN raw
             /\ \A position \in DOMAIN raw :
                    /\ copies[position].target = origins[raw[position].targetBinding]
                    /\ copies[position].read = origins[raw[position].readBinding]
                    /\ copies[position].target \in keys
                    /\ copies[position].read \in keys
             /\ CopyPlan(keys, copies, receipt.reads, receipt.writes, DirectCopyRoutes(keys, copies))
    PROOF
    <1>. DEFINE copies == DirectCopyResolvedSyntax(origins, raw)
                shape == [target: keys, read: keys]
                receipt == DirectCopyScheduledReceipt(keys, copies)
    <1>domain. DOMAIN copies = DOMAIN raw
        BY ONLY SMT DEF copies, DirectCopyResolvedSyntax
    <1>points. \A position \in DOMAIN raw :
            /\ copies[position].target = origins[raw[position].targetBinding]
            /\ copies[position].read = origins[raw[position].readBinding]
            /\ copies[position].target \in keys
            /\ copies[position].read \in keys
        BY ONLY DirectCopyTypedSyntax(keys, origins, raw),
            DirectCopyBuilderBodyReturnsEveryResolvedOperandInOrder DEF copies
    <1>typed. copies \in [1..Len(raw) -> shape]
        BY ONLY DirectCopyTypedSyntax(keys, origins, raw), <1>domain, <1>points, SMT
            DEF DirectCopyTypedSyntax, copies, shape, DirectCopyResolvedSyntax
    <1>sequence. copies \in Seq(shape)
        BY ONLY DirectCopyTypedSyntax(keys, origins, raw), <1>typed, SeqDef, SMT
            DEF DirectCopyTypedSyntax
    <1>length. /\ Len(copies) \in Nat /\ DOMAIN copies = 1..Len(copies)
        BY ONLY <1>sequence, LenProperties, SMT
    <1>count. Len(copies) = Len(raw)
        BY ONLY DirectCopyTypedSyntax(keys, origins, raw), <1>domain, <1>length, SMT
            DEF DirectCopyTypedSyntax
    <1>schedule. CopyPlan(keys, copies, receipt.reads, receipt.writes, DirectCopyRoutes(keys, copies))
        BY ONLY <1>length, <1>domain, <1>points, DirectCopySchedulerConstructsTheCompleteCapturePlan, SMT DEF receipt
    <1>. QED BY ONLY <1>count, <1>domain, <1>points, <1>schedule

THEOREM CopyCaptureHistoryIsUnique ==
    ASSUME NEW before, NEW reads, NEW left, NEW right,
           Len(reads) \in Nat, DOMAIN reads = 1..Len(reads),
           \A index \in DOMAIN reads :
               reads[index][1] = "capture" => reads[index][2] \in 1..(index - 1),
           CopyCaptureHistory(before, reads, left), CopyCaptureHistory(before, reads, right)
    PROVE \A index \in DOMAIN reads : left[index] = right[index]
    PROOF
    <1>. DEFINE count == Len(reads)
                agrees(index) == index = 0 \/ left[index] = right[index]
    <1>entry. agrees(0)
        BY ONLY SMT DEF agrees
    <1>advance. ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : agrees(prior)
                 PROVE agrees(index)
        <2>read. /\ left[index] = CopyReferenceValue(before, left, reads[index])
                  /\ right[index] = CopyReferenceValue(before, right, reads[index])
            BY (index \in 1..count), SMT DEF CopyCaptureHistory, count
        <2>operand. reads[index][1] = "capture" => left[reads[index][2]] = right[reads[index][2]]
            BY (index \in 1..count), (\A prior \in 0..(index - 1) : agrees(prior)), SMT DEF count, agrees
        <2>. QED BY ONLY <2>read, <2>operand, SMT DEF agrees, CopyReferenceValue
    <1>. HIDE DEF agrees
    <1>all. \A index \in 0..count : agrees(index)
        BY ONLY (Len(reads) \in Nat), <1>entry, <1>advance, FiniteIndexedPrefixProperty DEF count
    <1>. QED BY <1>all, SMT DEF agrees, count

THEOREM DirectCopyReceiptSuppliesTheCompleteCapturePlan ==
    ASSUME NEW keys, NEW copies, NEW reads, NEW writes,
           Len(copies) \in Nat, DOMAIN copies = 1..Len(copies), DOMAIN reads = DOMAIN copies,
           \A index \in DOMAIN copies :
               /\ copies[index].target \in keys
               /\ copies[index].read \in keys
               /\ reads[index] = DirectCopyRoutes(keys, copies)[index - 1][copies[index].read],
           writes = DirectCopyRoutes(keys, copies)[Len(copies)]
    PROVE CopyPlan(keys, copies, reads, writes, DirectCopyRoutes(keys, copies))
    BY DirectCopyRoutesFollowEveryCapture, SMT DEF CopyPlan

====
