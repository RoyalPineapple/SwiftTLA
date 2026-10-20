---------------- MODULE SequenceTailRule ----------------
EXTENDS TLAPS, SequenceTheorems

SourceSequenceTail(value) ==
    [index \in 1..(Len(value) - 1) |-> value[index + 1]]

THEOREM TailValuePreserved ==
    ASSUME NEW S, NEW value \in Seq(S), Len(value) > 0
    PROVE SourceSequenceTail(value) = Tail(value)
    BY TailIsSubSeq, SubSeqProperties, IsASeq, SMT
        DEF SourceSequenceTail

=========================================================
