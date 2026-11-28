---- MODULE AtomicSchedulerAuthoredPrefix ----
EXTENDS AtomicSchedulerRecording

SchedulerSetEntry(block, pending, old) ==
    LET n == SwiftSchedulerLocalNames
    IN [k \in {n.values, n.assignments, n.repls, n.patternValue, n.patternTarget} |->
           CASE k = n.values -> block
             [] k = n.assignments -> pending
             [] k = n.repls -> old
             [] k = n.patternTarget -> Head(block).target
             [] OTHER -> Head(block).rhs]

\* Pattern matching the first .set(.root(key), rhs) projects target and rhs without running the RHS.
\* 'descriptor' is the value of the actual binding allocation, which precedes the LET.
SchedulerSetEntryBindings(block, pending, old, target, rhs, env) ==
    /\ {SchedulerNameValues, SchedulerNameAssignments, SchedulerRootReplacements,
         SchedulerRootPatternValue, <<116, 97, 114, 103, 101, 116>>} \subseteq DOMAIN env
    /\ env[SchedulerNameValues] = block /\ env[SchedulerNameAssignments] = pending
    /\ env[SchedulerRootReplacements] = old /\ env[SchedulerRootPatternValue] = rhs
    /\ env[<<116, 97, 114, 103, 101, 116>>] = target

THEOREM ActualSchedulerRootHeadSuppliesTheContinuation ==
    ASSUME NEW block, NEW roots, block \in Seq(roots), block # <<>>,
           NEW pending, NEW old, SchedulerRootBindingsField \in DOMAIN old,
           NEW descriptor, SchedulerNameBinding \in DOMAIN descriptor,
           descriptor.target = Head(block).target,
           NEW Substitute(_, _), NEW recur(_, _, _, _)
    PROVE LET row == Head(block)
              env == SchedulerSetEntry(block, pending, old)
              locals == SchedulerExecuteSetLocals(env, descriptor, Substitute, ActualSchedulerRecordingResult)
              binder == descriptor[SchedulerNameBinding]
              keep == SchedulerKeepPending(pending,row.target)
              commits == Append(keep, [target |-> row.target, value |-> [variable |-> binder]])
              bindings == SchedulerWriteLocal(old[SchedulerRootBindingsField], row.target, [variable |-> binder])
              next == SchedulerWriteLocal(SchedulerWriteLocal(old, SchedulerRootBindingsField, bindings),
                                         SchedulerRecordingLastWriteField, descriptor)
          IN SchedulerSetReturn(locals, recur) =
              <<[kind |-> "letBinding", variable |-> binder,
                 value |-> Substitute(old[SchedulerRootBindingsField], row.rhs),
                 body |-> recur(SchedulerNameSchedule, Tail(block), commits, next)]>>
PROOF
<1>. DEFINE row == Head(block)
            env == SchedulerSetEntry(block, pending, old)
            locals == SchedulerExecuteSetLocals(env, descriptor, Substitute, ActualSchedulerRecordingResult)
            binder == descriptor[SchedulerNameBinding]
            keep == SchedulerKeepPending(pending,row.target)
            commits == Append(keep, [target |-> row.target, value |-> [variable |-> binder]])
            bindings == SchedulerWriteLocal(old[SchedulerRootBindingsField], row.target, [variable |-> binder])
            next == SchedulerWriteLocal(SchedulerWriteLocal(old, SchedulerRootBindingsField, bindings),
                                         SchedulerRecordingLastWriteField, descriptor)
<1>known. /\ SchedulerLexicalNames.values = SchedulerNameValues
          /\ SchedulerLexicalNames.assignments = SchedulerNameAssignments
          /\ SchedulerLexicalNames.repls = SchedulerRootReplacements
          /\ SchedulerLexicalNames.patternTarget = <<116, 97, 114, 103, 101, 116>>
          /\ SchedulerLexicalNames.patternValue = SchedulerRootPatternValue
    BY ONLY IsaM("simp"), SMT DEF SchedulerLexicalNames, SchedulerTokenTarget
<1>names. /\ SwiftSchedulerLocalNames.values = SchedulerNameValues
          /\ SwiftSchedulerLocalNames.assignments = SchedulerNameAssignments
          /\ SwiftSchedulerLocalNames.repls = SchedulerRootReplacements
          /\ SwiftSchedulerLocalNames.patternTarget = <<116, 97, 114, 103, 101, 116>>
          /\ SwiftSchedulerLocalNames.patternValue = SchedulerRootPatternValue
    BY ONLY <1>known, ActualSchedulerLocalNameUses, SMT
<1>entry. SchedulerSetEntryBindings(block, pending, old, row.target, row.rhs, env)
    BY ONLY <1>names, SMT DEF SchedulerSetEntryBindings, env, row, SchedulerSetEntry, SchedulerNameValues,
        SchedulerNameAssignments, SchedulerRootReplacements, SchedulerRootPatternValue
<1>record. ActualSchedulerRecordingResult(old,descriptor) = next
    BY ONLY (SchedulerRootBindingsField \in DOMAIN old), (SchedulerNameBinding \in DOMAIN descriptor),
        (descriptor.target = Head(block).target), ActualSchedulerRecordingWritesOnlyTheTarget, SMT
        DEF next, bindings, binder, row
<1>. DEFINE rawTail == Tail(env[SchedulerNameValues])
            rawOld == env[SchedulerRootReplacements]
            rawRhs == env[SchedulerRootPatternValue]
            rawPending == Append(SchedulerKeepPending(env[SchedulerNameAssignments], descriptor.target),
                                  [target |-> descriptor.target, value |-> [variable |-> binder]])
<1>rhs. SchedulerRhsLocal(env, Substitute) = Substitute(rawOld[SchedulerRootBindingsField], rawRhs)
    BY ONLY SourceSetBindingsResolveTheirUses, SMT
        DEF SchedulerRhsLocal, SchedulerOperandEdges, SchedulerUse, rawOld, rawRhs
<1>recorded. SchedulerNextLocal(env, descriptor, ActualSchedulerRecordingResult) =
              ActualSchedulerRecordingResult(rawOld, descriptor)
    BY ONLY SourceSetBindingsResolveTheirUses, SMT
        DEF SchedulerNextLocal, SchedulerOperandEdges, SchedulerUse, rawOld
<1>writes. SchedulerPendingLocal(env, descriptor) = rawPending
    BY ONLY SourceSetBindingsResolveTheirUses, SMT
        DEF SchedulerPendingLocal, SchedulerOperandEdges, SchedulerUse, rawPending, binder
<1>outputs. /\ locals[SchedulerNameUpdate] = descriptor /\ locals[SchedulerNameSuffix] = rawTail
            /\ locals[SchedulerNameUpdated] = SchedulerRhsLocal(env, Substitute)
            /\ locals[SchedulerNameNext] = SchedulerNextLocal(env, descriptor, ActualSchedulerRecordingResult)
            /\ locals[SchedulerNamePending] = SchedulerPendingLocal(env, descriptor)
    BY ONLY SourceSetBindingsResolveTheirUses, SMT
        DEF locals, SchedulerExecuteSetLocals, SchedulerOperandEdges, rawTail
<1>returned. SchedulerSetReturn(locals, recur) =
    <<[kind |-> "letBinding", variable |-> locals[SchedulerNameUpdate][SchedulerNameBinding],
       value |-> locals[SchedulerNameUpdated],
       body |-> recur(SchedulerNameSchedule, locals[SchedulerNameSuffix], locals[SchedulerNamePending],
                        locals[SchedulerNameNext])]>>
    BY ONLY ActualSchedulerReturnOperands, SMT DEF SchedulerSetReturn
<1>sourceShape. SchedulerSetReturn(locals, recur) =
    <<[kind |-> "letBinding", variable |-> binder,
       value |-> Substitute(rawOld[SchedulerRootBindingsField], rawRhs),
       body |-> recur(SchedulerNameSchedule, rawTail, rawPending, ActualSchedulerRecordingResult(rawOld, descriptor))]>>
    BY ONLY <1>returned, <1>outputs, <1>rhs, <1>writes, <1>recorded, SMT DEF binder
<1>inputs. /\ rawTail = Tail(block) /\ rawOld = old /\ rawRhs = row.rhs /\ rawPending = commits
    BY ONLY <1>entry, (descriptor.target = Head(block).target), SMT
        DEF SchedulerSetEntryBindings, rawTail, rawOld, rawRhs, rawPending, commits, keep, row
<1>result. SchedulerSetReturn(locals,recur) =
    <<[kind |-> "letBinding", variable |-> binder, value |-> Substitute(old[SchedulerRootBindingsField],row.rhs),
       body |-> recur(SchedulerNameSchedule, Tail(block), commits, ActualSchedulerRecordingResult(old,descriptor))]>>
    BY ONLY <1>sourceShape, <1>inputs, SMT
<1>. QED BY ONLY <1>record, <1>result, SMT DEF row, env, locals, binder, keep, commits, next, bindings

\* Atomically assigned root name is a property of the input pattern. Allocate names the
\* normal-return binder allocation operation; its freshness/totality is a separate obligation.
SchedulerSetDescriptor(block,old,Allocate(_)) ==
    LET n == SwiftSchedulerLocalNames
        previous == old[n.previousField]
        allowed == n.previousReceiver = n.repls /\ n.rootReceiver = n.patternTarget
                   /\ n.targetProperty = <<114,111,111,116>>
    IN IF allowed THEN
           [k \in {"target","predecessor", SchedulerNameBinding} |->
               CASE k = "target" -> Head(block).target
                 [] k = "predecessor" -> IF previous = <<>> THEN <<>> ELSE previous[n.previousBinder]
                 [] OTHER -> Allocate(n.allocator)]
       ELSE <<>>

THEOREM ActualSetDescriptorUsesTheAuthoredTargetAndThePreviousBinding ==
    ASSUME NEW block, NEW old, NEW Allocate(_)
    PROVE LET d == SchedulerSetDescriptor(block,old,Allocate)
              prior == old[SchedulerRecordingLastWriteField]
          IN /\ SchedulerNameBinding \in DOMAIN d
             /\ d.target = Head(block).target
             /\ d[SchedulerNameBinding] = Allocate(SchedulerNameBinding)
             /\ d.predecessor = IF prior = <<>> THEN <<>> ELSE prior[SchedulerNameBinding]
PROOF
<1>names. /\ SwiftSchedulerLocalNames.previousField = SchedulerRecordingLastWriteField
          /\ SwiftSchedulerLocalNames.previousBinder = SchedulerNameBinding
          /\ SwiftSchedulerLocalNames.allocator = SchedulerNameBinding
          /\ SwiftSchedulerLocalNames.previousReceiver = SwiftSchedulerLocalNames.repls
          /\ SwiftSchedulerLocalNames.rootReceiver = SwiftSchedulerLocalNames.patternTarget
          /\ SwiftSchedulerLocalNames.targetProperty = <<114,111,111,116>>
    BY ONLY ActualSchedulerLocalNameUses, SMT
       DEF SchedulerLexicalNames, SchedulerTokenRoot, SchedulerTokenLastWrite, SchedulerRecordingLastWriteField
<1>. DEFINE d == SchedulerSetDescriptor(block, old, Allocate)
            prior == old[SchedulerRecordingLastWriteField]
<1>keys. /\ SchedulerNameBinding # "target" /\ SchedulerNameBinding # "predecessor"
    BY ONLY IsaM("simp"), SMT DEF SchedulerNameBinding
<1>fields. /\ SchedulerNameBinding \in DOMAIN d
            /\ d.target = Head(block).target
            /\ d[SchedulerNameBinding] = Allocate(SchedulerNameBinding)
            /\ d.predecessor = IF prior = <<>> THEN <<>> ELSE prior[SchedulerNameBinding]
    BY ONLY <1>names, <1>keys, SMT DEF d, prior, SchedulerSetDescriptor
<1>. QED BY ONLY <1>fields DEF d, prior

THEOREM RootSetAndArbitrarySuffixUseTheActualSchedulerOperands ==
    ASSUME NEW block, NEW shapes, block \in Seq(shapes), block # <<>>,
           Head(block).kind = "rootSet",
           NEW pending, NEW old, SchedulerRootBindingsField \in DOMAIN old,
           NEW Allocate(_), NEW Substitute(_, _), NEW recur(_, _, _, _)
    PROVE LET row == Head(block)
              d == SchedulerSetDescriptor(block,old,Allocate)
              locals == SchedulerExecuteSetLocals(SchedulerSetEntry(block,pending,old),d,
                                                  Substitute,ActualSchedulerRecordingResult)
              binder == Allocate(SchedulerNameBinding)
              binding == [variable |-> binder]
              commits == Append(SchedulerKeepPending(pending,row.target),
                                [target |-> row.target,value |-> binding])
              bindings == SchedulerWriteLocal(old[SchedulerRootBindingsField],row.target,binding)
              next == SchedulerWriteLocal(SchedulerWriteLocal(old,SchedulerRootBindingsField,bindings),
                                         SchedulerRecordingLastWriteField,d)
          IN SchedulerSetReturn(locals,recur) =
             <<[kind |-> "letBinding", variable |-> binder,
                value |-> Substitute(old[SchedulerRootBindingsField],row.rhs),
                body |-> recur(SchedulerNameSchedule,Tail(block),commits,next)]>>
    BY ONLY (block \in Seq(shapes)), (block # <<>>), (SchedulerRootBindingsField \in DOMAIN old),
       ActualSetDescriptorUsesTheAuthoredTargetAndThePreviousBinding,
       ActualSchedulerRootHeadSuppliesTheContinuation, SMT
====

