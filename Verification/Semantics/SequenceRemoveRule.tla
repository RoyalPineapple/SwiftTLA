---------------- MODULE SequenceRemoveRule ----------------
EXTENDS TLAPS, SequenceTheorems

SourceRemoveDefined(value, index) == index \in 1..Len(value)
CompiledRemoveDefined(value, index) == index \in DOMAIN value

SourceRemoveValue(value, index) ==
    [position \in 1..(Len(value) - 1) |->
        IF position < index THEN value[position] ELSE value[position + 1]]
CompiledRemoveValue(value, index) ==
    SubSeq(value, 1, index - 1) \o SubSeq(value, index + 1, Len(value))

THEOREM RemoveDomainPreserved ==
    ASSUME NEW S, NEW value \in Seq(S), NEW index \in Int
    PROVE SourceRemoveDefined(value, index)
        <=> CompiledRemoveDefined(value, index)
    BY SMT DEF SourceRemoveDefined, CompiledRemoveDefined

THEOREM RemoveValuePreserved ==
    ASSUME NEW S, NEW value \in Seq(S), NEW index \in Int,
           SourceRemoveDefined(value, index)
    PROVE SourceRemoveValue(value, index) = CompiledRemoveValue(value, index)
    BY SubSeqProperties, ConcatProperties, SeqEqual, SMT
        DEF SourceRemoveValue, CompiledRemoveValue,
            SourceRemoveDefined

============================================================
