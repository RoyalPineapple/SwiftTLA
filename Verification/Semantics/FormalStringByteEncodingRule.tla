---------------- MODULE FormalStringByteEncodingRule ----------------
EXTENDS TLAPS, Integers, Sequences

Byte == 0..255
BytePair(value) == <<value \div 16, value % 16>>
EncodedPairs(bytes) == [index \in 1..Len(bytes) |-> BytePair(bytes[index])]
FlatPairs(bytes) ==
    [position \in 1..(2 * Len(bytes)) |->
        IF position % 2 = 1
        THEN bytes[(position + 1) \div 2] \div 16
        ELSE bytes[position \div 2] % 16]
HexCharacter(nibble) ==
    IF nibble < 10 THEN nibble + 48 ELSE nibble + 55
HexBytes(bytes) ==
    [position \in 1..(2 * Len(bytes)) |->
        HexCharacter(FlatPairs(bytes)[position])]

THEOREM BytePairIsInjective ==
    ASSUME NEW first \in Byte, NEW second \in Byte,
           BytePair(first) = BytePair(second)
    PROVE first = second
    BY SMT DEF BytePair, Byte

THEOREM EncodedByteSequencesAreInjective ==
    ASSUME NEW first \in Seq(Byte), NEW second \in Seq(Byte),
           EncodedPairs(first) = EncodedPairs(second)
    PROVE first = second
    PROOF
    <1>1. Len(first) = Len(second)
        BY SMT DEF EncodedPairs
    <1>2. \A index \in 1..Len(first) :
              BytePair(first[index]) = BytePair(second[index])
        BY <1>1, SMT DEF EncodedPairs
    <1>3. \A index \in 1..Len(first) :
              first[index] \in Byte /\ second[index] \in Byte
        BY <1>1, SMT
    <1>4. \A index \in 1..Len(first) : first[index] = second[index]
        BY <1>2, <1>3, BytePairIsInjective, SMT DEF Byte
    <1> QED BY <1>1, <1>4, SMT

THEOREM FlattenedBytePairsAreInjective ==
    ASSUME NEW first \in Seq(Byte), NEW second \in Seq(Byte),
           FlatPairs(first) = FlatPairs(second)
    PROVE first = second
    PROOF
    <1>1. DOMAIN FlatPairs(first) = 1..(2 * Len(first))
        BY SMT DEF FlatPairs
    <1>2. DOMAIN FlatPairs(second) = 1..(2 * Len(second))
        BY SMT DEF FlatPairs
    <1>3. Len(first) = Len(second)
        BY <1>1, <1>2, SMT
    <1>4. \A index \in 1..Len(first) :
              FlatPairs(first)[2 * index - 1] = first[index] \div 16
              /\ FlatPairs(first)[2 * index] = first[index] % 16
              /\ FlatPairs(second)[2 * index - 1] = second[index] \div 16
              /\ FlatPairs(second)[2 * index] = second[index] % 16
        BY <1>3, SMT DEF FlatPairs
    <1>5. \A index \in 1..Len(first) :
              BytePair(first[index]) = BytePair(second[index])
        BY <1>4, SMT DEF BytePair
    <1>6. EncodedPairs(first) = EncodedPairs(second)
        BY <1>3, <1>5, SMT DEF EncodedPairs
    <1> QED BY <1>6, EncodedByteSequencesAreInjective, SMT

THEOREM HexCharacterIsInjective ==
    ASSUME NEW first \in 0..15, NEW second \in 0..15,
           HexCharacter(first) = HexCharacter(second)
    PROVE first = second
    BY SMT DEF HexCharacter

THEOREM ByteNibblesAreInRange ==
    ASSUME NEW value \in Byte
    PROVE value \div 16 \in 0..15 /\ value % 16 \in 0..15
    BY SMT DEF Byte

THEOREM UppercaseHexByteEncodingIsInjective ==
    ASSUME NEW first \in Seq(Byte), NEW second \in Seq(Byte),
           HexBytes(first) = HexBytes(second)
    PROVE first = second
    PROOF
    <1>1. Len(first) = Len(second)
        BY SMT DEF HexBytes
    <1>2. \A position \in 1..(2 * Len(first)) :
              FlatPairs(first)[position] \in 0..15
              /\ FlatPairs(second)[position] \in 0..15
        BY <1>1, ByteNibblesAreInRange, SMT DEF FlatPairs, Byte
    <1>3. \A position \in 1..(2 * Len(first)) :
              HexCharacter(FlatPairs(first)[position])
                  = HexCharacter(FlatPairs(second)[position])
        BY <1>1, SMT DEF HexBytes
    <1>4. \A position \in 1..(2 * Len(first)) :
              FlatPairs(first)[position] = FlatPairs(second)[position]
        BY <1>2, <1>3, HexCharacterIsInjective, SMT
    <1>5. FlatPairs(first) = FlatPairs(second)
        BY <1>1, <1>4, SMT DEF FlatPairs
    <1> QED BY <1>5, FlattenedBytePairsAreInjective, SMT

\* The implementation escapes raw strings that could start with its prefix.
HasPrefix(value, prefix) ==
    \E tail \in Seq(Byte) : value = prefix \o tail
EncodedIdentity(rawEligible, raw, escaped, prefix) ==
    IF rawEligible THEN raw ELSE prefix \o escaped

THEOREM RawAndEscapedBranchesCannotCollide ==
    ASSUME NEW raw \in Seq(Byte), NEW escaped \in Seq(Byte),
           NEW prefix \in Seq(Byte), ~HasPrefix(raw, prefix)
    PROVE EncodedIdentity(TRUE, raw, escaped, prefix)
        # EncodedIdentity(FALSE, raw, escaped, prefix)
    BY SMT DEF EncodedIdentity, HasPrefix

THEOREM OmittingPrefixEscapeCausesCollision ==
    EncodedIdentity(TRUE, <<1, 2>>, <<2>>, <<1>>)
        = EncodedIdentity(FALSE, <<1, 2>>, <<2>>, <<1>>)
    BY SMT DEF EncodedIdentity

=====================================================================
