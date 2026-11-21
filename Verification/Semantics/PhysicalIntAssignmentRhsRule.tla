---- MODULE PhysicalIntAssignmentRhsRule ----
EXTENDS OrderedIntAssignmentListRule, ScalarCopyOutputBinding

PhysicalAssignmentOperandsMatch(row, physical) ==
    LET expected == AssignmentRhsPlan(row)
    IN /\ physical.count = expected.count
       /\ \A node \in 1..expected.count :
              /\ physical.kinds[node] = expected.kinds[node]
              /\ (expected.kinds[node] = "literal" =>
                      physical.literals[node] = expected.literals[node])
              /\ (expected.kinds[node] = "add" =>
                      /\ physical.left[node] = expected.left[node]
                      /\ physical.right[node] = expected.right[node])

PhysicalAssignmentReadsMatchRoutes(rows, index, physical) ==
    LET expected == AssignmentRhsPlan(rows[index])
        routes == DirectCopyRoutes(Keys, rows)[index - 1]
    IN /\ PhysicalAssignmentOperandsMatch(rows[index], physical)
       /\ \A node \in 1..expected.count : expected.kinds[node] = "read" =>
              /\ expected.reads[node] \in Keys
              /\ physical.reads[node] = routes[expected.reads[node]]

PhysicalAssignmentReadsNameWriters(rows, index, physical) ==
    LET expected == AssignmentRhsPlan(rows[index])
    IN /\ PhysicalAssignmentOperandsMatch(rows[index], physical)
       /\ \A node \in 1..expected.count : expected.kinds[node] = "read" =>
              /\ expected.reads[node] \in Keys
              /\ CopyReceiptNamesWriter(rows, index - 1, expected.reads[node], physical.reads[node])

THEOREM NamedAssignmentReadRouteIsTheScheduledRoute ==
    ASSUME NEW rows, Len(rows) \in Nat, NEW prefix \in 0..Len(rows), NEW key \in Keys, NEW reference,
           CopyReceiptNamesWriter(rows, prefix, key, reference)
    PROVE reference = DirectCopyRoutes(Keys, rows)[prefix][key]
    PROOF
    <1>exists. \E writer \in 0..prefix : LastDirectCopy(rows, prefix, key, writer)
        BY ONLY (Len(rows) \in Nat), (prefix \in 0..Len(rows)), EveryFiniteCopyPrefixHasALastWriter, SMT
    <1>chosen. LastDirectCopy(rows, prefix, key, DirectCopyWriter(rows, prefix, key))
        BY ONLY <1>exists, SMT DEF DirectCopyWriter
    <1>named. LastDirectCopy(rows, prefix, key, CopyReceiptOrdinal(reference))
        BY ONLY CopyReceiptNamesWriter(rows, prefix, key, reference) DEF CopyReceiptNamesWriter
    <1>same. CopyReceiptOrdinal(reference) = DirectCopyWriter(rows, prefix, key)
        BY ONLY <1>chosen, <1>named, (Len(rows) \in Nat), (prefix \in 0..Len(rows)),
            TwoLastDirectCopiesHaveTheSamePosition, SMT
    <1>. QED BY ONLY <1>same, CopyReceiptNamesWriter(rows, prefix, key, reference),
        (prefix \in 0..Len(rows)), (key \in Keys), SMT DEF CopyReceiptNamesWriter, DirectCopyRoutes

THEOREM NamedAssignmentOperandsMatchTheirRoutes ==
    ASSUME NEW rows, Len(rows) \in Nat, NEW index \in 1..Len(rows), NEW physical,
           PhysicalAssignmentReadsNameWriters(rows, index, physical)
    PROVE PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
    PROOF
    <1>bounds. index - 1 \in 0..Len(rows)
        BY ONLY (Len(rows) \in Nat), (index \in 1..Len(rows)), SMT
    <1>. QED BY ONLY <1>bounds, (Len(rows) \in Nat), PhysicalAssignmentReadsNameWriters(rows, index, physical),
        NamedAssignmentReadRouteIsTheScheduledRoute, SMT
        DEF PhysicalAssignmentReadsNameWriters, PhysicalAssignmentReadsMatchRoutes

PhysicalRhsReadIndices(plan) == [node \in 1..plan.count |-> node]

PhysicalRhsBindings(plan, before, completed) ==
    [node \in 1..plan.count |-> IF plan.kinds[node] = "read"
        THEN CopyReferenceValue(before, completed, plan.reads[node]) ELSE 0]

PhysicalAssignmentRhsHistory(plan, before, completed, history) ==
    GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals, PhysicalRhsReadIndices(plan),
        plan.left, plan.right, PhysicalRhsBindings(plan, before, completed), history)

PhysicalAssignmentRhs(plan, before, completed) ==
    LET visited == CHOOSE history : PhysicalAssignmentRhsHistory(plan, before, completed, history)
    IN visited[plan.count]

THEOREM AssignmentPrefixMaterializationIsTyped ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW before \in AssignmentBindings,
           NEW completed \in Seq(AssignmentIntValues), Len(completed) <= Len(rows)
    PROVE CompletedAssignmentBindings(before, rows, completed) \in AssignmentBindings
    PROOF
    <1>. DEFINE count == Len(completed)
                routes == DirectCopyRoutes(Keys, rows)[count]
    <1>bounds. /\ Len(rows) \in Nat /\ count \in 0..Len(rows)
        BY SupportedAssignmentList(rows), LenProperties, SMT
            DEF SupportedAssignmentList, count
    <1>values. \A key \in Keys :
        CopyReferenceValue(before, completed, routes[key]) \in AssignmentIntValues
        <2>. TAKE key \in Keys
        <2>reference. routes[key] = DirectCopyReference(key, DirectCopyWriter(rows, count, key))
            BY ONLY <1>bounds, (key \in Keys), SMT DEF routes, DirectCopyRoutes
        <2>earlier. routes[key][1] = "capture" => routes[key][2] \in 1..count
            BY ONLY <1>bounds, (key \in Keys), ReachedAssignmentRoutesUseOnlyEarlierCaptures, SMT DEF routes
        <2>slots. /\ before[key] \in AssignmentIntValues
                  /\ \A slot \in 1..count : completed[slot] \in AssignmentIntValues
            BY ONLY (before \in AssignmentBindings), (key \in Keys),
                (completed \in Seq(AssignmentIntValues)), ElementOfSeq, SMT DEF AssignmentBindings, count
        <2>. QED BY ONLY <2>reference, <2>earlier, <2>slots, SMT
            DEF CopyReferenceValue, DirectCopyReference
    <1>. QED BY ONLY <1>values, SMT
        DEF CompletedAssignmentBindings, routes, count, CopyMaterializedState, AssignmentBindings

THEOREM PhysicalAssignmentHistoryMatchesTheCertifiedRhs ==
    ASSUME NEW rows, NEW index \in 1..Len(rows), NEW physical, NEW before,
           NEW completed, Len(completed) = index - 1, NEW history,
           AssignmentRhsCertificate(rows[index]),
           PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
    PROVE PhysicalAssignmentRhsHistory(physical, before, completed, history) <=>
        GeneratedAssignmentRhsHistory(rows[index], CompletedAssignmentBindings(before, rows, completed), history)
    PROOF
    <1>. DEFINE expected == AssignmentRhsPlan(rows[index])
                routes == DirectCopyRoutes(Keys, rows)[index - 1]
                bindings == CompletedAssignmentBindings(before, rows, completed)
    <1>length. physical.count = expected.count
        BY ONLY PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
            DEF PhysicalAssignmentReadsMatchRoutes, PhysicalAssignmentOperandsMatch, expected
    <1>nodes. \A node \in 1..expected.count :
          GeneratedNode(node, physical.kinds, physical.literals, PhysicalRhsReadIndices(physical),
              physical.left, physical.right, PhysicalRhsBindings(physical, before, completed), history)
        = GeneratedNode(node, expected.kinds, expected.literals, expected.reads,
              expected.left, expected.right, bindings, history)
        <2>. TAKE node \in 1..expected.count
        <2>operands. /\ physical.kinds[node] = expected.kinds[node]
                     /\ (expected.kinds[node] = "literal" => physical.literals[node] = expected.literals[node])
                     /\ (expected.kinds[node] = "read" =>
                           /\ expected.reads[node] \in Keys
                           /\ physical.reads[node] = routes[expected.reads[node]])
                     /\ (expected.kinds[node] = "add" =>
                           physical.left[node] = expected.left[node] /\ physical.right[node] = expected.right[node])
            BY ONLY (node \in 1..expected.count), PhysicalAssignmentReadsMatchRoutes(rows, index, physical), SMT
                DEF PhysicalAssignmentReadsMatchRoutes, PhysicalAssignmentOperandsMatch, expected, routes
        <2>kinds. expected.kinds[node] \in {"literal", "read", "add"}
            BY ONLY (node \in 1..expected.count), AssignmentRhsCertificate(rows[index]), SMT
                DEF AssignmentRhsCertificate, LiteralReadAddCertificate, AssignmentRhsPlan, ExtractedNodePlan,
                    NodeEmissionArrays, AllNodePayloadsMatchSource, NodePayloadMatchesSource, expected
        <2>read. expected.kinds[node] = "read" =>
            PhysicalRhsBindings(physical, before, completed)[node] = bindings[expected.reads[node]]
            BY ONLY <1>length, <2>operands, (node \in 1..expected.count), (Len(completed) = index - 1), SMT
                DEF PhysicalRhsBindings, bindings, CompletedAssignmentBindings, CopyMaterializedState, routes
        <2>. QED BY ONLY <1>length, <2>operands, <2>kinds, <2>read, (node \in 1..expected.count), SMT
            DEF GeneratedNode, PhysicalRhsReadIndices
    <1>. QED BY ONLY <1>length, <1>nodes, SMT
        DEF PhysicalAssignmentRhsHistory, GeneratedAssignmentRhsHistory, GeneratedExpressionHistory, expected, bindings

THEOREM PhysicalAssignmentRhsHasCertifiedOutcome ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW index \in 1..Len(rows),
           NEW physical, PhysicalAssignmentReadsMatchRoutes(rows, index, physical),
           NEW before \in AssignmentBindings, NEW completed \in Seq(AssignmentIntValues),
           Len(completed) = index - 1
    PROVE LET bindings == CompletedAssignmentBindings(before, rows, completed)
              reached == PhysicalAssignmentRhs(physical, before, completed)
          IN /\ reached = SourceAssignmentRHS(rows[index], bindings)
             /\ reached = GeneratedAssignmentRHS(rows[index], bindings)
             /\ \A history : PhysicalAssignmentRhsHistory(physical, before, completed, history) =>
                      history[physical.count] = reached
    PROOF
    <1>. DEFINE bindings == CompletedAssignmentBindings(before, rows, completed)
                row == rows[index]
                logical == AssignmentRhsPlan(row)
                reached == PhysicalAssignmentRhs(physical, before, completed)
    <1>shape. /\ AssignmentRhsCertificate(row)
              /\ Len(completed) <= Len(rows)
              /\ physical.count = logical.count
        BY SupportedAssignmentList(rows), (index \in 1..Len(rows)), SMT
            DEF SupportedAssignmentList, row, PhysicalAssignmentReadsMatchRoutes, PhysicalAssignmentOperandsMatch, logical
    <1>type. bindings \in AssignmentBindings
        BY ONLY <1>shape, SupportedAssignmentList(rows), (before \in AssignmentBindings),
            (completed \in Seq(AssignmentIntValues)), AssignmentPrefixMaterializationIsTyped, SMT DEF bindings
    <1>linked. \A history : PhysicalAssignmentRhsHistory(physical, before, completed, history) <=>
        GeneratedAssignmentRhsHistory(row, bindings, history)
        BY ONLY <1>shape, (index \in 1..Len(rows)), (Len(completed) = index - 1),
            PhysicalAssignmentReadsMatchRoutes(rows, index, physical), PhysicalAssignmentHistoryMatchesTheCertifiedRhs,
            SMT DEF row, bindings
    <1>exists. \E history : GeneratedAssignmentRhsHistory(row, bindings, history)
        BY ONLY <1>shape, <1>type, LiteralReadAddCertificateSuppliesExpressionParent, SMT
            DEF AssignmentRhsCertificate, AssignmentBindings, AssignmentIntValues,
                AssignmentRhsPlan, GeneratedAssignmentRhsHistory
    <1>selected. PhysicalAssignmentRhsHistory(physical, before, completed,
        CHOOSE history : PhysicalAssignmentRhsHistory(physical, before, completed, history))
        BY ONLY <1>linked, <1>exists, SMT
    <1>match. /\ \A history : PhysicalAssignmentRhsHistory(physical, before, completed, history) =>
                        history[physical.count] = SourceAssignmentRHS(row, bindings)
               /\ SourceAssignmentRHS(row, bindings) = GeneratedAssignmentRHS(row, bindings)
        BY ONLY <1>shape, <1>type, <1>linked, CertifiedAssignmentRhsConstructsBothMeanings, SMT DEF logical
    <1>. QED BY ONLY <1>selected, <1>match, SMT DEF reached, PhysicalAssignmentRhs, row, bindings

====
