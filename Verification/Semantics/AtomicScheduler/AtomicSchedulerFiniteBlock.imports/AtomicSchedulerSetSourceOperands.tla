---- MODULE AtomicSchedulerSetSourceOperands ----
EXTENDS AtomicSchedulerAuthoredPrefix

THEOREM SchedulerLexicalSlotsAreTheDeclaredNames ==
    /\ SchedulerLexicalNames.values = SchedulerNameValues
    /\ SchedulerLexicalNames.assignments = SchedulerNameAssignments
    /\ SchedulerLexicalNames.repls = SchedulerRootReplacements
    /\ SchedulerLexicalNames.patternTarget = <<116, 97, 114, 103, 101, 116>>
    /\ SchedulerLexicalNames.patternValue = SchedulerRootPatternValue
PROOF BY ONLY SMTT(20) DEF SchedulerLexicalNames, SchedulerTokenTarget

THEOREM ActualRootSetEntryHasTheAuthoredOperands ==
    ASSUME NEW block, block # <<>>, NEW pending, NEW old
    PROVE SchedulerSetEntryBindings(block, pending, old, Head(block).target, Head(block).rhs,
                                      SchedulerSetEntry(block, pending, old))
PROOF
<1>. DEFINE row == Head(block)
            env == SchedulerSetEntry(block,pending,old)
<1>names. /\ SwiftSchedulerLocalNames.values = SchedulerNameValues
          /\ SwiftSchedulerLocalNames.assignments = SchedulerNameAssignments
          /\ SwiftSchedulerLocalNames.repls = SchedulerRootReplacements
          /\ SwiftSchedulerLocalNames.patternTarget = <<116, 97, 114, 103, 101, 116>>
          /\ SwiftSchedulerLocalNames.patternValue = SchedulerRootPatternValue
    BY ONLY SchedulerLexicalSlotsAreTheDeclaredNames, ActualSchedulerLocalNameUses, SMT
<1>entry. SchedulerSetEntryBindings(block, pending, old, row.target, row.rhs, env)
    BY ONLY <1>names, SMT DEF SchedulerSetEntryBindings, env, row, SchedulerSetEntry, SchedulerNameValues,
        SchedulerNameAssignments, SchedulerRootReplacements, SchedulerRootPatternValue
<1>. QED BY ONLY <1>entry DEF row, env

THEOREM TheActualDescriptorUsesTheSourceMemberNames ==
    /\ SwiftSchedulerLocalNames.previousField = SchedulerRecordingLastWriteField
    /\ SwiftSchedulerLocalNames.previousBinder = SchedulerNameBinding
    /\ SwiftSchedulerLocalNames.allocator = SchedulerNameBinding
    /\ SwiftSchedulerLocalNames.previousReceiver = SwiftSchedulerLocalNames.repls
    /\ SwiftSchedulerLocalNames.rootReceiver = SwiftSchedulerLocalNames.patternTarget
    /\ SwiftSchedulerLocalNames.targetProperty = <<114,111,111,116>>
PROOF
BY ONLY ActualSchedulerLocalNameUses, SMT
       DEF SchedulerLexicalNames, SchedulerTokenRoot, SchedulerTokenLastWrite, SchedulerRecordingLastWriteField


THEOREM TheSourceRhsCallUsesTheDeclaredNames ==
    LET n == SwiftSchedulerLocalNames
    IN /\ n.assignArg = n.patternValue
       /\ n.rootParam = n.rootReturn
       /\ n.helperParam = n.helperValue
       /\ n.called = n.helper
       /\ n.assignRecv = n.patternTarget
       /\ n.patternValue = SchedulerRootPatternValue
       /\ n.mapRecv = SchedulerRootReplacements
       /\ n.mapField = SchedulerRootBindingsField
PROOF BY ONLY SourceSetBindingsResolveTheirUses, PTL DEF SchedulerOperandEdges

THEOREM SourceRecordingUsesTheDeclaredNames ==
    LET n == SwiftSchedulerLocalNames
    IN /\ n.nextRecv = SchedulerRootReplacements
       /\ n.nextArg = n.descriptor
PROOF BY ONLY SourceSetBindingsResolveTheirUses, PTL DEF SchedulerOperandEdges

THEOREM SourcePendingWritesUseTheDeclaredNames ==
    LET n == SwiftSchedulerLocalNames
    IN /\ n.pendingInput = SchedulerNameAssignments
       /\ n.keepTarget = n.descriptor
       /\ n.appendTarget = n.descriptor
       /\ n.appendBinder = n.descriptor
PROOF BY ONLY SourceSetBindingsResolveTheirUses, PTL DEF SchedulerOperandEdges

THEOREM SourceSetLocalResultsUseDistinctDeclaredSlots ==
    LET n == SwiftSchedulerLocalNames
    IN /\ n.tailInput = SchedulerNameValues
       /\ n.descriptor = SchedulerNameUpdate
       /\ n.suffix = SchedulerNameSuffix
       /\ n.pending = SchedulerNamePending
       /\ n.next = SchedulerNameNext
       /\ n.result = SchedulerNameUpdated
       /\ n.suffix # n.descriptor
       /\ n.result \notin {n.descriptor, n.suffix}
       /\ n.next \notin {n.descriptor, n.suffix, n.result}
       /\ n.pending \notin {n.descriptor, n.suffix, n.result, n.next}
PROOF BY ONLY SourceSetBindingsResolveTheirUses, PTL DEF SchedulerOperandEdges

====
