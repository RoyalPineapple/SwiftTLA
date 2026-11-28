---- MODULE AtomicSchedulerFiniteBlock ----
EXTENDS AtomicSchedulerEntrySource, SchedulerCallStack, AtomicSchedulerHandoff, AtomicSchedulerSingleSet, AtomicPriorReadBindings, AtomicSchedulerEmptyReturnSource, StandaloneAtomicRun

SchedulerEmptyEntry(entry) ==
    [key \in {SchedulerNameValues, SchedulerNameAssignments} |->
        IF key = SchedulerNameValues THEN entry.values ELSE entry.assignments]

SchedulerActualEmptyValue(entry) == SchedulerEmptyReturn(SchedulerEmptyEntry(entry))

\* rows are a proof projection of the actual compiled LET and the actual
\* orderedIntCertificate invocation for its paired source RHS. They are not
\* the Swift array returned by scheduleAtomicStatements.
SchedulerBlockRow(statement, step, result, returned) ==
    LET row == SchedulerAssignmentRhsRow(statement.target, result)
    IN [target |-> row.target, view |-> row.view, emitted |-> row.emitted,
        inverse |-> row.inverse, fallback |-> row.fallback,
        binding |-> returned[1].variable, predecessor |-> step.descriptor.predecessor,
        substitutedRhs |-> returned[1].value, sourceRhs |-> statement.rhs]

SchedulerActualSetTrace(current, next, returned, body, row) ==
    LET statement == Head(current.values)
    IN /\ current.values # <<>>
       /\ \E compiled :
             /\ SchedulerAssignmentRhsInvocation(statement, compiled)
             /\ LET step == SchedulerActualSetStep(current, compiled)
                IN /\ next = step.next
                   /\ returned = SchedulerActualSetValue(step, body)
                   /\ row = SchedulerBlockRow(statement, step, compiled, returned)

SchedulerPreviousBinding(old) ==
    LET previous == old[SchedulerRecordingLastWriteField]
    IN IF previous = <<>> THEN <<>> ELSE previous[SchedulerNameBinding]

SchedulerHeadNext(entry, compiled) == SchedulerActualSetStep(entry, compiled).next
SchedulerHeadLet(entry, compiled, suffix) == SchedulerActualSetValue(SchedulerActualSetStep(entry, compiled), suffix)
SchedulerHeadRow(entry, compiled, suffix) ==
    SchedulerBlockRow(Head(entry.values), SchedulerActualSetStep(entry, compiled), compiled,
                      SchedulerHeadLet(entry, compiled, suffix))

SchedulerOldNames(entry) == StateExprIncomingVariableNames(entry.old[SchedulerRootBindingsField])

LOCAL TraceConstruction == INSTANCE FiniteAssignmentTraceQuantifiedInduction
    WITH TraceReady <- SchedulerBlockEntryReady,
         TraceNext <- SchedulerHeadNext,
         TraceLet <- SchedulerHeadLet,
         TraceRow <- SchedulerHeadRow,
         TraceEmpty <- SchedulerActualEmptyValue,
         TraceEdge <- SchedulerActualSetTrace,
         TracePredecessor <- SchedulerPreviousBinding,
         TraceBindingsField <- SchedulerRootBindingsField,
         TraceAssignmentRhsCertificate <- AssignmentRhsCertificate,
         TraceSubstitution <- StateExprReplaceProjection,
         TraceNameWrite <- PutRootName

SchedulerActualBlockReturns(entry, trace) == TraceConstruction!FiniteScheduleReturns(entry, trace)
SchedulerReturnedRowsPreserveOccurrences(entry, rows) == TraceConstruction!TracePreservesOccurrences(entry, rows)
SchedulerReturnedEntriesAreReady(trace, shapes) == TraceConstruction!TraceStatesAreReady(trace, shapes)

THEOREM ActualSchedulerBlockReturnExposesBodiesAndSteps ==
    ASSUME NEW entry, NEW trace, SchedulerActualBlockReturns(entry, trace)
    PROVE /\ DOMAIN trace.entries = 1..(Len(entry.values) + 1)
          /\ DOMAIN trace.bodies = 1..(Len(entry.values) + 1)
          /\ DOMAIN trace.rows = 1..Len(entry.values)
          /\ trace.entries[1] = entry
          /\ \A i \in 1..Len(entry.values) :
                 SchedulerActualSetTrace(trace.entries[i], trace.entries[i+1],
                                         trace.bodies[i], trace.bodies[i+1], trace.rows[i])
PROOF
<1>domains. /\ DOMAIN trace.entries = 1..(Len(entry.values) + 1)
             /\ DOMAIN trace.bodies = 1..(Len(entry.values) + 1)
             /\ DOMAIN trace.rows = 1..Len(entry.values)
             /\ trace.entries[1] = entry
    BY ONLY SchedulerActualBlockReturns(entry, trace), PTL
        DEF SchedulerActualBlockReturns, TraceConstruction!FiniteScheduleReturns
<1>edges. \A i \in 1..Len(entry.values) :
              SchedulerActualSetTrace(trace.entries[i], trace.entries[i+1],
                                      trace.bodies[i], trace.bodies[i+1], trace.rows[i])
    <2>. TAKE i \in 1..Len(entry.values)
    <2>step. TraceConstruction!TraceStepWithReadWriteMaps(trace.entries[i], trace.entries[i+1],
                                  trace.bodies[i], trace.bodies[i+1], trace.rows[i])
        BY ONLY (i \in 1..Len(entry.values)), SchedulerActualBlockReturns(entry, trace), SMT
            DEF SchedulerActualBlockReturns, TraceConstruction!FiniteScheduleReturns
    <2>. QED BY ONLY <2>step, PTL DEF TraceConstruction!TraceStepWithReadWriteMaps
<1>. QED BY ONLY <1>domains, <1>edges, PTL

THEOREM ActualSchedulerBlockTerminalPublishesTheActualPending ==
    ASSUME NEW entry, NEW trace,
           SchedulerActualBlockReturns(entry, trace)
    PROVE LET last == Len(entry.values) + 1
              pending == trace.entries[last].assignments
          IN trace.bodies[last] =
                IF pending = <<>> THEN <<>>
                ELSE <<[kind |-> "parallel", assignments |-> pending]>>
PROOF
<1>. DEFINE last == Len(entry.values) + 1
            child == trace.entries[last]
<1>empty. /\ child.values = <<>> /\ trace.bodies[last] = SchedulerActualEmptyValue(child)
    BY ONLY SchedulerActualBlockReturns(entry, trace) DEF SchedulerActualBlockReturns, TraceConstruction!FiniteScheduleReturns, child, last
<1>keys. SchedulerNameValues # SchedulerNameAssignments
    BY ONLY SMT DEF SchedulerNameValues, SchedulerNameAssignments
<1>. DEFINE input == SchedulerEmptyEntry(child)
<1>operands. /\ input[SchedulerNameValues] = <<>>
              /\ input[SchedulerNameAssignments] = child.assignments
    BY ONLY <1>empty, <1>keys, SMT DEF input, SchedulerEmptyEntry
<1>return. SchedulerEmptyReturn(input) =
              IF child.assignments = <<>> THEN <<>>
              ELSE <<[kind |-> "parallel", assignments |-> child.assignments]>>
    BY ONLY <1>operands, ActualEmptySchedulerPublishesPendingWrites, SMT
<1>. QED BY ONLY <1>empty, <1>return DEF input, SchedulerActualEmptyValue, child, last

THEOREM RecordingProjectsToOneNameUpdate ==
    ASSUME NEW incoming, NEW target, NEW name
    PROVE StateExprIncomingVariableNames(SchedulerWriteLocal(incoming,target,[variable |-> name])) =
                      PutRootName(StateExprIncomingVariableNames(incoming),target,name)
PROOF
<1>. DEFINE written == SchedulerWriteLocal(incoming,target,[variable |-> name])
            actual == StateExprIncomingVariableNames(written)
            before == StateExprIncomingVariableNames(incoming)
            expected == PutRootName(before,target,name)
<1>domains. /\ DOMAIN written = DOMAIN incoming \cup {target}
             /\ DOMAIN actual = DOMAIN written
             /\ DOMAIN before = DOMAIN incoming
             /\ DOMAIN expected = DOMAIN before \cup {target}
    BY ONLY SMT DEF written, actual, expected, before, StateExprIncomingVariableNames, PutRootName, SchedulerWriteLocal
<1>pointwise. \A key \in DOMAIN actual : actual[key] = expected[key]
    <2>. TAKE key \in DOMAIN actual
    <2>target. CASE key = target
        BY ONLY <2>target, <1>domains, SMT
            DEF actual, expected, before, written, StateExprIncomingVariableNames, PutRootName, SchedulerWriteLocal
    <2>other. CASE key # target
        BY ONLY <2>other, (key \in DOMAIN actual), <1>domains, SMT
            DEF actual, expected, before, written, StateExprIncomingVariableNames, PutRootName, SchedulerWriteLocal
    <2>. QED BY ONLY <2>target, <2>other, SMT
<1>equal. actual = expected
    BY ONLY <1>domains, <1>pointwise, SMT DEF actual, expected, StateExprIncomingVariableNames, PutRootName
<1>. QED BY ONLY <1>equal DEF actual, expected, written, before

\* The proof rule's head postcondition is discharged using the actual
\* allocator, source RHS certificate, recording, substitution, and return.
THEOREM ActualSupportedHeadSuppliesTheTraceInduction ==
    ASSUME NEW shapes
    PROVE \A entry : SchedulerBlockEntryReady(entry, shapes) /\ entry.values # <<>> =>
                         \E compiled : TraceConstruction!HeadTracePostcondition(entry, shapes, compiled)
PROOF
<1>. TAKE entry
<1>. SUFFICES ASSUME SchedulerBlockEntryReady(entry, shapes), entry.values # <<>>
              PROVE \E compiled : TraceConstruction!HeadTracePostcondition(entry, shapes, compiled)
    OBVIOUS
<1>. DEFINE statement == Head(entry.values)
<1>source. /\ SchedulerSupportedAssignmentStatement(statement) /\ statement = entry.values[1]
    BY ONLY SchedulerBlockEntryReady(entry, shapes), (entry.values # <<>>),
        LenProperties, EmptySeq, HeadTailProperties, SMT DEF SchedulerBlockEntryReady, statement
<1>compiler. PICK compiled : SchedulerAssignmentRhsInvocation(statement, compiled)
    BY ONLY <1>source, ActualAssignmentRhsCompilerReturnsASupportedRow, SMT
<1>. DEFINE step == SchedulerActualSetStep(entry, compiled)
            descriptor == step.descriptor
            name == descriptor[SchedulerNameBinding]
            child == step.next
<1>. DEFINE allocated == AtomicBindingAllocation(entry.allocator).name
            actualDescriptor == SchedulerSetDescriptorForBinding(entry.values, entry.old, allocated)
<1>descriptorDefinition. descriptor = actualDescriptor
    BY ONLY SMT DEF descriptor, step, SchedulerActualSetStep, actualDescriptor, allocated, SchedulerSetDescriptorForBinding
<1>sourceBinding. SchedulerNameBinding \in DOMAIN actualDescriptor
    BY ONLY ActualRootAssignmentDescriptorHasItsBinding, SMT DEF actualDescriptor, allocated
<1>allocatedDescriptor. SchedulerNameBinding \in DOMAIN descriptor
    BY ONLY <1>descriptorDefinition, <1>sourceBinding, SMT
<1>nonemptyDescriptor. descriptor # <<>>
    BY ONLY <1>allocatedDescriptor, SeqDef, SMT
<1>next. /\ SchedulerBlockEntryReady(child, shapes) /\ child.values = Tail(entry.values)
         /\ step.locals[SchedulerNameUpdate] = descriptor
         /\ descriptor.predecessor = SchedulerPreviousBinding(entry.old)
         /\ SchedulerPreviousBinding(child.old) = name
         /\ child.old[SchedulerRootBindingsField] =
                SchedulerWriteLocal(entry.old[SchedulerRootBindingsField], statement.target, [variable |-> name])
         /\ step.locals[SchedulerNameUpdated] =
                StateExprReplaceProjection(SwiftSourceArrayAsView(compiled.source), SchedulerOldNames(entry))
         /\ name \notin entry.allocator.used /\ child.allocator.used = entry.allocator.used \cup {name}
    BY ONLY <1>compiler, SchedulerBlockEntryReady(entry, shapes), (entry.values # <<>>),
        <1>nonemptyDescriptor, ActualSchedulerSetStepUsesTheActualHeadAndTransfersEntry, SMT DEF step, child, descriptor, name,
            statement, SchedulerPreviousBinding, SchedulerOldNames
<1>localDescriptor. step.locals[SchedulerNameUpdate] = descriptor
    BY ONLY <1>next, PTL
<1>oldRhs. step.locals[SchedulerNameUpdated] =
    StateExprReplaceProjection(SwiftSourceArrayAsView(compiled.source), SchedulerOldNames(entry))
    BY ONLY <1>next, PTL
<1>nameMap. SchedulerOldNames(child) = PutRootName(SchedulerOldNames(entry),statement.target,name)
    BY ONLY <1>next, RecordingProjectsToOneNameUpdate, SMT DEF SchedulerOldNames
<1>rowCarrier. /\ statement.target \in Keys
              /\ AssignmentRhsCertificate(SchedulerAssignmentRhsRow(statement.target, compiled))
    BY ONLY <1>source, <1>compiler, ActualAssignmentRhsCompilerReturnsASupportedRow, SMT
        DEF SchedulerSupportedAssignmentStatement
<1>body. \A suffix :
    LET returned == SchedulerHeadLet(entry, compiled, suffix)
        row == SchedulerHeadRow(entry, compiled, suffix)
    IN /\ TraceConstruction!TraceStepWithReadWriteMaps(entry, child, returned, suffix, row)
       /\ row.target \in Keys /\ AssignmentRhsCertificate(row)
       /\ row.target = statement.target /\ row.sourceRhs = statement.rhs
       /\ row.binding \notin entry.allocator.used
       /\ row.predecessor = SchedulerPreviousBinding(entry.old)
       /\ SchedulerPreviousBinding(child.old) = row.binding
       /\ child.allocator.used = entry.allocator.used \cup {row.binding}
    <2>. TAKE suffix
    <2>. DEFINE returned == SchedulerHeadLet(entry, compiled, suffix)
                row == SchedulerHeadRow(entry, compiled, suffix)
                sourceRow == SchedulerAssignmentRhsRow(statement.target, compiled)
    <2>wrapped. returned =
        <<[kind |-> "letBinding",
           variable |-> step.locals[SchedulerNameUpdate][SchedulerNameBinding],
           value |-> step.locals[SchedulerNameUpdated], body |-> suffix]>>
        BY ONLY ActualSchedulerSetReturnWrapsTheExactRecursiveValue, SMT
            DEF returned, SchedulerHeadLet, step
    <2>indexed. /\ returned[1].variable = step.locals[SchedulerNameUpdate][SchedulerNameBinding]
                /\ returned[1].value = step.locals[SchedulerNameUpdated]
        BY ONLY <2>wrapped, SMT
    <2>binding. returned[1].variable = name
        BY ONLY <1>localDescriptor, <2>indexed, SMT DEF name
    <2>edge. SchedulerActualSetTrace(entry, child, returned, suffix, row)
        <3>. SUFFICES
            \E actual :
                /\ SchedulerAssignmentRhsInvocation(statement, actual)
                /\ LET head == SchedulerActualSetStep(entry, actual)
                   IN /\ child = head.next /\ returned = SchedulerActualSetValue(head, suffix)
                      /\ row = SchedulerBlockRow(statement, head, actual, returned)
            BY (entry.values # <<>>) DEF SchedulerActualSetTrace, statement
        <3>. WITNESS compiled
        <3>. QED BY ONLY <1>compiler DEF step, child, returned, row, SchedulerHeadLet, SchedulerHeadRow, statement
    <2>actualRow. /\ row.target = sourceRow.target /\ row.view = sourceRow.view
                   /\ row.emitted = sourceRow.emitted /\ row.inverse = sourceRow.inverse
                   /\ row.fallback = sourceRow.fallback
                   /\ row.binding = returned[1].variable
                   /\ row.predecessor = descriptor.predecessor
                   /\ row.substitutedRhs = returned[1].value
                   /\ row.sourceRhs = statement.rhs
        BY ONLY SMT DEF row, sourceRow, SchedulerHeadRow, SchedulerBlockRow,
            statement, step, descriptor, returned, SchedulerHeadLet
    <2>source. /\ sourceRow.target = statement.target
                /\ sourceRow.view = SwiftSourceArrayAsView(compiled.source)
        BY ONLY SMT DEF sourceRow, SchedulerAssignmentRhsRow
    <2>identity. /\ row.target = statement.target /\ row.sourceRhs = statement.rhs
                  /\ row.binding = name /\ row.predecessor = descriptor.predecessor
        BY ONLY <2>binding, <2>actualRow, <2>source, SMT
    <2>readValue. row.substitutedRhs = StateExprReplaceProjection(row.view, SchedulerOldNames(entry))
        BY ONLY <2>indexed, <2>actualRow, <2>source, <1>oldRhs, SMT
    <2>certificate. AssignmentRhsCertificate(row)
        BY ONLY <1>rowCarrier, <2>actualRow, SMT DEF sourceRow, AssignmentRhsCertificate
    <2>. QED BY ONLY <2>edge, <2>identity, <2>readValue, <2>certificate, <1>nameMap, <1>rowCarrier, <1>next, SMT
        DEF TraceConstruction!TraceStepWithReadWriteMaps, TraceConstruction!TraceOldNames, SchedulerOldNames, StateExprIncomingVariableNames, returned, row
<1>. WITNESS compiled
<1>child. child = SchedulerHeadNext(entry,compiled)
    BY ONLY DEF child, step, SchedulerHeadNext
<1>slot. /\ statement.target = entry.values[1].target
          /\ statement.rhs = entry.values[1].rhs
    BY ONLY <1>source, SMT
<1>ready. /\ SchedulerBlockEntryReady(SchedulerHeadNext(entry,compiled), shapes)
           /\ SchedulerHeadNext(entry,compiled).values = Tail(entry.values)
    BY ONLY <1>child, <1>next, SMT
<1>bodyExact. \A suffix :
    LET returned == SchedulerHeadLet(entry,compiled,suffix)
        row == SchedulerHeadRow(entry,compiled,suffix)
        after == SchedulerHeadNext(entry,compiled)
    IN /\ TraceConstruction!TraceStepWithReadWriteMaps(entry,after,returned,suffix,row)
       /\ row.target \in Keys /\ AssignmentRhsCertificate(row)
       /\ row.target = entry.values[1].target /\ row.sourceRhs = entry.values[1].rhs
       /\ row.binding \notin entry.allocator.used
       /\ row.predecessor = SchedulerPreviousBinding(entry.old)
       /\ SchedulerPreviousBinding(after.old) = row.binding
       /\ after.allocator.used = entry.allocator.used \cup {row.binding}
    <2>. TAKE suffix
    <2>. QED BY ONLY <1>child, <1>slot, <1>body, SMT
<1>. QED BY ONLY <1>ready, <1>bodyExact, PTL DEF TraceConstruction!HeadTracePostcondition

THEOREM ActualSchedulerReturnsEverySupportedStatementOnce ==
    ASSUME NEW shapes
    PROVE \A entry :
        SchedulerBlockEntryReady(entry, shapes) =>
            \E trace : SchedulerActualBlockReturns(entry, trace)
                       /\ SupportedAssignmentList(trace.rows)
                       /\ SchedulerReturnedRowsPreserveOccurrences(entry, trace.rows)
                       /\ SchedulerReturnedEntriesAreReady(trace, shapes)
                       /\ Len(trace.rows) = Len(entry.values)
PROOF
<1>sequenceInput. TraceConstruction!TraceInputSequences(shapes)
    BY ONLY SMT DEF TraceConstruction!TraceInputSequences, SchedulerBlockEntryReady
<1>head. TraceConstruction!TraceInputHeads(shapes)
    BY ONLY ActualSupportedHeadSuppliesTheTraceInduction, SMT DEF TraceConstruction!TraceInputHeads
<1>rule. \A statementShapes :
    TraceConstruction!TraceInputSequences(statementShapes)
    /\ TraceConstruction!TraceInputHeads(statementShapes)
    => TraceConstruction!TraceOutputFor(statementShapes)
    BY ONLY IntegerDomain, TraceConstruction!TheFiniteReturnFollowsFromTheHeadAndSequenceInputs, SMT
        DEF IntegerDomain
<1>instance. TraceConstruction!TraceOutputFor(shapes)
    BY ONLY <1>sequenceInput, <1>head, <1>rule, SMT
<1>. QED BY ONLY <1>instance, SMT
    DEF TraceConstruction!TraceOutputFor, SchedulerActualBlockReturns,
        SchedulerReturnedRowsPreserveOccurrences, SchedulerReturnedEntriesAreReady,
        TraceConstruction!TraceSupportedAssignmentList, SupportedAssignmentList

SchedulerTraceIncomingNames(trace) ==
    [i \in 1..(Len(trace.rows)+1) |-> SchedulerOldNames(trace.entries[i])]

THEOREM TheReturnedBlockReadsItsOwnStrictlyPriorRows ==
    ASSUME NEW entry, NEW trace, SchedulerActualBlockReturns(entry,trace),
           SupportedAssignmentList(trace.rows), Len(trace.rows)=Len(entry.values),
           DOMAIN SchedulerOldNames(entry) = {}
    PROVE /\ RowsReadExactlyTheirStrictlyPriorWriters(trace.rows,SchedulerTraceIncomingNames(trace))
          /\ \A i \in 1..Len(trace.rows) : trace.rows[i].substitutedRhs =
                  StateExprReplaceProjection(trace.rows[i].view,SchedulerTraceIncomingNames(trace)[i])
PROOF
<1>. DEFINE rows == trace.rows
            count == Len(rows)
            maps == SchedulerTraceIncomingNames(trace)
<1>shape. count \in Nat /\ trace.entries[1] = entry
    BY ONLY SupportedAssignmentList(trace.rows), SchedulerActualBlockReturns(entry,trace), SMT
        DEF SupportedAssignmentList, SchedulerActualBlockReturns, TraceConstruction!FiniteScheduleReturns, rows, count
<1>empty. SchedulerOldNames(entry) = [key \in {} |-> key]
    BY ONLY (DOMAIN SchedulerOldNames(entry) = {}), SMT DEF SchedulerOldNames, StateExprIncomingVariableNames
<1>seed. maps[1] = [key \in {} |-> key]
    BY ONLY <1>shape, <1>empty, SMT DEF maps, SchedulerTraceIncomingNames, count, rows
<1>advance. \A i \in 1..count :
    /\ maps[i+1] = PutRootName(maps[i],rows[i].target,rows[i].binding)
    /\ rows[i].substitutedRhs = StateExprReplaceProjection(rows[i].view,maps[i])
    <2>. TAKE i \in 1..count
    <2>edge. TraceConstruction!TraceStepWithReadWriteMaps(trace.entries[i],trace.entries[i+1],
                    trace.bodies[i],trace.bodies[i+1],rows[i])
        BY ONLY (i \in 1..count), (Len(trace.rows)=Len(entry.values)), SchedulerActualBlockReturns(entry,trace), SMT
            DEF SchedulerActualBlockReturns, TraceConstruction!FiniteScheduleReturns, rows, count
    <2>. QED BY ONLY <1>shape, (i \in 1..count), <2>edge, SMT
        DEF TraceConstruction!TraceStepWithReadWriteMaps, TraceConstruction!TraceOldNames,
            maps, SchedulerTraceIncomingNames, SchedulerOldNames, StateExprIncomingVariableNames, rows, count
<1>maps. /\ RecordedNameMapsFollowRows(trace.rows,SchedulerTraceIncomingNames(trace))
         /\ \A i \in 1..Len(trace.rows) :
                trace.rows[i].substitutedRhs =
                      StateExprReplaceProjection(trace.rows[i].view,SchedulerTraceIncomingNames(trace)[i])
    BY ONLY <1>seed, <1>advance, SMT DEF RecordedNameMapsFollowRows, rows, count, maps
<1>. QED BY ONLY <1>maps, SupportedAssignmentList(trace.rows), SourceBoundSubstitutionReadsOnlyTheLatestStrictlyPriorWrite, SMT

\* The two histories are the checked source and certificate-plan meanings.
\* A match to actual emitted instructions still needs the physical operand and
\* read route checks, including the binding-ID-to-slot correspondence.
THEOREM ReturnedLetOwnsTheRowBinderAndRhs ==
    ASSUME NEW statement, NEW step, NEW result, NEW returned
    PROVE LET row == SchedulerBlockRow(statement, step, result, returned)
          IN /\ row.binding = returned[1].variable /\ row.substitutedRhs = returned[1].value
    BY ONLY IsaM("simp") DEF SchedulerBlockRow

ReturnedLetBelongsToAuthoredWrite(entry, trace, i) ==
    LET authored == entry.values[i]
        row == trace.rows[i]
        scheduled == trace.bodies[i][1]
    IN /\ row.sourceRhs = authored.rhs /\ row.target = authored.target
       /\ row.binding = scheduled.variable /\ row.substitutedRhs = scheduled.value

THEOREM ActualSchedulerReturnPairsTheAuthoredAndScheduledRhs ==
    ASSUME NEW entry, NEW trace, SchedulerActualBlockReturns(entry, trace),
           SchedulerReturnedRowsPreserveOccurrences(entry, trace.rows), Len(trace.rows) = Len(entry.values)
    PROVE \A i \in 1..Len(entry.values) : ReturnedLetBelongsToAuthoredWrite(entry, trace, i)
PROOF
<1>. TAKE i \in 1..Len(entry.values)
<1>edge. SchedulerActualSetTrace(trace.entries[i], trace.entries[i+1], trace.bodies[i],
                                  trace.bodies[i+1], trace.rows[i])
    BY ONLY SchedulerActualBlockReturns(entry, trace), ActualSchedulerBlockReturnExposesBodiesAndSteps,
            (i \in 1..Len(entry.values)), SMT
<1>row. PICK compiled :
    trace.rows[i] = SchedulerBlockRow(Head(trace.entries[i].values),
        SchedulerActualSetStep(trace.entries[i], compiled), compiled, trace.bodies[i])
    BY ONLY <1>edge, SMT DEF SchedulerActualSetTrace
<1>returned. /\ trace.rows[i].binding = trace.bodies[i][1].variable
             /\ trace.rows[i].substitutedRhs = trace.bodies[i][1].value
    BY ONLY <1>row, ReturnedLetOwnsTheRowBinderAndRhs, SMT
<1>authored. /\ trace.rows[i].sourceRhs = entry.values[i].rhs
             /\ trace.rows[i].target = entry.values[i].target
    BY ONLY SchedulerReturnedRowsPreserveOccurrences(entry, trace.rows), (Len(trace.rows) = Len(entry.values)),
            (i \in 1..Len(entry.values)), SMT
        DEF SchedulerReturnedRowsPreserveOccurrences, TraceConstruction!TracePreservesOccurrences
<1>. QED BY ONLY <1>authored, <1>returned DEF ReturnedLetBelongsToAuthoredWrite

THEOREM TheActualReturnedLetHasItsChildAndRowFields ==
    ASSUME NEW entry, NEW successor, NEW returned, NEW child, NEW row,
           SchedulerActualSetTrace(entry, successor, returned, child, row)
    PROVE /\ returned = <<returned[1]>>
          /\ returned[1].kind = "letBinding" /\ returned[1].body = child
          /\ returned[1].variable = row.binding /\ returned[1].value = row.substitutedRhs
PROOF
<1>. DEFINE statement == Head(entry.values)
<1>compiled. PICK compiled :
    /\ returned = SchedulerActualSetValue(SchedulerActualSetStep(entry, compiled), child)
    /\ row = SchedulerBlockRow(statement, SchedulerActualSetStep(entry, compiled), compiled, returned)
    BY ONLY SchedulerActualSetTrace(entry, successor, returned, child, row), SMT
        DEF SchedulerActualSetTrace, statement
<1>. DEFINE step == SchedulerActualSetStep(entry, compiled)
<1>shape. returned =
    <<[kind |-> "letBinding", variable |-> step.locals[SchedulerNameUpdate][SchedulerNameBinding],
       value |-> step.locals[SchedulerNameUpdated], body |-> child]>>
    BY ONLY <1>compiled, ActualSchedulerSetReturnWrapsTheExactRecursiveValue, SMT DEF step
<1>nested. /\ returned = <<returned[1]>>
           /\ returned[1].kind = "letBinding" /\ returned[1].body = child
    BY ONLY <1>shape, IsaM("simp"), SMT
<1>fields. /\ returned[1].variable = row.binding /\ returned[1].value = row.substitutedRhs
    BY ONLY <1>compiled, ReturnedLetOwnsTheRowBinderAndRhs, SMT DEF step
<1>. QED BY ONLY <1>nested, <1>fields

THEOREM ReturnedSchedulerBodiesSupplyTheActualDefineColumn ==
    ASSUME NEW entry, NEW trace, SchedulerActualBlockReturns(entry, trace),
           Len(entry.values) \in Nat, Len(trace.rows) = Len(entry.values),
           NEW pending, NEW terminalAction
    PROVE LET actions == CompiledLetSuffixes(trace,pending,terminalAction)
          IN /\ actions[Len(trace.rows)+1] = terminalAction
             /\ \E items : \A i \in 1..Len(trace.rows) :
                    /\ trace.bodies[i] = <<trace.bodies[i][1]>> /\ trace.bodies[i][1].kind = "letBinding"
                    /\ trace.bodies[i][1].body = trace.bodies[i+1] /\ trace.bodies[i+1] \in Seq(items)
             /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
             /\ \A i \in DOMAIN trace.rows :
                    /\ actions[i].name = trace.rows[i].binding
                    /\ actions[i].value = trace.rows[i].substitutedRhs
PROOF
<1>. DEFINE count == Len(trace.rows)
            bodies == trace.bodies
            last == count + 1
            actions == CompiledLetSuffixes(trace,pending,terminalAction)
            occupied == {j \in DOMAIN bodies : bodies[j] # <<>>}
            statementSet == {bodies[j][1] : j \in occupied}
<1>edges. /\ DOMAIN bodies = 1..last /\ DOMAIN trace.rows = 1..count /\ count \in Nat
          /\ \A i \in DOMAIN trace.rows :
                SchedulerActualSetTrace(trace.entries[i],trace.entries[i+1],bodies[i],bodies[i+1],trace.rows[i])
    BY ONLY SchedulerActualBlockReturns(entry, trace), ActualSchedulerBlockReturnExposesBodiesAndSteps,
        (Len(entry.values) \in Nat), (Len(trace.rows) = Len(entry.values)), SMT DEF count, last, bodies
<1>lets. \A i \in DOMAIN trace.rows :
    LET returned == bodies[i]
        row == trace.rows[i]
    IN /\ returned = <<returned[1]>>
       /\ returned[1].kind = "letBinding" /\ returned[1].body = bodies[i+1]
       /\ returned[1].variable = row.binding /\ returned[1].value = row.substitutedRhs
    <2>. TAKE i \in DOMAIN trace.rows
    <2>edge. SchedulerActualSetTrace(trace.entries[i],trace.entries[i+1],bodies[i],bodies[i+1],trace.rows[i])
        BY ONLY <1>edges, (i \in DOMAIN trace.rows), SMT
    <2>. QED BY ONLY <2>edge, TheActualReturnedLetHasItsChildAndRowFields, IsaM("blast")
<1>terminal. bodies[last] = <<>> \/ bodies[last] = <<bodies[last][1]>>
    <2>. DEFINE endIndex == Len(entry.values)+1
                writes == trace.entries[endIndex].assignments
                parallel == [kind |-> "parallel", assignments |-> writes]
    <2>end. trace.bodies[endIndex] = IF writes = <<>> THEN <<>> ELSE <<parallel>>
        BY ONLY SchedulerActualBlockReturns(entry,trace), ActualSchedulerBlockTerminalPublishesTheActualPending
            DEF endIndex, writes, parallel
    <2>atLast. bodies[last] = trace.bodies[endIndex]
        BY ONLY (Len(trace.rows) = Len(entry.values)), SMT DEF bodies, last, count, endIndex
    <2>field. <<parallel>>[1] = parallel BY ONLY IsaM("simp")
    <2>. QED BY ONLY <2>end, <2>atLast, <2>field, SMT
<1>arrays. \A j \in DOMAIN bodies : bodies[j] \in Seq(statementSet)
    <2>. TAKE j \in DOMAIN bodies
    <2>shape. bodies[j] = <<>> \/ bodies[j] = <<bodies[j][1]>>
        BY ONLY <1>edges, <1>lets, <1>terminal, (j \in DOMAIN bodies), SMT DEF last
    <2>member. bodies[j] # <<>> => bodies[j][1] \in statementSet
        BY ONLY (j \in DOMAIN bodies), SMT DEF statementSet, occupied
    <2>empty. CASE bodies[j] = <<>>
        BY ONLY <2>empty, EmptySeq, SMT
    <2>one. CASE bodies[j] # <<>>
        <3>member. bodies[j][1] \in statementSet BY ONLY <2>member, <2>one, PTL
        <3>function. <<bodies[j][1]>> \in [1..1 -> statementSet]
            BY ONLY <3>member, SMT
        <3>typed. <<bodies[j][1]>> \in Seq(statementSet)
            BY ONLY <3>function, SeqDef, SMT
        <3>. QED BY ONLY <2>one, <2>shape, <3>typed, SMT
    <2>. QED BY ONLY <2>empty, <2>one, SMT
<1>children. \A i \in DOMAIN trace.rows :
    /\ trace.bodies[i] = <<trace.bodies[i][1]>>
    /\ trace.bodies[i][1].kind = "letBinding"
    /\ trace.bodies[i][1].body = trace.bodies[i+1]
    /\ trace.bodies[i+1] \in Seq(statementSet)
    <2>. TAKE i \in DOMAIN trace.rows
    <2>child. i+1 \in DOMAIN bodies
        BY ONLY <1>edges, (i \in DOMAIN trace.rows), SMT DEF last
    <2>. QED BY ONLY <1>arrays, <1>lets, <2>child, (i \in DOMAIN trace.rows), SMT DEF bodies
<1>actions. /\ actions[Len(trace.rows)+1] = terminalAction
            /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
    BY ONLY <1>edges, <1>children, ScheduledLetLoweringProducesTheActionColumn, SMT DEF actions, count
<1>sameRows. \A i \in DOMAIN trace.rows :
    /\ actions[i].name = trace.rows[i].binding
    /\ actions[i].value = trace.rows[i].substitutedRhs
    <2>. TAKE i \in DOMAIN trace.rows
    <2>define. actions[i] = [kind |-> "define", name |-> trace.bodies[i][1].variable,
                            value |-> trace.bodies[i][1].value, body |-> actions[i+1]]
        BY ONLY <1>actions, (i \in DOMAIN trace.rows), SMT DEF ActualActionDefinesMatchTheScheduledLets
    <2>. QED BY ONLY <1>lets, <2>define, (i \in DOMAIN trace.rows), SMT DEF bodies
<1>shape. \E items : \A i \in 1..count :
                /\ bodies[i] = <<bodies[i][1]>> /\ bodies[i][1].kind = "letBinding"
                /\ bodies[i][1].body = bodies[i+1] /\ bodies[i+1] \in Seq(items)
    <2>. WITNESS statementSet
    <2>. QED BY ONLY <1>edges,<1>children,SMT
<1>. QED BY ONLY <1>actions, <1>sameRows, <1>shape, PTL DEF actions, bodies, count

THEOREM TheSchedulerSuppliesItsCertifiedRows ==
    ASSUME NEW entry, NEW shapes, SchedulerBlockEntryReady(entry, shapes),
           DOMAIN SchedulerOldNames(entry) = {},
           NEW before \in AssignmentBindings
    PROVE \E trace, history :
        /\ SchedulerActualBlockReturns(entry, trace)
        /\ SupportedAssignmentList(trace.rows)
        /\ SchedulerReturnedRowsPreserveOccurrences(entry, trace.rows)
        /\ SchedulerReturnedEntriesAreReady(trace, shapes)
        /\ Len(trace.rows) = Len(entry.values)
        /\ \A i \in 1..Len(entry.values) : ReturnedLetBelongsToAuthoredWrite(entry, trace, i)
        /\ \A i \in 1..Len(entry.values) :
              trace.bodies[i][1].value = StateExprReplaceProjection(trace.rows[i].view,SchedulerTraceIncomingNames(trace)[i])
        /\ RowsReadExactlyTheirStrictlyPriorWriters(trace.rows,SchedulerTraceIncomingNames(trace))
        /\ \A pending,terminalAction :
              LET actions == CompiledLetSuffixes(trace,pending,terminalAction)
              IN /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
                 /\ \A i \in DOMAIN trace.rows :
                       /\ actions[i].name = trace.rows[i].binding
                       /\ actions[i].value = trace.rows[i].substitutedRhs
        /\ \A authoredNames \in SUBSET entry.allocator.used :
               \A i \in 1..Len(trace.rows) : trace.rows[i].binding \notin authoredNames
        /\ LET last == Len(entry.values) + 1
               pending == trace.entries[last].assignments
           IN trace.bodies[last] =
                    IF pending = <<>> THEN <<>>
                    ELSE <<[kind |-> "parallel", assignments |-> pending]>>
        /\ AssignmentListHistory(FALSE, before, trace.rows, history)
        /\ AssignmentListHistory(TRUE, before, trace.rows, history)
        /\ \A index \in 0..Len(trace.rows) : AssignmentPrefixMeaning(before, trace.rows, history, index)
PROOF
<1>schedule. PICK trace : SchedulerActualBlockReturns(entry, trace)
                          /\ SupportedAssignmentList(trace.rows)
                          /\ SchedulerReturnedRowsPreserveOccurrences(entry, trace.rows)
                           /\ SchedulerReturnedEntriesAreReady(trace, shapes)
                          /\ Len(trace.rows) = Len(entry.values)
    BY ONLY SchedulerBlockEntryReady(entry, shapes), ActualSchedulerReturnsEverySupportedStatementOnce, SMT
<1>paired. \A i \in 1..Len(entry.values) : ReturnedLetBelongsToAuthoredWrite(entry, trace, i)
    BY ONLY <1>schedule, ActualSchedulerReturnPairsTheAuthoredAndScheduledRhs, SMT
<1>pending. LET last == Len(entry.values) + 1
                 pending == trace.entries[last].assignments
             IN trace.bodies[last] =
                    IF pending = <<>> THEN <<>>
                    ELSE <<[kind |-> "parallel", assignments |-> pending]>>
    BY ONLY <1>schedule, ActualSchedulerBlockTerminalPublishesTheActualPending, SMT
<1>reads. RowsReadExactlyTheirStrictlyPriorWriters(trace.rows,SchedulerTraceIncomingNames(trace))
    BY ONLY <1>schedule, (DOMAIN SchedulerOldNames(entry) = {}), TheReturnedBlockReadsItsOwnStrictlyPriorRows, SMT
<1>source. \A i \in 1..Len(trace.rows) : trace.rows[i].substitutedRhs =
                  StateExprReplaceProjection(trace.rows[i].view,SchedulerTraceIncomingNames(trace)[i])
    BY ONLY <1>schedule, (DOMAIN SchedulerOldNames(entry) = {}), TheReturnedBlockReadsItsOwnStrictlyPriorRows, SMT
<1>operand. \A i \in 1..Len(entry.values) :
              trace.bodies[i][1].value = StateExprReplaceProjection(trace.rows[i].view,SchedulerTraceIncomingNames(trace)[i])
    BY ONLY <1>paired, <1>schedule, <1>source, SMT DEF ReturnedLetBelongsToAuthoredWrite
<1>defines. \A pending,terminalAction :
                LET actions == CompiledLetSuffixes(trace,pending,terminalAction)
                IN /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
                   /\ \A i \in DOMAIN trace.rows :
                         /\ actions[i].name = trace.rows[i].binding
                         /\ actions[i].value = trace.rows[i].substitutedRhs
    <2>. TAKE pending, terminalAction
    <2>count. Len(entry.values) \in Nat
        BY ONLY SchedulerBlockEntryReady(entry,shapes), LenProperties, SeqDef, SMT DEF SchedulerBlockEntryReady
    <2>all. LET actions == CompiledLetSuffixes(trace,pending,terminalAction)
            IN /\ actions[Len(trace.rows)+1] = terminalAction
               /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
               /\ \A i \in DOMAIN trace.rows :
                     /\ actions[i].name = trace.rows[i].binding
                     /\ actions[i].value = trace.rows[i].substitutedRhs
        BY ONLY <1>schedule, <2>count, ReturnedSchedulerBodiesSupplyTheActualDefineColumn, SMT
    <2>. QED BY ONLY <2>all
<1>fresh. \A authoredNames \in SUBSET entry.allocator.used :
                 \A i \in 1..Len(trace.rows) : trace.rows[i].binding \notin authoredNames
    BY ONLY <1>schedule, SMT
        DEF SchedulerReturnedRowsPreserveOccurrences, TraceConstruction!TracePreservesOccurrences
<1>run. PICK history :
        /\ AssignmentListHistory(FALSE, before, trace.rows, history)
        /\ AssignmentListHistory(TRUE, before, trace.rows, history)
        /\ \A index \in 0..Len(trace.rows) : AssignmentPrefixMeaning(before, trace.rows, history, index)
    BY ONLY <1>schedule, (before \in AssignmentBindings), CertifiedOrderedAssignmentListConstructsCompleteActionOutcome, SMT
<1>. WITNESS trace, history
<1>. QED BY ONLY <1>defines, <1>operand, <1>paired, <1>schedule, <1>pending, <1>reads, <1>fresh, <1>run

ScheduledRowsHaveCompleteOutcome(entry, shapes, before, trace, history) ==
        /\ SchedulerActualBlockReturns(entry, trace)
        /\ SupportedAssignmentList(trace.rows)
        /\ SchedulerReturnedRowsPreserveOccurrences(entry, trace.rows)
        /\ SchedulerReturnedEntriesAreReady(trace, shapes)
        /\ Len(trace.rows) = Len(entry.values)
        /\ \A i \in 1..Len(entry.values) : ReturnedLetBelongsToAuthoredWrite(entry, trace, i)
        /\ \A i \in 1..Len(entry.values) :
              trace.bodies[i][1].value = StateExprReplaceProjection(trace.rows[i].view,SchedulerTraceIncomingNames(trace)[i])
        /\ RowsReadExactlyTheirStrictlyPriorWriters(trace.rows,SchedulerTraceIncomingNames(trace))
        /\ \A pending,terminalAction :
              LET actions == CompiledLetSuffixes(trace,pending,terminalAction)
              IN /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
                 /\ \A i \in DOMAIN trace.rows :
                       /\ actions[i].name = trace.rows[i].binding
                       /\ actions[i].value = trace.rows[i].substitutedRhs
        /\ \A authoredNames \in SUBSET entry.allocator.used :
               \A i \in 1..Len(trace.rows) : trace.rows[i].binding \notin authoredNames
        /\ LET last == Len(entry.values) + 1
               pending == trace.entries[last].assignments
           IN trace.bodies[last] =
                    IF pending = <<>> THEN <<>>
                    ELSE <<[kind |-> "parallel", assignments |-> pending]>>
        /\ AssignmentListHistory(FALSE, before, trace.rows, history)
        /\ AssignmentListHistory(TRUE, before, trace.rows, history)
        /\ \A index \in 0..Len(trace.rows) : AssignmentPrefixMeaning(before, trace.rows, history, index)

CompleteOutcomeForReturnedBody(entry, shapes, before, body) ==
    \E trace, history :
        /\ trace.bodies[1] = body
        /\ ScheduledRowsHaveCompleteOutcome(entry,shapes,before,trace,history)

SchedulerRhsInput(statement) == CHOOSE c : SchedulerAssignmentRhsInvocation(statement,c)

\* Normal-return interpretation for the supported cases. The two folds take
\* the caller's entry only. Their length is determined by the authored list.
SchedulerRootSetFrame(e) == e.values # <<>> /\ Head(e.values).kind = "rootSet"
SchedulerActiveStep(e) == SchedulerActualSetStep(e,SchedulerRhsInput(Head(e.values)))
SchedulerPush(e,index) == IF SchedulerRootSetFrame(e) THEN SchedulerActiveStep(e).next ELSE "outside seed"
SchedulerUnwind(e,child) == IF SchedulerRootSetFrame(e) THEN SchedulerActualSetValue(SchedulerActiveStep(e),child) ELSE "outside seed"
LOCAL PushRule == INSTANCE SchedulerPushRule WITH Advance <- SchedulerPush
SchedulerCalls(entry,n) == PushRule!CallChain(entry,1,n+1,SchedulerPush)
SchedulerResults(calls,n) ==
    LET terminal == SchedulerActualEmptyValue(calls[n+1])
        pop(child,k) == SchedulerUnwind(calls[(n+1)-k],child)
    IN CallChain(terminal,0,n,pop)
SchedulerReturnedValue(entry) ==
    LET n == Len(entry.values)
    IN SchedulerResults(SchedulerCalls(entry,n),n)[n]

THEOREM CertifiedEdgeFollowsTheSourceCallAndReturn ==
    ASSUME NEW e, NEW next, NEW body, NEW child, NEW row, NEW shapes,
           SchedulerBlockEntryReady(e,shapes), SchedulerActualSetTrace(e,next,body,child,row)
    PROVE next = SchedulerPush(e,0) /\ body = SchedulerUnwind(e,child)
PROOF
<1>set. e.values # <<>>
    BY ONLY SchedulerActualSetTrace(e,next,body,child,row) DEF SchedulerActualSetTrace
<1>typed. SchedulerSupportedAssignmentStatement(Head(e.values))
    BY ONLY SchedulerBlockEntryReady(e,shapes),<1>set,HeadTailProperties,LenProperties,EmptySeq, SMT DEF SchedulerBlockEntryReady
<1>frame. SchedulerRootSetFrame(e)
    BY ONLY <1>set,<1>typed DEF SchedulerRootSetFrame,SchedulerSupportedAssignmentStatement
<1>read. PICK c : /\ SchedulerAssignmentRhsInvocation(Head(e.values),c)
                  /\ next=SchedulerActualSetStep(e,c).next
                  /\ body=SchedulerActualSetValue(SchedulerActualSetStep(e,c),child)
    BY ONLY SchedulerActualSetTrace(e,next,body,child,row),SMT DEF SchedulerActualSetTrace
<1>. DEFINE chosen == SchedulerRhsInput(Head(e.values))
<1>exists. \E x : SchedulerAssignmentRhsInvocation(Head(e.values),x)
    <2>. WITNESS c
    <2>. QED BY ONLY <1>read
<1>valid. SchedulerAssignmentRhsInvocation(Head(e.values),chosen)
    BY ONLY <1>exists,<1>read, SMT DEF chosen,SchedulerRhsInput
<1>input. c.source=chosen.source
    BY ONLY <1>valid,<1>read,TheSchedulerRhsHasOnlyOnePhysicalSourceArray
<1>same. SchedulerActualSetStep(e,c)=SchedulerActualSetStep(e,chosen)
    BY ONLY <1>input,IsaM("simp"),SMT DEF SchedulerActualSetStep,SchedulerSubstituteHead
<1>exact. /\ next = SchedulerActiveStep(e).next
          /\ body = SchedulerActualSetValue(SchedulerActiveStep(e),child)
    BY ONLY <1>same,<1>read,SMT DEF SchedulerActiveStep,chosen
<1>. QED BY ONLY <1>frame,<1>exact DEF SchedulerPush,SchedulerUnwind

THEOREM CertifiedTraceDescribesTheSourceSchedulerReturn ==
    ASSUME NEW entry, NEW trace, NEW shapes, Len(entry.values) \in Nat,
           SchedulerActualBlockReturns(entry,trace), SchedulerReturnedEntriesAreReady(trace,shapes)
    PROVE SchedulerReturnedValue(entry) = trace.bodies[1]
PROOF
<1>. DEFINE n == Len(entry.values)
            last == n+1
            calls == SchedulerCalls(entry,n)
            returns == SchedulerResults(calls,n)
            seen == [k \in 0..n |-> trace.bodies[last-k]]
            terminal == SchedulerActualEmptyValue(calls[last])
            pop(child,k) == SchedulerUnwind(calls[last-k],child)
<1>bounds. /\ 1 \in Nat /\ 0 \in Nat /\ n \in Nat /\ last \in Nat /\ 1 <= last /\ 0 <= n
    BY ONLY (Len(entry.values) \in Nat), SMT DEF n,last
<1>domain. /\ trace.entries[1]=entry /\ DOMAIN trace.entries=1..last
           /\ \A i \in 1..n : SchedulerActualSetTrace(trace.entries[i],trace.entries[i+1],trace.bodies[i],trace.bodies[i+1],trace.rows[i])
    BY ONLY SchedulerActualBlockReturns(entry,trace),ActualSchedulerBlockReturnExposesBodiesAndSteps DEF n,last
<1>edge. \A i \in 1..n :
     /\ trace.entries[i+1]=SchedulerPush(trace.entries[i],0)
     /\ trace.bodies[i]=SchedulerUnwind(trace.entries[i],trace.bodies[i+1])
    <2>. TAKE i \in 1..n
    <2>in. i \in DOMAIN trace.entries
        BY ONLY (i \in 1..n),<1>bounds,<1>domain,SMT DEF last
    <2>ready. SchedulerBlockEntryReady(trace.entries[i],shapes)
        BY ONLY <2>in,SchedulerReturnedEntriesAreReady(trace,shapes), SMT
            DEF SchedulerReturnedEntriesAreReady,TraceConstruction!TraceStatesAreReady
    <2>. QED BY ONLY (i \in 1..n),<1>domain,<2>ready,CertifiedEdgeFollowsTheSourceCallAndReturn,SMT
<1>down. \A i \in (1+1)..last : trace.entries[i]=SchedulerPush(trace.entries[i-1],i)
    <2>. TAKE i \in (1+1)..last
    <2>index. /\ i-1 \in 1..n /\ i-1+1=i
        BY ONLY (i \in (1+1)..last),<1>bounds,SMT DEF last
    <2>child. trace.entries[i]=SchedulerPush(trace.entries[i-1],0)
        BY ONLY <2>index,<1>edge,SMT
    <2>. QED BY ONLY <2>child DEF SchedulerPush
<1>calls. \A i \in 1..last : calls[i]=trace.entries[i]
    <2>domain. DOMAIN trace.entries=1..last BY ONLY <1>domain,PTL
    <2>first. trace.entries[1]=entry BY ONLY <1>domain,PTL
    <2>forward. \A i \in 1..last : PushRule!CallChain(entry,1,last,SchedulerPush)[i]=trace.entries[i]
        BY ONLY <1>bounds,<2>domain,<2>first,<1>down,PushRule!TheForwardCallsAreDetermined,Zenon,SMT,IsaM("blast")
    <2>. QED BY ONLY <2>forward DEF calls,SchedulerCalls,last
<1>base. trace.bodies[last]=SchedulerActualEmptyValue(trace.entries[last])
    BY ONLY SchedulerActualBlockReturns(entry,trace) DEF SchedulerActualBlockReturns,TraceConstruction!FiniteScheduleReturns,n,last
<1>zero. seen[0]=terminal /\ DOMAIN seen=0..n
    BY ONLY <1>bounds,<1>calls,<1>base,SMT DEF seen,terminal,last
<1>up. \A k \in (0+1)..n : seen[k]=pop(seen[k-1],k)
    <2>. TAKE k \in (0+1)..n
    <2>index. /\ last-k \in 1..n /\ k \in 0..n /\ k-1 \in 0..n /\ last-(k-1)=(last-k)+1
        BY ONLY (k \in (0+1)..n),<1>bounds,SMT DEF last
    <2>parent. trace.bodies[last-k]=SchedulerUnwind(trace.entries[last-k],trace.bodies[(last-k)+1])
        BY ONLY <2>index,<1>edge,SMT
    <2>. QED BY ONLY <2>index,<2>parent,<1>calls,(k \in (0+1)..n),<1>bounds,SMT DEF seen,pop,last
<1>fold. \A k \in 0..n : CallChain(terminal,0,n,pop)[k]=seen[k]
    BY ONLY <1>bounds,<1>zero,<1>up,PointwiseCallsDetermineChain
<1>top. seen[n]=trace.bodies[1]
    BY ONLY <1>bounds,SMT DEF seen,last
<1>index. n \in 0..n BY ONLY <1>bounds,SMT
<1>root. CallChain(terminal,0,n,pop)[n]=seen[n]
    BY ONLY <1>fold,<1>index,IsaM("blast")
<1>evaluate. SchedulerReturnedValue(entry)=CallChain(terminal,0,n,pop)[n]
    BY ONLY DEF SchedulerReturnedValue,SchedulerResults,terminal,calls,pop,n,last
<1>. QED BY ONLY <1>root,<1>evaluate,<1>top,SMT

SchedulerEntryFor(statements,allocator) ==
    LET empty == [k \in {} |-> k]
        old == [k \in {SchedulerRootBindingsField,SchedulerRecordingLastWriteField} |->
                  IF k=SchedulerRootBindingsField THEN empty ELSE <<>>]
    IN SchedulerBlockEntry(statements,<<>>,old,allocator)

\* The entry construction models the empty pending list, bindings and optional
\* lastWrite at the local function's default call. The allocator is captured.
ScheduleAtomicBody(statements,allocator) ==
    IF SchedulerDeclAndEntry THEN SchedulerReturnedValue(SchedulerEntryFor(statements,allocator))
    ELSE "unrecognized scheduler entry"

THEOREM TheCertifiedBodyIsTheArgumentToLower ==
    ASSUME NEW statements, NEW allocator, NEW shapes, NEW before \in AssignmentBindings, NEW Lower(_),
           SchedulerBlockEntryReady(SchedulerEntryFor(statements,allocator),shapes)
    PROVE \E trace,history : LET entry == SchedulerEntryFor(statements,allocator)
                                 schedule(xs) == ScheduleAtomicBody(xs,allocator)
                                 call == LowerCall(statements,schedule,Lower)
                             IN
               /\ ScheduledRowsHaveCompleteOutcome(entry,shapes,before,trace,history)
               /\ schedule(statements)=trace.bodies[1]
               /\ call=[called |-> TRUE,body |-> trace.bodies[1],result |-> Lower(trace.bodies[1])]
PROOF
<1>. DEFINE entry == SchedulerEntryFor(statements,allocator)
            schedule(xs) == ScheduleAtomicBody(xs,allocator)
            call == LowerCall(statements,schedule,Lower)
<1>empty. DOMAIN SchedulerOldNames(entry)={}
    BY ONLY SMT DEF SchedulerOldNames,StateExprIncomingVariableNames,entry,SchedulerEntryFor,SchedulerBlockEntry
<1>nat. Len(entry.values) \in Nat
    BY ONLY SchedulerBlockEntryReady(SchedulerEntryFor(statements,allocator),shapes),
        LenProperties,SMT DEF entry,SchedulerBlockEntryReady
<1>witness. PICK trace,history : ScheduledRowsHaveCompleteOutcome(entry,shapes,before,trace,history)
    BY ONLY SchedulerBlockEntryReady(SchedulerEntryFor(statements,allocator),shapes),<1>empty,(before \in AssignmentBindings),
            TheSchedulerSuppliesItsCertifiedRows DEF entry,ScheduledRowsHaveCompleteOutcome
<1>facts. /\ SchedulerActualBlockReturns(entry,trace) /\ SchedulerReturnedEntriesAreReady(trace,shapes)
    BY ONLY <1>witness, PTL DEF ScheduledRowsHaveCompleteOutcome
<1>body. SchedulerReturnedValue(entry)=trace.bodies[1]
    BY ONLY <1>facts,<1>nat,CertifiedTraceDescribesTheSourceSchedulerReturn
<1>returned. schedule(statements)=trace.bodies[1]
    BY ONLY TheSchedulerInvokesItsLocalFunctionOnStatements,<1>body DEF schedule,ScheduleAtomicBody,entry
<1>forward. call=[called |-> TRUE,body |-> schedule(statements),result |-> Lower(schedule(statements))]
    BY ONLY LowerReceivesTheSchedulerReturn DEF call
<1>observed. call=[called |-> TRUE,body |-> trace.bodies[1],result |-> Lower(trace.bodies[1])]
    BY ONLY <1>returned,<1>forward,SMT
<1>. WITNESS trace,history
<1>. QED BY ONLY <1>witness,<1>returned,<1>observed,PTL

\* The depth bound is the number of authored writes. Run takes the actual body
\* and initial empty dictionary; neither the trace nor the action column is an input.
StandaloneBlockAction(statements, allocator, Less(_, _)) ==
    LET schedule(xs) == ScheduleAtomicBody(xs,allocator)
        run(body,values) == ActualStandaloneRun(body,values,Len(statements),Less)
    IN ActualStandaloneLowerAtomicStepAction(statements,schedule,run)

ActionsForReturnedLets(trace, Less(_, _)) ==
    LET terminal == ActualStandaloneTerminalRun(trace.bodies[Len(trace.rows)+1],AtomicLowererEmptyValues,Less)
    IN CompiledLetSuffixes(trace,AtomicLowererEmptyValues,terminal)

THEOREM ActualReturnedBlockSuppliesTheCompleteAssignmentOutcome ==
    ASSUME NEW statements, NEW allocator, NEW shapes, NEW before \in AssignmentBindings, NEW Less(_, _),
           SchedulerBlockEntryReady(SchedulerEntryFor(statements,allocator),shapes)
    PROVE \E trace,history :
        /\ ScheduledRowsHaveCompleteOutcome(SchedulerEntryFor(statements,allocator),shapes,before,trace,history)
        /\ ScheduleAtomicBody(statements,allocator) = trace.bodies[1]
        /\ LET actions == ActionsForReturnedLets(trace,Less)
           IN /\ StandaloneBlockAction(statements,allocator,Less) = actions[1]
              /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
              /\ \A i \in DOMAIN trace.rows :
                    /\ actions[i].name = trace.rows[i].binding
                    /\ actions[i].value = trace.rows[i].substitutedRhs
                    /\ actions[i].body = actions[i+1]
PROOF
<1>. DEFINE entry == SchedulerEntryFor(statements,allocator)
            schedule(xs) == ScheduleAtomicBody(xs,allocator)
            run(body,values) == ActualStandaloneRun(body,values,Len(statements),Less)
            lower(body) == run(body,AtomicLowererEmptyValues).action
            call == LowerCall(statements,schedule,lower)
<1>entry. entry.values=statements
    BY ONLY IsaM("simp"),SMT DEF entry,SchedulerEntryFor,SchedulerBlockEntry
<1>handoff. PICK trace,history :
    /\ ScheduledRowsHaveCompleteOutcome(entry,shapes,before,trace,history)
    /\ schedule(statements)=trace.bodies[1]
    /\ call=[called |-> TRUE,body |-> trace.bodies[1],result |-> lower(trace.bodies[1])]
    BY ONLY SchedulerBlockEntryReady(SchedulerEntryFor(statements,allocator),shapes),
        (before \in AssignmentBindings),TheCertifiedBodyIsTheArgumentToLower
        DEF entry,schedule,call
<1>. DEFINE count == Len(trace.rows)
            terminal == ActualStandaloneTerminalRun(trace.bodies[count+1],AtomicLowererEmptyValues,Less)
            actions == CompiledLetSuffixes(trace,AtomicLowererEmptyValues,terminal)
<1>actual. SchedulerActualBlockReturns(entry,trace) /\ count=Len(entry.values)
    BY ONLY <1>handoff,PTL DEF ScheduledRowsHaveCompleteOutcome,count
<1>nat. Len(entry.values) \in Nat
    BY ONLY SchedulerBlockEntryReady(SchedulerEntryFor(statements,allocator),shapes),
        LenProperties,SMT DEF entry,SchedulerBlockEntryReady
<1>items. PICK items : \A i \in 1..count :
             /\ trace.bodies[i] = <<trace.bodies[i][1]>> /\ trace.bodies[i][1].kind = "letBinding"
             /\ trace.bodies[i][1].body = trace.bodies[i+1] /\ trace.bodies[i+1] \in Seq(items)
    BY ONLY <1>actual,<1>nat,ReturnedSchedulerBodiesSupplyTheActualDefineColumn,SMT DEF count
<1>size. count \in Nat /\ Len(statements)=count
    BY ONLY <1>actual,<1>nat,<1>entry,SMT
<1>recursive. ActualStandaloneRun(trace.bodies[1],AtomicLowererEmptyValues,count,Less).action=actions[1]
    BY ONLY <1>items,<1>size,StandaloneRunReturnsTheCompiledLetSuffix DEF count,actions,terminal
<1>outer. StandaloneBlockAction(statements,allocator,Less)=run(schedule(statements),AtomicLowererEmptyValues).action
    BY ONLY ActualStandaloneLowersTheSchedulerReturnWithEmptyValues DEF StandaloneBlockAction,run,schedule
<1>same. StandaloneBlockAction(statements,allocator,Less)=actions[1]
    BY ONLY <1>outer,<1>recursive,<1>size,<1>handoff,SMT DEF run
<1>column. /\ ActualActionDefinesMatchTheScheduledLets(trace,actions)
           /\ \A i \in DOMAIN trace.rows : /\ actions[i].name = trace.rows[i].binding
                                            /\ actions[i].value = trace.rows[i].substitutedRhs
    <2>available. \A pending,terminalAction :
        LET column == CompiledLetSuffixes(trace,pending,terminalAction)
        IN /\ ActualActionDefinesMatchTheScheduledLets(trace,column)
           /\ \A i \in DOMAIN trace.rows :
                 /\ column[i].name = trace.rows[i].binding
                 /\ column[i].value = trace.rows[i].substitutedRhs
        BY ONLY <1>handoff, PTL DEF ScheduledRowsHaveCompleteOutcome
    <2>. QED BY ONLY <2>available, IsaM("blast") DEF actions
<1>each. \A i \in DOMAIN trace.rows :
                    /\ actions[i].name = trace.rows[i].binding
                    /\ actions[i].value = trace.rows[i].substitutedRhs
                    /\ actions[i].body = actions[i+1]
    BY ONLY <1>column,IsaM("auto"),SMT DEF ActualActionDefinesMatchTheScheduledLets
<1>. WITNESS trace,history
<1>. QED BY ONLY <1>handoff,<1>same,<1>column,<1>each,PTL DEF entry,schedule,ActionsForReturnedLets,actions,terminal,count
====
