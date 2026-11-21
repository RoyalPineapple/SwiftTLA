---- MODULE OrderedScalarCopyRule ----
EXTENDS IndexedHistoryRules, Sequences

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
====
