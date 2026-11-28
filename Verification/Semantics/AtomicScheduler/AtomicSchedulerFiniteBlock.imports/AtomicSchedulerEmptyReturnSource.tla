---- MODULE AtomicSchedulerEmptyReturnSource ----
EXTENDS AtomicSchedulerSetSourceOperands

THEOREM ActualEmptySchedulerPublishesPendingWrites ==
    ASSUME NEW input, input[SchedulerNameValues] = <<>>
    PROVE SchedulerEmptyReturn(input) =
        IF input[SchedulerNameAssignments] = <<>> THEN <<>>
        ELSE <<[kind |-> "parallel", assignments |-> input[SchedulerNameAssignments]]>>
PROOF
<1>names. /\ SchedulerReturnNames.finalName = SchedulerNameFinalWrites
          /\ SchedulerReturnNames.assignmentsTest = SchedulerNameAssignments
          /\ SchedulerReturnNames.assignmentsArgument = SchedulerNameAssignments
          /\ SchedulerReturnNames.guardInput = SchedulerNameValues
          /\ SchedulerReturnNames.finalReference = SchedulerNameFinalWrites
    BY ONLY ActualSchedulerReturnOperands, PTL
<1>. QED BY ONLY <1>names, (input[SchedulerNameValues] = <<>>), SMT DEF SchedulerEmptyReturn

SchedulerSetDescriptorForBinding(values, old, name) ==
    SchedulerSetDescriptor(values, old, LAMBDA unused : name)

THEOREM ActualRootAssignmentDescriptorHasItsBinding ==
    \A values, old, name :
        SchedulerNameBinding \in DOMAIN SchedulerSetDescriptorForBinding(values, old, name)
PROOF
<1>. TAKE values, old, name
<1>. QED BY ONLY TheActualDescriptorUsesTheSourceMemberNames, SMT
    DEF SchedulerSetDescriptorForBinding, SchedulerSetDescriptor
====
