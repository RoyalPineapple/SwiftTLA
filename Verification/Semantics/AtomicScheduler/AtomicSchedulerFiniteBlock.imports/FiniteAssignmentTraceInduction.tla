---- MODULE FiniteAssignmentTraceInduction ----
EXTENDS AtomicPriorReadBindings

CONSTANTS TraceReady(_, _), TraceNext(_, _), TraceLet(_, _, _), TraceRow(_, _, _),
          TraceEmpty(_), TraceEdge(_, _, _, _, _), TracePredecessor(_), TraceBindingsField,
          TraceAssignmentRhsCertificate(_), TraceSubstitution(_, _), TraceNameWrite(_, _, _)

TraceSupportedAssignmentList(rows) ==
    /\ Len(rows) \in Nat
    /\ DOMAIN rows = 1..Len(rows)
    /\ \A index \in DOMAIN rows : rows[index].target \in Keys /\ TraceAssignmentRhsCertificate(rows[index])

TraceOldNames(entry) ==
    LET bindings == entry.old[TraceBindingsField]
    IN [key \in DOMAIN bindings |-> bindings[key].variable]

TraceStepWithReadWriteMaps(entry, child, returned, suffix, row) ==
    /\ TraceEdge(entry, child, returned, suffix, row)
    /\ row.substitutedRhs = TraceSubstitution(row.view,TraceOldNames(entry))
    /\ TraceOldNames(child) = TraceNameWrite(TraceOldNames(entry),row.target,row.binding)

\* The concrete caller proves these conditions for one supported source head,
\* using the real compiler operators it substitutes for each parameter.
HeadTracePostcondition(entry, shapes, context) ==
    LET child == TraceNext(entry, context)
    IN /\ TraceReady(child, shapes)
       /\ child.values = Tail(entry.values)
       /\ \A suffix :
           LET row == TraceRow(entry, context, suffix)
               returned == TraceLet(entry, context, suffix)
           IN /\ TraceStepWithReadWriteMaps(entry, child, returned, suffix, row)
              /\ row.target \in Keys /\ TraceAssignmentRhsCertificate(row)
              /\ row.target = entry.values[1].target /\ row.sourceRhs = entry.values[1].rhs
              /\ row.binding \notin entry.allocator.used
              /\ row.predecessor = TracePredecessor(entry.old)
              /\ TracePredecessor(child.old) = row.binding
              /\ child.allocator.used = entry.allocator.used \cup {row.binding}

FiniteScheduleReturns(entry, trace) ==
    LET count == Len(entry.values)
        last == count + 1
    IN /\ DOMAIN trace.entries = 1..last
       /\ DOMAIN trace.bodies = 1..last
       /\ DOMAIN trace.rows = 1..count
       /\ trace.entries[1] = entry
       /\ trace.entries[last].values = <<>>
       /\ trace.bodies[last] = TraceEmpty(trace.entries[last])
       /\ \A index \in 1..count :
           TraceStepWithReadWriteMaps(trace.entries[index], trace.entries[index + 1],
                                   trace.bodies[index], trace.bodies[index + 1],
                                   trace.rows[index])

TracePreservesOccurrences(entry, rows) ==
    /\ \A i \in 1..Len(rows) :
           /\ rows[i].target = entry.values[i].target
           /\ rows[i].sourceRhs = entry.values[i].rhs
           /\ rows[i].binding \notin entry.allocator.used
           /\ rows[i].predecessor =
                IF i = 1 THEN TracePredecessor(entry.old) ELSE rows[i-1].binding
    /\ \A i,j \in 1..Len(rows) : rows[i].binding = rows[j].binding => i = j

PrependTrace(value, tail, count) ==
    [index \in 1..(count+1) |-> IF index = 1 THEN value ELSE tail[index-1]]

TraceStatesAreReady(trace, shapes) ==
    \A i \in DOMAIN trace.entries : TraceReady(trace.entries[i], shapes)

THEOREM HeadAndTailConstructTheFiniteReturn ==
    ASSUME NEW shapes,
           \A entry : TraceReady(entry, shapes) => entry.values \in Seq(shapes),
           \A entry : TraceReady(entry, shapes) /\ entry.values # <<>> =>
               \E context : HeadTracePostcondition(entry, shapes, context)
    PROVE \A entry :
        TraceReady(entry, shapes) =>
            \E trace : FiniteScheduleReturns(entry, trace)
                       /\ TraceSupportedAssignmentList(trace.rows)
                       /\ TracePreservesOccurrences(entry, trace.rows)
                           /\ TraceStatesAreReady(trace, shapes)
                       /\ Len(trace.rows) = Len(entry.values)
PROOF
<1>. DEFINE P(n) == \A entry :
            TraceReady(entry, shapes) /\ Len(entry.values) = n =>
                \E trace : FiniteScheduleReturns(entry, trace)
                           /\ TraceSupportedAssignmentList(trace.rows)
                           /\ TracePreservesOccurrences(entry, trace.rows)
                           /\ TraceStatesAreReady(trace, shapes)
                           /\ Len(trace.rows) = n
<1>zero. P(0)
    <2>. SUFFICES ASSUME NEW entry, TraceReady(entry, shapes), Len(entry.values) = 0
                  PROVE \E trace : FiniteScheduleReturns(entry, trace)
                          /\ TraceSupportedAssignmentList(trace.rows)
                           /\ TracePreservesOccurrences(entry, trace.rows)
                           /\ TraceStatesAreReady(trace, shapes)
                           /\ Len(trace.rows) = 0
        BY DEF P
    <2>. DEFINE trace == [entries |-> <<entry>>, bodies |-> <<TraceEmpty(entry)>>, rows |-> <<>>]
    <2>empty. entry.values = <<>>
        BY ONLY TraceReady(entry, shapes), (Len(entry.values) = 0),
            (\A input : TraceReady(input, shapes) => input.values \in Seq(shapes)), LenProperties, SeqDef, SMT
    <2>returns. FiniteScheduleReturns(entry, trace)
        BY ONLY <2>empty, (Len(entry.values) = 0), SMT DEF FiniteScheduleReturns, trace
    <2>rows. /\ TraceSupportedAssignmentList(trace.rows)
             /\ TracePreservesOccurrences(entry, trace.rows)
                           /\ TraceStatesAreReady(trace, shapes)
             /\ Len(trace.rows) = 0
        BY ONLY TraceReady(entry, shapes), SMT
            DEF TraceSupportedAssignmentList, TracePreservesOccurrences, TraceStatesAreReady, trace
    <2>. WITNESS trace
    <2>. QED BY ONLY <2>returns, <2>rows
<1>advance. \A n \in Nat : P(n) => P(n + 1)
    <2>. SUFFICES ASSUME NEW n \in Nat, P(n)
                  PROVE P(n + 1)
        OBVIOUS
    <2>. SUFFICES ASSUME NEW entry, TraceReady(entry, shapes), Len(entry.values) = n + 1
                  PROVE \E trace : FiniteScheduleReturns(entry, trace)
                          /\ TraceSupportedAssignmentList(trace.rows)
                           /\ TracePreservesOccurrences(entry, trace.rows)
                           /\ TraceStatesAreReady(trace, shapes)
                           /\ Len(trace.rows) = n + 1
        BY DEF P
    <2>sequenceInput. entry.values \in Seq(shapes)
        BY ONLY TraceReady(entry, shapes), (\A input : TraceReady(input, shapes) => input.values \in Seq(shapes)), SMT
    <2>head. entry.values # <<>>
        BY ONLY <2>sequenceInput, (Len(entry.values) = n + 1), (n \in Nat), EmptySeq, LenProperties, SMT
    <2>context. PICK context : HeadTracePostcondition(entry, shapes, context)
        BY ONLY TraceReady(entry, shapes), <2>head,
            (\A input : TraceReady(input, shapes) /\ input.values # <<>> =>
                \E witness : HeadTracePostcondition(input, shapes, witness)), SMT
    <2>. DEFINE child == TraceNext(entry, context)
    <2>child. /\ TraceReady(child, shapes)
              /\ child.values = Tail(entry.values)
              /\ Len(child.values) = n
        BY ONLY <2>context, <2>sequenceInput, (Len(entry.values) = n+1), <2>head,
            HeadTailProperties, SMT DEF HeadTracePostcondition, child
    <2>suffix. PICK tail : FiniteScheduleReturns(child, tail)
                          /\ TraceSupportedAssignmentList(tail.rows)
                          /\ TracePreservesOccurrences(child, tail.rows)
                          /\ TraceStatesAreReady(tail, shapes)
                          /\ Len(tail.rows) = n
        BY ONLY <2>child, P(n), SMT DEF P
    <2>. DEFINE returned == TraceLet(entry, context, tail.bodies[1])
                row == TraceRow(entry, context, tail.bodies[1])
                trace == [entries |-> PrependTrace(entry, tail.entries, n+1),
                          bodies |-> PrependTrace(returned, tail.bodies, n+1),
                          rows |-> PrependTrace(row, tail.rows, n)]
    <2>matched. /\ TraceStepWithReadWriteMaps(entry, child, returned, tail.bodies[1], row)
                /\ row.target \in Keys /\ TraceAssignmentRhsCertificate(row)
                /\ row.target = entry.values[1].target /\ row.sourceRhs = entry.values[1].rhs
                /\ row.binding \notin entry.allocator.used
                /\ row.predecessor = TracePredecessor(entry.old)
                /\ TracePredecessor(child.old) = row.binding
                /\ child.allocator.used = entry.allocator.used \cup {row.binding}
        BY ONLY <2>context, SMT DEF HeadTracePostcondition, child, row, returned
    <2>shifts. /\ DOMAIN trace.entries = 1..(n+2)
               /\ DOMAIN trace.bodies = 1..(n+2)
               /\ DOMAIN trace.rows = 1..(n+1)
               /\ trace.entries[1] = entry /\ trace.bodies[1] = returned /\ trace.rows[1] = row
               /\ \A i \in 1..(n+1) :
                      trace.entries[i+1] = tail.entries[i] /\ trace.bodies[i+1] = tail.bodies[i]
               /\ \A i \in 1..n : trace.rows[i+1] = tail.rows[i]
        BY ONLY (n \in Nat), SMT DEF trace, PrependTrace
    <2>sequence. Len(trace.rows) = n+1
        <3>. DEFINE elements == {trace.rows[i] : i \in 1..(n+1)}
        <3>typed. trace.rows \in [1..(n+1) -> elements]
            BY ONLY (n \in Nat), <2>shifts, SMT DEF trace, PrependTrace, elements
        <3>isSeq. trace.rows \in Seq(elements)
            BY ONLY (n \in Nat), <3>typed, SeqDef, SMT
        <3>. QED BY ONLY (n \in Nat), <3>typed, <3>isSeq, LenProperties, SMT
    <2>supportedRows. \A i \in 1..(n+1) : trace.rows[i].target \in Keys /\ TraceAssignmentRhsCertificate(trace.rows[i])
        <3>. TAKE i \in 1..(n+1)
        <3>first. CASE i = 1
            BY ONLY <3>first, <2>matched, <2>shifts, SMT
        <3>later. CASE i # 1
            <4>bounds. i-1 \in DOMAIN tail.rows /\ i-1 \in 1..n
                BY ONLY <3>later, <2>suffix, (i \in 1..(n+1)), SMT DEF TraceSupportedAssignmentList
            <4>value. trace.rows[i] = tail.rows[i-1]
                BY ONLY <4>bounds, <2>shifts, SMT
            <4>. QED BY ONLY <4>bounds, <4>value, <2>suffix, SMT DEF TraceSupportedAssignmentList
        <3>. QED BY ONLY <3>first, <3>later, SMT
    <2>supported. /\ TraceSupportedAssignmentList(trace.rows) /\ Len(trace.rows) = n+1
        BY ONLY (n \in Nat), <2>supportedRows, <2>shifts, <2>sequence, SMT DEF TraceSupportedAssignmentList
    <2>order. \A i \in 1..(n+1) :
                 /\ trace.rows[i].target = entry.values[i].target
                 /\ trace.rows[i].sourceRhs = entry.values[i].rhs
                 /\ trace.rows[i].binding \notin entry.allocator.used
                 /\ trace.rows[i].predecessor =
                      IF i = 1 THEN TracePredecessor(entry.old) ELSE trace.rows[i-1].binding
        <3>. TAKE i \in 1..(n+1)
        <3>first. CASE i = 1
            BY ONLY <3>first, <2>matched, <2>shifts, <2>head, SMT
        <3>later. CASE i > 1
            <4>coordinates. i-1 \in 1..n /\ trace.rows[i] = tail.rows[i-1]
                BY ONLY (i \in 1..(n+1)), <3>later, <2>shifts, SMT
            <4>source. child.values[i-1] = entry.values[i]
                BY ONLY <4>coordinates, <2>child, <2>sequenceInput, <2>head,
                    HeadTailProperties, SMT
            <4>semantic. /\ trace.rows[i].target = entry.values[i].target
                          /\ trace.rows[i].sourceRhs = entry.values[i].rhs
                          /\ trace.rows[i].binding \notin entry.allocator.used
                          /\ trace.rows[i].predecessor =
                               IF i=2 THEN row.binding ELSE tail.rows[i-2].binding
                BY ONLY <2>suffix, <2>matched, <4>coordinates, <4>source, SMT DEF TracePreservesOccurrences
            <4>. QED BY ONLY <4>semantic, <3>later, <2>shifts, (i \in 1..(n+1)), SMT
        <3>. QED BY ONLY <3>first, <3>later, (i \in 1..(n+1)), SMT
    <2>distinct. \A i,j \in 1..(n+1) : trace.rows[i].binding = trace.rows[j].binding => i=j
        <3>. TAKE i,j \in 1..(n+1)
        <3>same. CASE i=j
            BY ONLY <3>same
        <3>headFirst. CASE i=1 /\ i#j
            BY ONLY <3>headFirst, (j \in 1..(n+1)), <2>matched, <2>shifts, <2>suffix, SMT
                DEF TracePreservesOccurrences
        <3>headLast. CASE j=1 /\ i#j
            BY ONLY <3>headLast, (i \in 1..(n+1)), <2>matched, <2>shifts, <2>suffix, SMT
                DEF TracePreservesOccurrences
        <3>tail. CASE i#1 /\ j#1
            BY ONLY <3>tail, (i \in 1..(n+1)), (j \in 1..(n+1)), <2>shifts, <2>suffix, SMT
                DEF TracePreservesOccurrences
        <3>. QED BY ONLY <3>same, <3>headFirst, <3>headLast, <3>tail, SMT
    <2>occurrences. TracePreservesOccurrences(entry, trace.rows)
        BY ONLY <2>order, <2>distinct, <2>supported, SMT DEF TracePreservesOccurrences
    <2>boundary. /\ trace.entries[n+2].values = <<>>
                  /\ trace.bodies[n+2] = TraceEmpty(trace.entries[n+2])
        BY ONLY (n \in Nat), <2>child, <2>suffix, <2>shifts, SMT DEF FiniteScheduleReturns
    <2>initial. TraceStepWithReadWriteMaps(trace.entries[1], trace.entries[2], trace.bodies[1], trace.bodies[2], trace.rows[1])
        BY ONLY (n \in Nat), <2>suffix, <2>shifts, <2>matched, SMT DEF FiniteScheduleReturns
    <2>readyEntries. TraceStatesAreReady(trace, shapes)
        BY ONLY TraceReady(entry, shapes), <2>suffix, <2>shifts, <2>child,
            (n \in Nat), SMT DEF TraceStatesAreReady, FiniteScheduleReturns
    <2>rest. \A i \in 2..(n+1) :
                TraceStepWithReadWriteMaps(trace.entries[i], trace.entries[i+1], trace.bodies[i],
                                       trace.bodies[i+1], trace.rows[i])
        <3>. TAKE i \in 2..(n+1)
        <3>prior. i-1 \in 1..n /\ i \in 1..(n+1)
            BY ONLY (i \in 2..(n+1)), (n \in Nat), SMT
        <3>unshift. TraceStepWithReadWriteMaps(tail.entries[i-1], tail.entries[i], tail.bodies[i-1],
                                           tail.bodies[i], tail.rows[i-1])
            BY ONLY <3>prior, <2>child, <2>suffix, SMT DEF FiniteScheduleReturns
        <3>. QED BY ONLY <3>prior, <3>unshift, <2>shifts, SMT
    <2>returns. FiniteScheduleReturns(entry, trace)
        BY ONLY (Len(entry.values) = n + 1), (n \in Nat), <2>shifts, <2>boundary, <2>initial,
            <2>rest, SMT DEF FiniteScheduleReturns
    <2>. WITNESS trace
    <2>. QED BY ONLY <2>returns, <2>supported, <2>occurrences, <2>readyEntries
<1>. HIDE DEF P
<1>all. \A n \in Nat : P(n)
    BY ONLY <1>zero, <1>advance, NatInduction
<1>. TAKE entry
<1>. SUFFICES ASSUME TraceReady(entry, shapes)
              PROVE \E trace : FiniteScheduleReturns(entry, trace)
                       /\ TraceSupportedAssignmentList(trace.rows)
                           /\ TracePreservesOccurrences(entry, trace.rows)
                           /\ TraceStatesAreReady(trace, shapes)
                           /\ Len(trace.rows) = Len(entry.values)
    OBVIOUS
<1>induction. P(Len(entry.values))
    BY ONLY TraceReady(entry, shapes), (\A input : TraceReady(input, shapes) => input.values \in Seq(shapes)),
        <1>all, LenProperties, SMT
<1>. QED BY ONLY <1>induction, TraceReady(entry, shapes), SMT DEF P


====
