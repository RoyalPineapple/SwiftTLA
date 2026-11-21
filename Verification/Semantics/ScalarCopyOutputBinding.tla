---- MODULE ScalarCopyOutputBinding ----
EXTENDS OrderedScalarCopyRule

CopyReceiptOrdinal(reference) ==
    IF reference[1] = "capture" THEN reference[2] ELSE 0

CopyReceiptNamesWriter(copies, prefix, key, reference) ==
    LET writer == CopyReceiptOrdinal(reference)
    IN /\ LastDirectCopy(copies, prefix, key, writer)
       /\ reference = DirectCopyReference(key, writer)

ReceiptNamesLastWriters(keys, copies, reads, writes) ==
    /\ DOMAIN reads = DOMAIN copies
    /\ DOMAIN writes = keys
    /\ reads = [index \in DOMAIN copies |-> reads[index]]
    /\ writes = [key \in keys |-> writes[key]]
    /\ \A index \in DOMAIN copies :
           CopyReceiptNamesWriter(copies, index - 1, copies[index].read, reads[index])
    /\ \A key \in keys :
           CopyReceiptNamesWriter(copies, Len(copies), key, writes[key])

THEOREM CheckedReceiptIsTheScheduledReceipt ==
    ASSUME NEW keys, NEW copies, NEW reads, NEW writes,
           Len(copies) \in Nat, DOMAIN copies = 1..Len(copies),
           \A index \in DOMAIN copies :
               copies[index].target \in keys /\ copies[index].read \in keys,
           ReceiptNamesLastWriters(keys, copies, reads, writes)
    PROVE /\ reads = DirectCopyScheduledReceipt(keys, copies).reads
          /\ writes = DirectCopyScheduledReceipt(keys, copies).writes
    PROOF
    <1>. DEFINE count == Len(copies)
                routes == DirectCopyRoutes(keys, copies)
    <1>resolve. \A prefix \in 0..count : \A key \in keys : \A reference :
        CopyReceiptNamesWriter(copies, prefix, key, reference) => reference = routes[prefix][key]
        PROOF
        <2>. SUFFICES ASSUME NEW prefix \in 0..count, NEW key \in keys, NEW reference,
                            CopyReceiptNamesWriter(copies, prefix, key, reference)
                     PROVE reference = routes[prefix][key]
            OBVIOUS
        <2>chosen. LastDirectCopy(copies, prefix, key, DirectCopyWriter(copies, prefix, key))
            BY EveryFiniteCopyPrefixHasALastWriter, SMT DEF count, DirectCopyWriter
        <2>named. LastDirectCopy(copies, prefix, key, CopyReceiptOrdinal(reference))
            BY SMT DEF CopyReceiptNamesWriter
        <2>same. CopyReceiptOrdinal(reference) = DirectCopyWriter(copies, prefix, key)
            BY <2>chosen, <2>named, TwoLastDirectCopiesHaveTheSamePosition, SMT DEF count
        <2>. QED BY <2>same, SMT DEF CopyReceiptNamesWriter, routes, DirectCopyRoutes, count
    <1>reads. \A index \in DOMAIN copies : reads[index] = routes[index - 1][copies[index].read]
        BY <1>resolve, SMT DEF ReceiptNamesLastWriters, count
    <1>writes. \A key \in keys : writes[key] = routes[count][key]
        BY <1>resolve, SMT DEF ReceiptNamesLastWriters, count
    <1>returned. DirectCopyScheduledReceipt(keys, copies) =
        [reads |-> [index \in 1..count |-> routes[index - 1][copies[index].read]],
         writes |-> routes[count]]
        BY (Len(copies) \in Nat), SMT DEF DirectCopyScheduledReceipt, DirectCopySchedulerFold,
            DirectCopyReceiptAtPrefix, routes, count
    <1>. QED BY <1>reads, <1>writes, <1>returned, SMT
        DEF ReceiptNamesLastWriters, routes, DirectCopyRoutes, count

====
