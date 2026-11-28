---- MODULE AtomicSchedulerSingleSet ----
EXTENDS AtomicSchedulerAssignmentRows, AtomicSchedulerSetSourceOperands, AtomicSchedulerAllocator,
        AtomicStateExprSubstitution

SchedulerBlockEntry(values, assignments, old, allocator) ==
    [values |-> values, assignments |-> assignments, old |-> old, allocator |-> allocator]

\* Incoming bindings are the scheduler's map of root to .variable(binder).
\* 'used' and the binder payloads share the canonical Swift-name encoding.
SchedulerIncomingMapIsInItsImage(entry) ==
    LET incoming == entry.old[SchedulerRootBindingsField]
    IN /\ DOMAIN incoming \subseteq Keys
       /\ \A key \in DOMAIN incoming :
              \E binder \in entry.allocator.used : incoming[key] = [variable |-> binder]

SchedulerBlockEntryReady(entry, shapes) ==
    /\ entry.values \in Seq(shapes)
    /\ \A index \in 1..Len(entry.values) :
           SchedulerSupportedAssignmentStatement(entry.values[index])
    /\ {SchedulerRootBindingsField, SchedulerRecordingLastWriteField} \subseteq DOMAIN entry.old
    /\ SchedulerIncomingMapIsInItsImage(entry)
    /\ AtomicAllocatorCanServe(entry.allocator, Len(entry.values))

\* binding() mutates its captures. Its allocation result is computed for this
\* occurrence only. The recursive call closes over allocation.after.
SchedulerSubstituteHead(statement, compiled, incoming, rhs) ==
    IF rhs = statement.rhs
    THEN ActualStateExprSubstitutionProjection(SwiftSourceArrayAsView(compiled.source), incoming)
    ELSE "unbound RHS"

SchedulerActualSetStep(entry, compiled) ==
    LET allocation == AtomicBindingAllocation(entry.allocator)
        descriptor == SchedulerSetDescriptor(entry.values, entry.old, LAMBDA name : allocation.name)
        input == SchedulerSetEntry(entry.values, entry.assignments, entry.old)
        statement == Head(entry.values)
        locals == SchedulerExecuteSetLocals(input, descriptor,
                    LAMBDA incoming, rhs : SchedulerSubstituteHead(statement, compiled, incoming, rhs),
                    ActualSchedulerRecordingResult)
        next == SchedulerBlockEntry(locals[SchedulerNameSuffix], locals[SchedulerNamePending],
                                    locals[SchedulerNameNext], allocation.after)
    IN [descriptor |-> descriptor, locals |-> locals, next |-> next]

\* The decoded nested call reads all three actual operands. Its return is the
\* value proved for that exact invocation, including the allocator after binding().
SchedulerActualSetChild(step, child, name, values, pending, old) ==
    IF /\ name = SchedulerNameSchedule
       /\ values = step.next.values
       /\ pending = step.next.assignments
       /\ old = step.next.old
    THEN child ELSE "unbound call"

SchedulerActualSetValue(step, child) ==
    SchedulerSetReturn(step.locals,
        LAMBDA name, values, pending, old : SchedulerActualSetChild(step, child, name, values, pending, old))

THEOREM ActualSchedulerSetReturnWrapsTheExactRecursiveValue ==
    ASSUME NEW entry, NEW compiled, NEW child
    PROVE LET step == SchedulerActualSetStep(entry, compiled)
              locals == step.locals
          IN SchedulerActualSetValue(step, child) =
                <<[kind |-> "letBinding",
                   variable |-> locals[SchedulerNameUpdate][SchedulerNameBinding],
                   value |-> locals[SchedulerNameUpdated],
                   body |-> child]>>
PROOF
<1>. DEFINE step == SchedulerActualSetStep(entry, compiled)
            locals == step.locals
<1>arguments. /\ step.next.values = locals[SchedulerNameSuffix]
              /\ step.next.assignments = locals[SchedulerNamePending]
              /\ step.next.old = locals[SchedulerNameNext]
    BY ONLY SMT DEF step, locals, SchedulerActualSetStep, SchedulerBlockEntry
<1>return. SchedulerActualSetValue(step, child) =
    <<[kind |-> "letBinding",
       variable |-> locals[SchedulerNameUpdate][SchedulerNameBinding],
       value |-> locals[SchedulerNameUpdated],
       body |-> SchedulerActualSetChild(step, child, SchedulerNameSchedule, locals[SchedulerNameSuffix],
                                       locals[SchedulerNamePending], locals[SchedulerNameNext])]>>
    BY ONLY ActualSchedulerReturnOperands, SMT DEF SchedulerActualSetValue, SchedulerSetReturn, locals
<1>child. SchedulerActualSetChild(step, child, SchedulerNameSchedule, locals[SchedulerNameSuffix],
                                 locals[SchedulerNamePending], locals[SchedulerNameNext]) = child
    BY ONLY <1>arguments, SMT DEF SchedulerActualSetChild
<1>. QED BY ONLY <1>return, <1>child, SMT DEF locals

THEOREM ActualSchedulerSetStepUsesTheActualHeadAndTransfersEntry ==
    ASSUME NEW entry, NEW shapes, SchedulerBlockEntryReady(entry, shapes), entry.values # <<>>,
           NEW compiled, SchedulerAssignmentRhsInvocation(Head(entry.values), compiled)
    PROVE LET step == SchedulerActualSetStep(entry, compiled)
              allocation == AtomicBindingAllocation(entry.allocator)
              descriptor == step.descriptor
              statement == Head(entry.values)
          IN /\ step.next.values = Tail(entry.values)
             /\ step.next.assignments =
                    Append(SchedulerKeepPending(entry.assignments, statement.target),
                           [target |-> statement.target, value |-> [variable |-> allocation.name]])
             /\ step.next.old = ActualSchedulerRecordingResult(entry.old, descriptor)
             /\ descriptor.target = statement.target
             /\ descriptor[SchedulerNameBinding] = allocation.name
             /\ descriptor.predecessor =
                    IF entry.old[SchedulerRecordingLastWriteField] = <<>> THEN <<>>
                    ELSE entry.old[SchedulerRecordingLastWriteField][SchedulerNameBinding]
             /\ step.locals[SchedulerNameUpdate] = descriptor
             /\ step.locals[SchedulerNameUpdated] =
                    ActualStateExprSubstitutionProjection(SwiftSourceArrayAsView(compiled.source),
                                                          entry.old[SchedulerRootBindingsField])
             /\ ActualStateExprSubstitutionReturns(SwiftSourceArrayAsView(compiled.source),
                    entry.old[SchedulerRootBindingsField], step.locals[SchedulerNameUpdated])
             /\ step.locals[SchedulerNameUpdated] =
                    StateExprReplaceProjection(SwiftSourceArrayAsView(compiled.source),
                        StateExprIncomingVariableNames(entry.old[SchedulerRootBindingsField]))
             /\ allocation.name \notin entry.allocator.used
             /\ step.next.allocator = allocation.after
             /\ step.next.allocator.used = entry.allocator.used \cup {allocation.name}
             /\ step.next.old[SchedulerRootBindingsField] =
                    SchedulerWriteLocal(entry.old[SchedulerRootBindingsField], statement.target,
                                        [variable |-> allocation.name])
             /\ step.next.old[SchedulerRecordingLastWriteField] = descriptor
             /\ SchedulerBlockEntryReady(step.next, shapes)
PROOF
<1>. DEFINE allocation == AtomicBindingAllocation(entry.allocator)
            step == SchedulerActualSetStep(entry, compiled)
            statement == Head(entry.values)
            descriptor == step.descriptor
            input == SchedulerSetEntry(entry.values, entry.assignments, entry.old)
            locals == step.locals
            Subst(incoming,rhs) == SchedulerSubstituteHead(statement,compiled,incoming,rhs)
<1>list. /\ entry.values \in Seq(shapes) /\ Len(entry.values) \in Nat \ {0}
          /\ Tail(entry.values) \in Seq(shapes)
          /\ Len(Tail(entry.values)) = Len(entry.values) - 1
          /\ \A index \in 1..Len(Tail(entry.values)) :
                SchedulerSupportedAssignmentStatement(Tail(entry.values)[index])
    BY ONLY SchedulerBlockEntryReady(entry, shapes), (entry.values # <<>>), SeqDef, LenProperties,
        HeadTailProperties, SMT DEF SchedulerBlockEntryReady
<1>allocated. /\ allocation.name \notin entry.allocator.used
               /\ allocation.after.used = entry.allocator.used \cup {allocation.name}
               /\ AtomicAllocatorCanServe(allocation.after, Len(Tail(entry.values)))
    BY ONLY SchedulerBlockEntryReady(entry, shapes), <1>list,
        ActualAllocatorReturnsAFreshBinderForTheShorterSuffix, SMT DEF SchedulerBlockEntryReady, allocation
<1>shape. /\ descriptor = SchedulerSetDescriptor(entry.values, entry.old, LAMBDA name: allocation.name)
          /\ locals = SchedulerExecuteSetLocals(input, descriptor, Subst, ActualSchedulerRecordingResult)
          /\ step.next = SchedulerBlockEntry(locals[SchedulerNameSuffix], locals[SchedulerNamePending],
                                              locals[SchedulerNameNext], allocation.after)
    BY ONLY SMT DEF step, descriptor, locals, Subst, statement, input, SchedulerActualSetStep
<1>descriptor. /\ SchedulerNameBinding \in DOMAIN descriptor
                /\ descriptor.target = statement.target
                /\ descriptor[SchedulerNameBinding] = allocation.name
                /\ descriptor.predecessor =
                       IF entry.old[SchedulerRecordingLastWriteField] = <<>> THEN <<>>
                       ELSE entry.old[SchedulerRecordingLastWriteField][SchedulerNameBinding]
    <2>tokens.
        /\ SwiftSchedulerLocalNames.previousField = SchedulerRecordingLastWriteField
        /\ SwiftSchedulerLocalNames.previousBinder = SchedulerNameBinding
        /\ SwiftSchedulerLocalNames.allocator = SchedulerNameBinding
        /\ SwiftSchedulerLocalNames.previousReceiver = SwiftSchedulerLocalNames.repls
        /\ SwiftSchedulerLocalNames.rootReceiver = SwiftSchedulerLocalNames.patternTarget
        /\ SwiftSchedulerLocalNames.targetProperty = <<114,111,111,116>>
        BY ONLY TheActualDescriptorUsesTheSourceMemberNames
    <2>keys. /\ SchedulerNameBinding # "target" /\ SchedulerNameBinding # "predecessor"
        BY ONLY IsaM("simp"), SMT DEF SchedulerNameBinding
    <2>defined. descriptor = SchedulerSetDescriptor(entry.values, entry.old, LAMBDA unused : allocation.name)
        BY ONLY <1>shape
    <2>normalized. descriptor =
        [k \in {"target", "predecessor", SchedulerNameBinding} |->
            CASE k = "target" -> statement.target
              [] k = "predecessor" ->
                   IF entry.old[SchedulerRecordingLastWriteField] = <<>> THEN <<>>
                   ELSE entry.old[SchedulerRecordingLastWriteField][SchedulerNameBinding]
              [] OTHER -> allocation.name]
        BY ONLY <2>defined, <2>tokens, SMT DEF SchedulerSetDescriptor, statement
    <2>. QED BY ONLY <2>normalized, <2>keys, SMT
<1>entry. SchedulerSetEntryBindings(entry.values, entry.assignments, entry.old,
                                     statement.target, statement.rhs, input)
    BY ONLY (entry.values # <<>>), ActualRootSetEntryHasTheAuthoredOperands, SMT DEF input, statement
<1>input. /\ input[SchedulerNameValues] = entry.values
           /\ input[SchedulerNameAssignments] = entry.assignments
           /\ input[SchedulerRootReplacements] = entry.old
           /\ input[SchedulerRootPatternValue] = statement.rhs
    BY ONLY <1>entry DEF SchedulerSetEntryBindings
<1>rawRhsCall. SchedulerRhsLocal(input, Subst) =
    Subst(input[SchedulerRootReplacements][SchedulerRootBindingsField], input[SchedulerRootPatternValue])
    BY ONLY TheSourceRhsCallUsesTheDeclaredNames, SMT
        DEF SchedulerRhsLocal, SchedulerUse
<1>rhsCall. SchedulerRhsLocal(input, Subst) =
                Subst(entry.old[SchedulerRootBindingsField], statement.rhs)
    BY ONLY <1>rawRhsCall, <1>input, SMT
<1>rhsReduction. Subst(entry.old[SchedulerRootBindingsField], statement.rhs) =
                       ActualStateExprSubstitutionProjection(SwiftSourceArrayAsView(compiled.source),
                                                              entry.old[SchedulerRootBindingsField])
    BY ONLY IsaM("simp") DEF Subst, SchedulerSubstituteHead
<1>rhs. SchedulerRhsLocal(input, Subst) =
              ActualStateExprSubstitutionProjection(SwiftSourceArrayAsView(compiled.source),
                                                     entry.old[SchedulerRootBindingsField])
    BY ONLY <1>rhsCall, <1>rhsReduction, SMT
<1>view. CompilerOccurrenceTree(SwiftSourceArrayAsView(compiled.source), compiled.source.count)
    BY ONLY SchedulerAssignmentRhsInvocation(Head(entry.values), compiled),
        ActualAssignmentRhsSourceArrayHasTheOccurrenceTree
<1>substitution.
    /\ ActualStateExprSubstitutionReturns(SwiftSourceArrayAsView(compiled.source),
            entry.old[SchedulerRootBindingsField], SchedulerRhsLocal(input, Subst))
    /\ SchedulerRhsLocal(input, Subst) =
            StateExprReplaceProjection(SwiftSourceArrayAsView(compiled.source),
                StateExprIncomingVariableNames(entry.old[SchedulerRootBindingsField]))
    BY ONLY <1>view, <1>rhs, ActualStateExprSubstitutionReturnsTheSourceProjection, SMT
<1>rawPending. SchedulerPendingLocal(input, descriptor) =
               Append(SchedulerKeepPending(input[SchedulerNameAssignments], descriptor.target),
                      [target |-> descriptor.target, value |-> [variable |-> descriptor[SchedulerNameBinding]]])
    BY ONLY SourcePendingWritesUseTheDeclaredNames, SMT
        DEF SchedulerPendingLocal, SchedulerUse
<1>pending. SchedulerPendingLocal(input, descriptor) =
              Append(SchedulerKeepPending(entry.assignments, statement.target),
                     [target |-> statement.target, value |-> [variable |-> allocation.name]])
    BY ONLY <1>rawPending, <1>input, <1>descriptor, SMT
<1>rawRecorded. SchedulerNextLocal(input, descriptor, ActualSchedulerRecordingResult) =
                 ActualSchedulerRecordingResult(input[SchedulerRootReplacements], descriptor)
    BY ONLY SourceRecordingUsesTheDeclaredNames, SMT
        DEF SchedulerNextLocal, SchedulerUse
<1>recorded. SchedulerNextLocal(input, descriptor, ActualSchedulerRecordingResult) =
                 ActualSchedulerRecordingResult(entry.old, descriptor)
    BY ONLY <1>rawRecorded, <1>input, SMT
<1>rawOutputs. /\ locals[SchedulerNameUpdate] = descriptor
                /\ locals[SchedulerNameSuffix] = Tail(input[SchedulerNameValues])
                /\ locals[SchedulerNameUpdated] = SchedulerRhsLocal(input, Subst)
                /\ locals[SchedulerNameNext] = SchedulerNextLocal(input, descriptor, ActualSchedulerRecordingResult)
                /\ locals[SchedulerNamePending] = SchedulerPendingLocal(input, descriptor)
    BY ONLY <1>shape, SourceSetLocalResultsUseDistinctDeclaredSlots, SMT
        DEF SchedulerExecuteSetLocals
<1>outputs. /\ locals[SchedulerNameUpdate] = descriptor
             /\ locals[SchedulerNameSuffix] = Tail(entry.values)
             /\ locals[SchedulerNameUpdated] = SchedulerRhsLocal(input, Subst)
             /\ locals[SchedulerNameNext] = SchedulerNextLocal(input, descriptor, ActualSchedulerRecordingResult)
             /\ locals[SchedulerNamePending] = SchedulerPendingLocal(input, descriptor)
    BY ONLY <1>rawOutputs, <1>input, SMT
<1>target. statement.target \in Keys
    BY ONLY SchedulerBlockEntryReady(entry, shapes), (entry.values # <<>>), <1>list,
        HeadTailProperties, SeqDef, SMT DEF SchedulerBlockEntryReady, SchedulerSupportedAssignmentStatement, statement
<1>binding. LET incoming == entry.old[SchedulerRootBindingsField]
               wrote == ActualSchedulerRecordingResult(entry.old, descriptor)[SchedulerRootBindingsField]
           IN wrote = SchedulerWriteLocal(incoming, statement.target, [variable |-> allocation.name])
    <2>field. SchedulerRootBindingsField \in DOMAIN entry.old
        BY ONLY SchedulerBlockEntryReady(entry, shapes), SMT DEF SchedulerBlockEntryReady
    <2>record. ActualSchedulerRecordingResult(entry.old, descriptor)[SchedulerRootBindingsField] =
        SchedulerWriteLocal(entry.old[SchedulerRootBindingsField], descriptor.target,
                            [variable |-> descriptor[SchedulerNameBinding]])
        BY ONLY <2>field, <1>descriptor, ActualSchedulerRecordingWritesOnlyTheTarget, SMT
    <2>. QED BY ONLY <1>descriptor, <2>record, SMT
<1>old. /\ {SchedulerRootBindingsField, SchedulerRecordingLastWriteField} \subseteq
               DOMAIN ActualSchedulerRecordingResult(entry.old, descriptor)
         /\ ActualSchedulerRecordingResult(entry.old, descriptor)[SchedulerRecordingLastWriteField] = descriptor
    <2>shape. SchedulerRootBindingsField \in DOMAIN entry.old
        BY ONLY SchedulerBlockEntryReady(entry, shapes), SMT DEF SchedulerBlockEntryReady
    <2>update. LET mapping == SchedulerWriteLocal(entry.old[SchedulerRootBindingsField], descriptor.target,
                                    [variable |-> descriptor[SchedulerNameBinding]])
               IN ActualSchedulerRecordingResult(entry.old, descriptor) =
                   SchedulerWriteLocal(SchedulerWriteLocal(entry.old, SchedulerRootBindingsField, mapping),
                                       SchedulerRecordingLastWriteField, descriptor)
        BY ONLY <2>shape, <1>descriptor, ActualSchedulerRecordingWritesOnlyTheTarget, SMT
    <2>. QED BY ONLY <2>update, SMT DEF SchedulerWriteLocal
<1>new. /\ step.next.values = Tail(entry.values)
         /\ step.next.old = ActualSchedulerRecordingResult(entry.old, descriptor)
         /\ step.next.allocator = allocation.after
         /\ step.next.assignments = SchedulerPendingLocal(input, descriptor)
    BY ONLY <1>shape, <1>outputs, <1>recorded, SMT DEF SchedulerBlockEntry
<1>map. SchedulerIncomingMapIsInItsImage(step.next)
    <2>prior. SchedulerIncomingMapIsInItsImage(entry)
        BY ONLY SchedulerBlockEntryReady(entry, shapes) DEF SchedulerBlockEntryReady
    <2>. QED BY ONLY <2>prior, <1>new, <1>target, <1>allocated, <1>binding, SMT
        DEF SchedulerIncomingMapIsInItsImage, SchedulerWriteLocal
<1>ready. SchedulerBlockEntryReady(step.next, shapes)
    BY ONLY <1>new, <1>old, <1>map, <1>allocated, <1>list, SMT DEF SchedulerBlockEntryReady
<1>. QED BY ONLY <1>new, <1>ready, <1>old, <1>descriptor, <1>rhs, <1>pending, <1>outputs, <1>allocated, <1>substitution, <1>binding, SMT
    DEF statement

====
