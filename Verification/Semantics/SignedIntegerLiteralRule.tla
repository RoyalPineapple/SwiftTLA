-------------------- MODULE SignedIntegerLiteralRule --------------------
EXTENDS TLAPS, Integers, NaturalsInduction

Radix == 1000000000
SignedMagnitude(value, negative) == IF negative THEN -value ELSE value
UnsignedChunk(prefix, chunk) == prefix * Radix + chunk
RenderedChunk(prefix, chunk, negative) ==
    IF negative THEN prefix * Radix - chunk ELSE prefix * Radix + chunk

THEOREM SignedChunkRule ==
    ASSUME NEW prefix \in Int, NEW chunk \in Int,
           NEW negative \in BOOLEAN
    PROVE RenderedChunk(SignedMagnitude(prefix, negative), chunk, negative)
        = SignedMagnitude(UnsignedChunk(prefix, chunk), negative)
    BY SMT DEF RenderedChunk, SignedMagnitude, UnsignedChunk, Radix

THEOREM SignedLiteralComposition ==
    ASSUME NEW count \in Nat, NEW chunks \in [1..count -> 0..(Radix - 1)],
           NEW unsigned, NEW rendered, NEW negative \in BOOLEAN,
           \A index \in 0..count : unsigned[index] \in Int,
           rendered[0] = SignedMagnitude(unsigned[0], negative),
           \A index \in 1..count :
               /\ unsigned[index] = UnsignedChunk(unsigned[index - 1], chunks[index])
               /\ rendered[index] = RenderedChunk(rendered[index - 1],
                       chunks[index], negative)
    PROVE \A index \in 0..count :
        rendered[index] = SignedMagnitude(unsigned[index], negative)
    PROOF
    <1>. DEFINE P(index) == index \in 0..count =>
        \A prior \in 0..index :
            rendered[prior] = SignedMagnitude(unsigned[prior], negative)
    <1>1. P(0) BY SMT DEF P
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..count
                     PROVE \A prior \in 0..(index + 1) :
                         rendered[prior] = SignedMagnitude(unsigned[prior], negative)
            BY SMT DEF P
        <2>1. index \in 0..count BY SMT
        <2>2. \A prior \in 0..index :
                rendered[prior] = SignedMagnitude(unsigned[prior], negative)
            BY <2>1, P(index), SMT DEF P
        <2>3. index + 1 \in 1..count BY SMT
        <2>3a. unsigned[index] \in Int /\ chunks[index + 1] \in Int
            BY <2>1, <2>3, SMT DEF Radix
        <2>4. rendered[index + 1] =
                SignedMagnitude(unsigned[index + 1], negative)
            BY <2>2, <2>3, <2>3a, SignedChunkRule, SMT
                DEF UnsignedChunk, RenderedChunk
        <2>. QED BY <2>2, <2>4, SMT
    <1>3. HIDE DEF P
    <1>4. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>. QED BY <1>4, SMT DEF P
====
