---------------- MODULE SequencePrefixRule ----------------
EXTENDS TLAPS, SequenceTheorems

SourceSequencePrefix(value, count) ==
    IF count < 1 THEN <<>> ELSE [index \in 1..count |-> value[index]]

THEOREM SequencePrefixValuePreserved ==
    ASSUME NEW S, NEW value \in Seq(S), NEW count \in Int,
           count <= Len(value)
    PROVE SourceSequencePrefix(value, count) = SubSeq(value, 1, count)
    PROOF
    <1>1. CASE count < 1
        <2>1. SourceSequencePrefix(value, count) = <<>>
            BY <1>1 DEF SourceSequencePrefix
        <2>2. SubSeq(value, 1, count) = <<>>
            BY <1>1, SubSeqEmpty, SMT
        <2>3. QED BY <2>1, <2>2
    <1>2. CASE count >= 1
        <2>1. count \in 0..Len(value) BY <1>2, SMT
        <2>2. SubSeq(value, 1, count) = Restrict(value, 1..count)
            BY <2>1, SubSeqRestrict
        <2>3. SourceSequencePrefix(value, count) = Restrict(value, 1..count)
            BY <1>2, SMT DEF SourceSequencePrefix, Restrict
        <2>4. QED BY <2>2, <2>3
    <1>3. QED BY <1>1, <1>2, SMT

=============================================================
