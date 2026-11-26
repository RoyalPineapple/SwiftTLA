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

\* The source row fields observed by the physical inventory. The authored
\* certificates may use different names for their unused occurrence metadata.
AssignmentRhsRowsArePrefix(rows, prefixRows) ==
    /\ Len(rows) \in Nat
    /\ Len(prefixRows) \in 0..Len(rows)
    /\ DOMAIN rows = 1..Len(rows)
    /\ DOMAIN prefixRows = 1..Len(prefixRows)
    /\ \A index \in DOMAIN prefixRows :
           /\ prefixRows[index].target = rows[index].target
           /\ AssignmentRhsPlan(prefixRows[index]) = AssignmentRhsPlan(rows[index])

THEOREM PhysicalAssignmentReadsRestrictToPrefix ==
    ASSUME NEW rows, NEW prefixRows, AssignmentRhsRowsArePrefix(rows, prefixRows),
           NEW plans, NEW prefixPlans,
           \A index \in DOMAIN rows : PhysicalAssignmentReadsMatchRoutes(rows, index, plans[index]),
           \A index \in DOMAIN prefixRows : prefixPlans[index] = plans[index]
    PROVE \A index \in DOMAIN prefixRows :
              PhysicalAssignmentReadsMatchRoutes(prefixRows, index, prefixPlans[index])
PROOF
<1>. DEFINE count == Len(prefixRows)
            full == DirectCopyRoutes(Keys, rows)
            maps == [slot \in 1..(count + 1) |-> full[slot - 1]]
<1>shape. /\ Len(rows) \in Nat /\ count \in Nat /\ count \in 0..Len(rows)
          /\ DOMAIN rows = 1..Len(rows) /\ DOMAIN prefixRows = 1..count
          /\ DOMAIN prefixRows \subseteq DOMAIN rows
    BY ONLY AssignmentRhsRowsArePrefix(rows, prefixRows), SMT DEF count, AssignmentRhsRowsArePrefix
<1>aligned. /\ maps[1] = CopyEntryRoutes(Keys)
            /\ \A slot \in 1..count :
                 maps[slot + 1] = CopyReplace(Keys, maps[slot], prefixRows[slot].target, <<"capture", slot>>)
    <2>full. /\ full[0] = CopyEntryRoutes(Keys)
             /\ \A slot \in 1..Len(rows) :
                    full[slot] = CopyReplace(Keys, full[slot - 1], rows[slot].target, <<"capture", slot>>)
        BY ONLY <1>shape, DirectCopyRoutesFollowEveryCapture DEF full
    <2>targets. \A slot \in 1..count : prefixRows[slot].target = rows[slot].target
        BY ONLY <1>shape, AssignmentRhsRowsArePrefix(rows, prefixRows) DEF AssignmentRhsRowsArePrefix
    <2>. QED BY ONLY <1>shape, <2>full, <2>targets, SMT DEF maps
<1>routes. \A slot \in DOMAIN prefixRows :
    DirectCopyRoutes(Keys, prefixRows)[slot - 1] = maps[slot]
    BY ONLY <1>shape, <1>aligned, DirectCopyRoutesAgreeWithRecordedPrefixes, SMT DEF count
<1>reads. \A index \in DOMAIN prefixRows :
    PhysicalAssignmentReadsMatchRoutes(prefixRows, index, prefixPlans[index])
    <2>. TAKE index \in DOMAIN prefixRows
    <2>physical. PhysicalAssignmentReadsMatchRoutes(rows, index, plans[index])
        BY ONLY <1>shape, (index \in DOMAIN prefixRows),
            (\A slot \in DOMAIN rows : PhysicalAssignmentReadsMatchRoutes(rows, slot, plans[slot])), SMT
    <2>row. /\ AssignmentRhsPlan(prefixRows[index]) = AssignmentRhsPlan(rows[index])
             /\ prefixPlans[index] = plans[index]
        BY ONLY (index \in DOMAIN prefixRows), AssignmentRhsRowsArePrefix(rows, prefixRows),
            (\A slot \in DOMAIN prefixRows : prefixPlans[slot] = plans[slot]), SMT DEF AssignmentRhsRowsArePrefix
    <2>route. DirectCopyRoutes(Keys, prefixRows)[index - 1] = full[index - 1]
        BY ONLY <1>shape, <1>routes, (index \in DOMAIN prefixRows), SMT DEF maps
    <2>. QED BY ONLY <2>physical, <2>row, <2>route, SMT
        DEF full, PhysicalAssignmentReadsMatchRoutes, PhysicalAssignmentOperandsMatch
<1>. QED BY ONLY <1>reads

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

LOCAL THEOREM ScheduledReadLookupsSupplyThePhysicalAssignmentRoutes ==
    ASSUME NEW rows, NEW index \in DOMAIN rows, AssignmentRhsCertificate(rows[index]),
           NEW incoming, incoming = DirectCopyRoutes(Keys, rows)[index - 1],
           NEW scheduled, NEW physical, PhysicalAssignmentOperandsMatch(rows[index], physical),
           \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
               scheduled[origin] = incoming[rows[index].view.reads[origin]],
           \A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
               physical.reads[node] = scheduled[rows[index].emitted.origins[node]]
    PROVE PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
PROOF
<1>. DEFINE row == rows[index]
            expected == AssignmentRhsPlan(row)
<1>certificate. /\ row.emitted.origins \in [1..row.emitted.count -> DOMAIN row.view.kinds]
                 /\ AllNodePayloadsMatchSource(row.view, row.emitted)
                 /\ TypedVisitedSourceInputs(row.view, row.emitted)
    BY ONLY AssignmentRhsCertificate(rows[index])
        DEF row, AssignmentRhsCertificate, LiteralReadAddCertificate
<1>read. \A node \in 1..expected.count : expected.kinds[node] = "read" =>
    /\ expected.reads[node] \in Keys
    /\ physical.reads[node] = incoming[expected.reads[node]]
    <2>. TAKE node \in 1..expected.count
    <2>. SUFFICES ASSUME expected.kinds[node] = "read"
                  PROVE /\ expected.reads[node] \in Keys
                        /\ physical.reads[node] = incoming[expected.reads[node]]
        OBVIOUS
    <2>. DEFINE origin == row.emitted.origins[node]
    <2>emission. /\ node \in 1..row.emitted.count
                 /\ row.emitted.nodes[node].kind = "read"
                 /\ expected.reads[node] = row.emitted.nodes[node].payload
        BY ONLY (node \in 1..expected.count), (expected.kinds[node] = "read"), SMT
            DEF expected, AssignmentRhsPlan, ExtractedNodePlan
    <2>source. /\ origin \in DOMAIN row.view.kinds
               /\ row.view.kinds[origin] = "read"
               /\ expected.reads[node] = row.view.reads[origin]
               /\ expected.reads[node] \in Keys
        BY ONLY <1>certificate, <2>emission, SMT
            DEF origin, AllNodePayloadsMatchSource, NodePayloadMatchesSource, TypedVisitedSourceInputs
    <2>scheduled. scheduled[origin] = incoming[expected.reads[node]]
        BY ONLY <2>source,
            (\A occurrence \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[occurrence] = "read" =>
                scheduled[occurrence] = incoming[rows[index].view.reads[occurrence]]), SMT DEF row
    <2>physical. physical.reads[node] = scheduled[origin]
        BY ONLY <2>emission,
            (\A cell \in 1..rows[index].emitted.count : rows[index].emitted.nodes[cell].kind = "read" =>
                physical.reads[cell] = scheduled[rows[index].emitted.origins[cell]]), SMT DEF row, origin
    <2>. QED BY ONLY <2>source, <2>scheduled, <2>physical, SMT
<1>. QED BY ONLY PhysicalAssignmentOperandsMatch(rows[index], physical), <1>read,
    (incoming = DirectCopyRoutes(Keys, rows)[index - 1]), SMT DEF row, expected, PhysicalAssignmentReadsMatchRoutes

\* Reviewed root .set: substitute through the incoming map, then install
\* the new LET name for the target. CopyReplace records that same target
\* replacement in slots. Project its capture slots through the returned LET
\* column to recover Swift's pre-write dictionary of variable names.
ScheduledRootReplacementNames(incoming, definitionNames) ==
    [key \in {k \in Keys : incoming[k][1] = "capture"} |->
        definitionNames[incoming[key][2]]]

\* Binder ordinals are global. Capture positions are local to the selected path.
AssignmentBinderSlot(binders, id) ==
    CHOOSE slot \in DOMAIN binders : binders[slot] = id

THEOREM UniqueAssignmentBinderResolvesToItsSlot ==
    ASSUME NEW binders, NEW slot \in DOMAIN binders,
           \A p, q \in DOMAIN binders : binders[p] = binders[q] => p = q
    PROVE AssignmentBinderSlot(binders, binders[slot]) = slot
PROOF
<1>exists. \E p \in DOMAIN binders : binders[p] = binders[slot]
    BY ONLY (slot \in DOMAIN binders), SMT
<1>found. LET p == AssignmentBinderSlot(binders, binders[slot])
          IN p \in DOMAIN binders /\ binders[p] = binders[slot]
    BY ONLY <1>exists, SMT DEF AssignmentBinderSlot
<1>. QED BY ONLY <1>found, (slot \in DOMAIN binders),
    (\A p, q \in DOMAIN binders : binders[p] = binders[q] => p = q), SMT

THEOREM ScheduledReadOccurrencesSupplyThePhysicalAssignmentRoutes ==
    ASSUME NEW rows, Len(rows) \in Nat, NEW index \in 1..Len(rows), index \in DOMAIN rows,
           AssignmentRhsCertificate(rows[index]),
           CompilerOccurrenceTree(rows[index].view, rows[index].emitted.count),
           NEW incoming, incoming = DirectCopyRoutes(Keys, rows)[index - 1],
           NEW definitionNames, NEW definitionBinders, NEW loweredNames, NEW loweredIDs, NEW scheduled,
           \A a, b \in 1..(index - 1) : definitionNames[a] = definitionNames[b] => a = b,
           \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
               LET key == rows[index].view.reads[origin]
                   name == loweredNames[origin]
                   id == loweredIDs[origin]
                   slot == AssignmentBinderSlot(definitionBinders, id[2])
               IN /\ \A p \in 1..(index - 1) : definitionNames[p] # key
                  /\ name = StateExprReplaceProjection(rows[index].view,
                                ScheduledRootReplacementNames(incoming, definitionNames))[origin].payload
                  /\ (\/ /\ id[1] = "state" /\ name = key /\ scheduled[origin] = <<"state", key>>
                      \/ /\ id[1] = "binding" /\ slot \in 1..(index - 1)
                         /\ id[2] = definitionBinders[slot] /\ name = definitionNames[slot]
                         /\ scheduled[origin] = <<"capture", slot>>),
           NEW physical, PhysicalAssignmentOperandsMatch(rows[index], physical),
           \A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
               physical.reads[node] = scheduled[rows[index].emitted.origins[node]]
    PROVE PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
PROOF
<1>. DEFINE row == rows[index]
            view == row.view
            prefix == index - 1
            replacements == ScheduledRootReplacementNames(incoming, definitionNames)
<1>range. /\ prefix \in 0..Len(rows) /\ prefix \in Nat
    BY ONLY (Len(rows) \in Nat), (index \in 1..Len(rows)), SMT DEF prefix
<1>names. \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" =>
    StateExprReplaceProjection(view, replacements)[origin].payload =
        StateExprReplaceReadName(replacements, view.reads[origin])
    BY ONLY CompilerOccurrenceTree(rows[index].view, rows[index].emitted.count),
        StateExprReplacementHasAUniqueProjection, SMT DEF row, view
<1>typed. \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" => view.reads[origin] \in Keys
    BY ONLY AssignmentRhsCertificate(rows[index]), SMT
        DEF row, view, AssignmentRhsCertificate, LiteralReadAddCertificate, TypedVisitedSourceInputs
<1>lookup. \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" =>
    scheduled[origin] = incoming[view.reads[origin]]
    <2>. TAKE origin \in DOMAIN view.kinds
    <2>. SUFFICES ASSUME view.kinds[origin] = "read"
                  PROVE scheduled[origin] = incoming[view.reads[origin]]
        OBVIOUS
    <2>. DEFINE key == view.reads[origin]
                name == loweredNames[origin]
                id == loweredIDs[origin]
                slot == AssignmentBinderSlot(definitionBinders, id[2])
                writer == DirectCopyWriter(rows, prefix, key)
    <2>key. key \in Keys
        BY ONLY (origin \in DOMAIN view.kinds), (view.kinds[origin] = "read"), <1>typed, SMT DEF key
    <2>exists. \E p \in 0..prefix : LastDirectCopy(rows, prefix, key, p)
        BY ONLY <1>range, (Len(rows) \in Nat), EveryFiniteCopyPrefixHasALastWriter, SMT
    <2>writer. writer \in 0..prefix
        BY ONLY <2>exists, SMT DEF writer, DirectCopyWriter, LastDirectCopy
    <2>route. incoming[key] = DirectCopyReference(key, writer)
        BY ONLY <1>range, <2>key, (incoming = DirectCopyRoutes(Keys, rows)[index - 1]), SMT
            DEF DirectCopyRoutes, writer, prefix
    <2>actual. /\ \A p \in 1..prefix : definitionNames[p] # key
               /\ name = StateExprReplaceReadName(replacements, key)
               /\ (\/ /\ id[1] = "state" /\ name = key /\ scheduled[origin] = <<"state", key>>
                   \/ /\ id[1] = "binding" /\ slot \in 1..prefix
                      /\ id[2] = definitionBinders[slot] /\ name = definitionNames[slot]
                      /\ scheduled[origin] = <<"capture", slot>>)
        BY <1>names, (origin \in DOMAIN view.kinds), (view.kinds[origin] = "read"), SMT
            DEF row, view, prefix, key, name, id, slot, replacements
    <2>entry. CASE writer = 0
        <3>name. name = key
            BY ONLY <2>entry, <2>route, <2>actual, SMT
                DEF DirectCopyReference, StateExprReplaceReadName, replacements, ScheduledRootReplacementNames
        <3>. QED BY ONLY <2>entry, <2>route, <2>actual, <3>name, SMT DEF DirectCopyReference
    <2>capture. CASE writer # 0
        <3>slot. writer \in 1..prefix
            BY ONLY <2>capture, <2>writer, SMT
        <3>name. name = definitionNames[writer]
            BY ONLY <2>capture, <2>key, <2>route, <2>actual, SMT
                DEF DirectCopyReference, StateExprReplaceReadName, replacements, ScheduledRootReplacementNames
        <3>identity. /\ slot \in 1..prefix /\ definitionNames[slot] = definitionNames[writer]
                     /\ scheduled[origin] = <<"capture", slot>>
            BY ONLY <2>actual, <3>slot, <3>name, SMT
        <3>. QED BY ONLY <2>capture, <2>route, <3>slot, <3>identity,
            (\A a, b \in 1..(index - 1) : definitionNames[a] = definitionNames[b] => a = b),
            SMT DEF prefix, DirectCopyReference
    <2>. QED BY ONLY <2>entry, <2>capture DEF key
<1>. QED BY ONLY <1>lookup, (index \in DOMAIN rows), AssignmentRhsCertificate(rows[index]),
    (incoming = DirectCopyRoutes(Keys, rows)[index - 1]), PhysicalAssignmentOperandsMatch(rows[index], physical),
    (\A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
        physical.reads[node] = scheduled[rows[index].emitted.origins[node]]),
    ScheduledReadLookupsSupplyThePhysicalAssignmentRoutes, SMT DEF row, view

\* The successful checkedAtomicBranchContinuations.advance compares the
\* decoded returned RHS to applyingWrites before installing this target.
\* The prefix maps represent the checker's authored dictionary with entry
\* reads represented explicitly. Acceptance supplies the comparison, not
\* a claim that all authored inputs are accepted by the checker.
ReturnedRootAssignmentReceiptFieldsInput(rows, index, maps, definitionNames, definitionBinders,
                                         loweredNames, loweredIDs, scheduled, physical) ==
    /\ Len(rows) \in Nat
    /\ index \in 1..Len(rows)
    /\ index \in DOMAIN rows
    /\ AssignmentRhsCertificate(rows[index])
    /\ CompilerOccurrenceTree(rows[index].view, rows[index].emitted.count)
    /\ maps[1] = CopyEntryRoutes(Keys)
    /\ \A position \in 1..(Len(rows) - 1) :
            maps[position + 1] =
                CopyReplace(Keys, maps[position], rows[position].target, <<"capture", position>>)
    /\ \A a, b \in 1..(index - 1) : definitionNames[a] = definitionNames[b] => a = b
    /\ \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
            scheduled[origin] = maps[index][rows[index].view.reads[origin]]
    /\ \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
            LET key == rows[index].view.reads[origin]
                name == loweredNames[origin]
                id == loweredIDs[origin]
                slot == AssignmentBinderSlot(definitionBinders, id[2])
            IN /\ \A p \in 1..(index - 1) : definitionNames[p] # key
               /\ (\/ /\ id[1] = "state" /\ name = key /\ scheduled[origin] = <<"state", key>>
                   \/ /\ id[1] = "binding" /\ slot \in 1..(index - 1)
                      /\ id[2] = definitionBinders[slot] /\ name = definitionNames[slot]
                      /\ scheduled[origin] = <<"capture", slot>>)
    /\ PhysicalAssignmentOperandsMatch(rows[index], physical)
    /\ \A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
            physical.reads[node] = scheduled[rows[index].emitted.origins[node]]

ReturnedRootAssignmentReceiptInput(receipt) ==
    ReturnedRootAssignmentReceiptFieldsInput(receipt.rows, receipt.index, receipt.maps, receipt.definitionNames,
        receipt.definitionBinders, receipt.loweredNames, receipt.loweredIDs, receipt.scheduled, receipt.physical)

ReturnedRootAssignmentReceiptOutput(receipt) ==
    LET rows == receipt.rows
        index == receipt.index
        maps == receipt.maps
        definitionNames == receipt.definitionNames
        definitionBinders == receipt.definitionBinders
        loweredNames == receipt.loweredNames
        loweredIDs == receipt.loweredIDs
        scheduled == receipt.scheduled
        physical == receipt.physical
    IN
        /\ maps[index] = DirectCopyRoutes(Keys, rows)[index - 1]
        /\ \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
               loweredNames[origin] = StateExprReplaceProjection(rows[index].view,
                   ScheduledRootReplacementNames(maps[index], definitionNames))[origin].payload
        /\ PhysicalAssignmentReadsMatchRoutes(rows, index, physical)

THEOREM ReturnedRootAssignmentReceiptRecordSuppliesScheduledReadRoutes ==
    \A boundReceipt : ReturnedRootAssignmentReceiptInput(boundReceipt) => ReturnedRootAssignmentReceiptOutput(boundReceipt)
PROOF
<1>. TAKE boundReceipt
<1>. SUFFICES ASSUME ReturnedRootAssignmentReceiptInput(boundReceipt)
              PROVE ReturnedRootAssignmentReceiptOutput(boundReceipt)
    OBVIOUS
<1>. DEFINE rows == boundReceipt.rows
            index == boundReceipt.index
            maps == boundReceipt.maps
            definitionNames == boundReceipt.definitionNames
            definitionBinders == boundReceipt.definitionBinders
            loweredNames == boundReceipt.loweredNames
            loweredIDs == boundReceipt.loweredIDs
            scheduled == boundReceipt.scheduled
            physical == boundReceipt.physical
<1>. SUFFICES ASSUME Len(rows) \in Nat, index \in 1..Len(rows), index \in DOMAIN rows,
                  AssignmentRhsCertificate(rows[index]),
                  CompilerOccurrenceTree(rows[index].view, rows[index].emitted.count),
                  maps[1] = CopyEntryRoutes(Keys),
                  \A position \in 1..(Len(rows) - 1) :
                      maps[position + 1] =
                          CopyReplace(Keys, maps[position], rows[position].target, <<"capture", position>>),
                  \A a, b \in 1..(index - 1) : definitionNames[a] = definitionNames[b] => a = b,
                  \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
                      scheduled[origin] = maps[index][rows[index].view.reads[origin]],
                  \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
                      LET key == rows[index].view.reads[origin]
                          name == loweredNames[origin]
                          id == loweredIDs[origin]
                          slot == AssignmentBinderSlot(definitionBinders, id[2])
                      IN /\ \A p \in 1..(index - 1) : definitionNames[p] # key
                         /\ (\/ /\ id[1] = "state" /\ name = key /\ scheduled[origin] = <<"state", key>>
                             \/ /\ id[1] = "binding" /\ slot \in 1..(index - 1)
                                /\ id[2] = definitionBinders[slot] /\ name = definitionNames[slot]
                                /\ scheduled[origin] = <<"capture", slot>>),
                  PhysicalAssignmentOperandsMatch(rows[index], physical),
                  \A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
                      physical.reads[node] = scheduled[rows[index].emitted.origins[node]]
              PROVE /\ maps[index] = DirectCopyRoutes(Keys, rows)[index - 1]
                    /\ \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
                           loweredNames[origin] = StateExprReplaceProjection(rows[index].view,
                               ScheduledRootReplacementNames(maps[index], definitionNames))[origin].payload
                    /\ PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
    BY (ReturnedRootAssignmentReceiptInput(boundReceipt)), PTL
        DEF ReturnedRootAssignmentReceiptInput, ReturnedRootAssignmentReceiptFieldsInput,
            ReturnedRootAssignmentReceiptOutput, rows, index, maps, definitionNames, definitionBinders, loweredNames, loweredIDs, scheduled, physical
<1>. DEFINE view == rows[index].view
            count == Len(rows) - 1
            replacements == ScheduledRootReplacementNames(maps[index], definitionNames)
<1>bounds. /\ count \in 0..Len(rows) /\ index \in 1..(count + 1)
    BY ONLY (Len(rows) \in Nat), (index \in 1..Len(rows)), SMT DEF count
<1>incoming. maps[index] = DirectCopyRoutes(Keys, rows)[index - 1]
    BY (Len(rows) \in Nat), <1>bounds, DirectCopyRoutesAgreeWithRecordedPrefixes, SMT DEF count
<1>projection. \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" =>
    StateExprReplaceProjection(view, replacements)[origin].payload =
        StateExprReplaceReadName(replacements, view.reads[origin])
    BY ONLY CompilerOccurrenceTree(rows[index].view, rows[index].emitted.count),
        StateExprReplacementHasAUniqueProjection, SMT DEF view
<1>names. \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" =>
    loweredNames[origin] = StateExprReplaceProjection(view, replacements)[origin].payload
    <2>. TAKE origin \in DOMAIN view.kinds
    <2>. SUFFICES ASSUME view.kinds[origin] = "read"
                  PROVE loweredNames[origin] = StateExprReplaceProjection(view, replacements)[origin].payload
        OBVIOUS
    <2>. DEFINE key == view.reads[origin]
                name == loweredNames[origin]
                id == loweredIDs[origin]
                slot == AssignmentBinderSlot(definitionBinders, id[2])
    <2>key. key \in Keys
        BY ONLY AssignmentRhsCertificate(rows[index]), (origin \in DOMAIN view.kinds), (view.kinds[origin] = "read"), SMT
            DEF view, key, AssignmentRhsCertificate, LiteralReadAddCertificate, TypedVisitedSourceInputs
    <2>receipt. /\ scheduled[origin] = maps[index][key]
                /\ (\/ /\ id[1] = "state" /\ name = key /\ scheduled[origin] = <<"state", key>>
                    \/ /\ id[1] = "binding" /\ slot \in 1..(index - 1)
                       /\ name = definitionNames[slot] /\ scheduled[origin] = <<"capture", slot>>)
        BY (origin \in DOMAIN view.kinds), (view.kinds[origin] = "read"), SMT DEF view, key, name, id, slot
    <2>name. name = StateExprReplaceReadName(replacements, key)
        <3>state. CASE id[1] = "state"
            <4>route. maps[index][key] = <<"state", key>> /\ name = key
                BY ONLY <3>state, <2>receipt, SMT
            <4>. QED BY ONLY <4>route, SMT DEF replacements, ScheduledRootReplacementNames, StateExprReplaceReadName
        <3>capture. CASE id[1] # "state"
            <4>route. maps[index][key] = <<"capture", slot>> /\ name = definitionNames[slot]
                BY ONLY <3>capture, <2>receipt, SMT
            <4>. QED BY ONLY <4>route, <2>key, SMT DEF replacements, ScheduledRootReplacementNames, StateExprReplaceReadName
        <3>. QED BY ONLY <3>state, <3>capture, SMT
    <2>. QED BY ONLY <2>name, <1>projection, (origin \in DOMAIN view.kinds), (view.kinds[origin] = "read"), SMT DEF key, name
<1>routes. PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
    BY ONLY (index \in DOMAIN rows), AssignmentRhsCertificate(rows[index]), <1>incoming,
        PhysicalAssignmentOperandsMatch(rows[index], physical),
        (\A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
            scheduled[origin] = maps[index][rows[index].view.reads[origin]]),
        (\A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
            physical.reads[node] = scheduled[rows[index].emitted.origins[node]]),
        ScheduledReadLookupsSupplyThePhysicalAssignmentRoutes, SMT
<1>. QED BY ONLY <1>incoming, <1>names, <1>routes DEF view, replacements

THEOREM ReturnedRootAssignmentReceiptFieldsSupplyPhysicalRoutes ==
    \A rows, index, maps, definitionNames, definitionBinders, loweredNames, loweredIDs, scheduled, physical :
        ReturnedRootAssignmentReceiptFieldsInput(rows, index, maps, definitionNames, definitionBinders,
            loweredNames, loweredIDs, scheduled, physical) =>
                PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
PROOF
<1>. TAKE rows, index, maps, definitionNames, definitionBinders, loweredNames, loweredIDs, scheduled, physical
<1>. SUFFICES ASSUME ReturnedRootAssignmentReceiptFieldsInput(rows, index, maps, definitionNames,
                         definitionBinders, loweredNames, loweredIDs, scheduled, physical)
              PROVE PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
    OBVIOUS
<1>. DEFINE receipt == [rows |-> rows, index |-> index, maps |-> maps,
                         definitionNames |-> definitionNames, definitionBinders |-> definitionBinders,
                         loweredNames |-> loweredNames, loweredIDs |-> loweredIDs, scheduled |-> scheduled,
                         physical |-> physical]
<1>input. ReturnedRootAssignmentReceiptInput(receipt)
    BY ONLY ReturnedRootAssignmentReceiptFieldsInput(rows, index, maps, definitionNames, definitionBinders,
                 loweredNames, loweredIDs, scheduled, physical), SMT DEF ReturnedRootAssignmentReceiptInput, receipt
<1>output. ReturnedRootAssignmentReceiptOutput(receipt)
    BY ONLY <1>input, ReturnedRootAssignmentReceiptRecordSuppliesScheduledReadRoutes, SMT
<1>. QED BY ONLY <1>output, SMT DEF ReturnedRootAssignmentReceiptOutput, receipt

THEOREM ReturnedRootAssignmentReceiptSuppliesScheduledReadRoutes ==
    ASSUME NEW rows, Len(rows) \in Nat, NEW index \in 1..Len(rows), index \in DOMAIN rows,
           AssignmentRhsCertificate(rows[index]),
           CompilerOccurrenceTree(rows[index].view, rows[index].emitted.count),
           NEW maps, maps[1] = CopyEntryRoutes(Keys),
           \A position \in 1..(Len(rows) - 1) :
               maps[position + 1] =
                   CopyReplace(Keys, maps[position], rows[position].target, <<"capture", position>>),
           NEW definitionNames, NEW definitionBinders, NEW loweredNames, NEW loweredIDs, NEW scheduled,
           \A a, b \in 1..(index - 1) : definitionNames[a] = definitionNames[b] => a = b,
           \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
               scheduled[origin] = maps[index][rows[index].view.reads[origin]],
           \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
               LET key == rows[index].view.reads[origin]
                   name == loweredNames[origin]
                   id == loweredIDs[origin]
                   slot == AssignmentBinderSlot(definitionBinders, id[2])
               IN /\ \A p \in 1..(index - 1) : definitionNames[p] # key
                  /\ (\/ /\ id[1] = "state" /\ name = key /\ scheduled[origin] = <<"state", key>>
                      \/ /\ id[1] = "binding" /\ slot \in 1..(index - 1)
                         /\ id[2] = definitionBinders[slot] /\ name = definitionNames[slot]
                         /\ scheduled[origin] = <<"capture", slot>>),
           NEW physical, PhysicalAssignmentOperandsMatch(rows[index], physical),
           \A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
               physical.reads[node] = scheduled[rows[index].emitted.origins[node]]
    PROVE /\ maps[index] = DirectCopyRoutes(Keys, rows)[index - 1]
          /\ \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
                 loweredNames[origin] = StateExprReplaceProjection(rows[index].view,
                     ScheduledRootReplacementNames(maps[index], definitionNames))[origin].payload
          /\ PhysicalAssignmentReadsMatchRoutes(rows, index, physical)
PROOF
<1>. DEFINE boundReceipt == [rows |-> rows, index |-> index, maps |-> maps,
                            definitionNames |-> definitionNames, definitionBinders |-> definitionBinders,
                            loweredNames |-> loweredNames, loweredIDs |-> loweredIDs,
                            scheduled |-> scheduled, physical |-> physical]
<1>inputs. ReturnedRootAssignmentReceiptInput(boundReceipt)
    BY SMT DEF ReturnedRootAssignmentReceiptInput, ReturnedRootAssignmentReceiptFieldsInput, boundReceipt
<1>outputs. ReturnedRootAssignmentReceiptOutput(boundReceipt)
    BY ONLY <1>inputs, ReturnedRootAssignmentReceiptRecordSuppliesScheduledReadRoutes, SMT
<1>. QED BY ONLY <1>outputs, SMT DEF ReturnedRootAssignmentReceiptOutput, boundReceipt

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

THEOREM PhysicalAssignmentRhsAgreesWithWitness ==
    ASSUME NEW plan, NEW before, NEW completed, NEW witness,
           plan.count \in Nat \ {0},
           \A index \in 1..plan.count : plan.kinds[index] = "add" =>
               /\ plan.left[index] \in 1..(index - 1)
               /\ plan.right[index] \in 1..(index - 1),
           \A index \in 1..plan.count : plan.kinds[index] \in {"literal", "read", "add"},
           PhysicalAssignmentRhsHistory(plan, before, completed, witness)
    PROVE PhysicalAssignmentRhs(plan, before, completed) = witness[plan.count]
PROOF
<1>. DEFINE selected == CHOOSE h : PhysicalAssignmentRhsHistory(plan, before, completed, h)
            agrees(index) == selected[index] = witness[index]
<1>chosen. PhysicalAssignmentRhsHistory(plan, before, completed, selected)
    BY ONLY PhysicalAssignmentRhsHistory(plan, before, completed, witness), SMT DEF selected
<1>base. agrees(0)
    BY ONLY <1>chosen, PhysicalAssignmentRhsHistory(plan, before, completed, witness), SMT
        DEF agrees, PhysicalAssignmentRhsHistory, GeneratedExpressionHistory
<1>step. \A index \in 1..plan.count :
             ((\A child \in 0..(index - 1) : agrees(child)) => agrees(index))
    <2>. SUFFICES ASSUME NEW index \in 1..plan.count,
                         \A child \in 0..(index - 1) : agrees(child)
                 PROVE agrees(index)
        BY SMT
    <2>. DEFINE atNode(history) ==
            GeneratedNode(index, plan.kinds, plan.literals, PhysicalRhsReadIndices(plan),
                plan.left, plan.right, PhysicalRhsBindings(plan, before, completed), history)
    <2>evaluate. ASSUME NEW h, PhysicalAssignmentRhsHistory(plan, before, completed, h)
                  PROVE h[index] = atNode(h)
        BY ONLY PhysicalAssignmentRhsHistory(plan, before, completed, h),
            (index \in 1..plan.count), SMT
            DEF atNode, PhysicalAssignmentRhsHistory, GeneratedExpressionHistory
    <2>selectedNode. selected[index] = atNode(selected)
        BY ONLY <1>chosen, <2>evaluate, Zenon
    <2>witnessNode. witness[index] = atNode(witness)
        BY ONLY PhysicalAssignmentRhsHistory(plan, before, completed, witness),
            (index \in 1..plan.count), SMT
            DEF atNode, PhysicalAssignmentRhsHistory, GeneratedExpressionHistory
    <2>kind. plan.kinds[index] \in {"literal", "read", "add"}
        BY SMT
    <2>literal. CASE plan.kinds[index] = "literal"
        BY ONLY <2>literal, <2>selectedNode, <2>witnessNode, SMT
            DEF agrees, atNode, GeneratedNode
    <2>read. CASE plan.kinds[index] = "read"
        BY ONLY <2>read, <2>selectedNode, <2>witnessNode, SMT
            DEF agrees, atNode, GeneratedNode
    <2>add. CASE plan.kinds[index] = "add"
        <3>children. /\ agrees(plan.left[index])
                     /\ agrees(plan.right[index])
            BY <2>add, SMT
        <3>. QED BY ONLY <2>add, <2>selectedNode, <2>witnessNode, <3>children, SMT
            DEF agrees, atNode, GeneratedNode
    <2>. QED BY ONLY <2>kind, <2>literal, <2>read, <2>add, SMT
<1>all. \A index \in 0..plan.count : agrees(index)
    BY <1>base, <1>step, FiniteIndexedPrefixProperty
<1>. QED BY <1>all, SMT DEF agrees, selected, PhysicalAssignmentRhs

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
