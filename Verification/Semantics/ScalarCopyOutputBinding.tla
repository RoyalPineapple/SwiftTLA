---- MODULE ScalarCopyOutputBinding ----
EXTENDS OrderedScalarCopyRule

CopyReceiptOrdinal(reference) ==
    IF reference[1] = "capture" THEN reference[2] ELSE 0

CopyReceiptNamesWriter(copies, prefix, key, reference) ==
    LET writer == CopyReceiptOrdinal(reference)
    IN /\ LastDirectCopy(copies, prefix, key, writer)
       /\ reference = DirectCopyReference(key, writer)

THEOREM NamedReceiptReferenceUsesTheLastWriter ==
    ASSUME NEW keys, NEW rows, Len(rows) \in Nat, NEW prefix \in 0..Len(rows),
           NEW key \in keys, NEW reference, CopyReceiptNamesWriter(rows, prefix, key, reference)
    PROVE reference = DirectCopyRoutes(keys, rows)[prefix][key]
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
    (prefix \in 0..Len(rows)), (key \in keys), SMT DEF CopyReceiptNamesWriter, DirectCopyRoutes

ContinuationReadsNameWriters(keys, rows) ==
    /\ Len(rows) \in Nat
    /\ DOMAIN rows = 1..Len(rows)
    /\ \A index \in DOMAIN rows :
           /\ rows[index].target \in keys
           /\ \A occurrence \in DOMAIN rows[index].reads :
                  LET read == rows[index].reads[occurrence]
                  IN /\ read.key \in keys
                     /\ CopyReceiptNamesWriter(rows, index - 1, read.key, read.reference)

ContinuationReadsUseTheOrderedWrites(keys, rows) ==
    \A index \in DOMAIN rows :
        \A occurrence \in DOMAIN rows[index].reads :
            LET read == rows[index].reads[occurrence]
            IN read.reference = DirectCopyRoutes(keys, rows)[index - 1][read.key]

THEOREM AContinuationReadsTheLatestWriterOnItsOwnPath ==
    ASSUME NEW keys, NEW rows, ContinuationReadsNameWriters(keys, rows)
    PROVE ContinuationReadsUseTheOrderedWrites(keys, rows)
PROOF
<1>. SUFFICES ASSUME NEW index \in DOMAIN rows, NEW occurrence \in DOMAIN rows[index].reads
               PROVE LET read == rows[index].reads[occurrence]
                     IN read.reference = DirectCopyRoutes(keys, rows)[index - 1][read.key]
    BY ONLY DEF ContinuationReadsUseTheOrderedWrites
<1>. DEFINE read == rows[index].reads[occurrence]
<1>bound. /\ Len(rows) \in Nat /\ index - 1 \in 0..Len(rows)
    BY ONLY ContinuationReadsNameWriters(keys, rows), (index \in DOMAIN rows), SMT DEF ContinuationReadsNameWriters
<1>name. /\ read.key \in keys
         /\ CopyReceiptNamesWriter(rows, index - 1, read.key, read.reference)
    BY ONLY ContinuationReadsNameWriters(keys, rows), (index \in DOMAIN rows),
        (occurrence \in DOMAIN rows[index].reads), SMT DEF ContinuationReadsNameWriters, read
<1>. QED BY ONLY <1>bound, <1>name, NamedReceiptReferenceUsesTheLastWriter, SMT DEF read

ContinuationGuardsFollowTheLexicalPrefix(gates, count) ==
    /\ gates \in [1..count -> BOOLEAN]
    /\ \A index \in 2..count : gates[index] => gates[index - 1]

THEOREM AFailedCaptureBlocksEveryLaterContinuationCapture ==
    ASSUME NEW count \in Nat, NEW gates, ContinuationGuardsFollowTheLexicalPrefix(gates, count),
           NEW failure \in 1..count, ~gates[failure]
    PROVE \A later \in failure..count : ~gates[later]
PROOF
<1>. DEFINE stopped(index) == index \in failure..count => ~gates[index]
<1>before. stopped(0)
    BY ONLY (failure \in 1..count), SMT DEF stopped
<1>step. \A index \in 1..count :
    (\A prior \in 0..(index - 1) : stopped(prior)) => stopped(index)
    <2>. SUFFICES ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : stopped(prior),
                         index \in failure..count
                 PROVE ~gates[index]
        BY ONLY DEF stopped
    <2>at. CASE index = failure
        BY ONLY <2>at, (~gates[failure]), SMT
    <2>after. CASE index > failure
        <3>bounds. /\ index \in 2..count
                   /\ index - 1 \in failure..count
                   /\ index - 1 \in 0..(index - 1)
            BY ONLY <2>after, (index \in 1..count), (failure \in 1..count), SMT
        <3>prior. ~gates[index - 1]
            BY ONLY <3>bounds, (\A prior \in 0..(index - 1) : stopped(prior)), SMT DEF stopped
        <3>. QED BY ONLY <3>bounds, <3>prior, ContinuationGuardsFollowTheLexicalPrefix(gates, count), SMT
            DEF ContinuationGuardsFollowTheLexicalPrefix
    <2>. QED BY ONLY <2>at, <2>after, (index \in failure..count), SMT
<1>. HIDE DEF stopped
<1>all. \A index \in 0..count : stopped(index)
    BY ONLY (count \in Nat), <1>before, <1>step, FiniteIndexedPrefixProperty, Isa
<1>. QED BY ONLY <1>all, (failure \in 1..count), SMT DEF stopped

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
        <2>. QED BY ONLY (Len(copies) \in Nat), (prefix \in 0..count), (key \in keys),
            CopyReceiptNamesWriter(copies, prefix, key, reference), NamedReceiptReferenceUsesTheLastWriter, SMT
            DEF routes, count
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
