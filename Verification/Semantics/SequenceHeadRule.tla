---------------- MODULE SequenceHeadRule ----------------
EXTENDS TLAPS, SequenceTheorems

SourceSequenceHasHead(value) == 1 \in DOMAIN value
SourceSequenceHead(value) == value[1]

THEOREM HeadDefinedByLength ==
    ASSUME NEW S, NEW value \in Seq(S)
    PROVE SourceSequenceHasHead(value) <=> Len(value) > 0
    BY IsASeq, SMT DEF SourceSequenceHasHead

THEOREM HeadValuePreserved ==
    ASSUME NEW S, NEW value \in Seq(S), SourceSequenceHasHead(value)
    PROVE SourceSequenceHead(value) = Head(value)
    BY DEF SourceSequenceHead

=========================================================
