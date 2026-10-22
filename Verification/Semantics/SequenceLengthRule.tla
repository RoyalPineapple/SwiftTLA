---------------- MODULE SequenceLengthRule ----------------
EXTENDS TLAPS, FiniteSetTheorems, SequenceTheorems

SourceSequenceLength(value) == Cardinality(DOMAIN value)

THEOREM SequenceLengthIsDomainSize ==
    ASSUME NEW S, NEW value \in Seq(S)
    PROVE SourceSequenceLength(value) = Len(value)
    BY IsASeq, FS_Interval, SMT DEF SourceSequenceLength

=============================================================
