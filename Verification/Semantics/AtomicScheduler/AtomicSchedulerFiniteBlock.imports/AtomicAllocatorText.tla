---- MODULE AtomicAllocatorText ----
EXTENDS TLAPS, Sequences, CompilerInputPageBlock5, CompilerInputPageBlock6, CompilerInputPageBlock7
\* CompilerInputPage289
\* CompilerInputPage290
\* CompilerInputPage291
\* CompilerInputPage292
\* CompilerInputPage293
\* CompilerInputPage306
\* CompilerInputPage307
\* CompilerInputPage308
\* CompilerInputPage309
\* CompilerInputPage310
\* CompilerInputPage311
\* CompilerInputPage312
\* CompilerInputPage313
\* CompilerInputPage314
\* CompilerInputPage315
\* CompilerInputPage316
\* CompilerInputPage317
\* CompilerInputPage318
\* CompilerInputPage319
\* CompilerInputPage320
\* CompilerInputPage321
\* CompilerInputPage322
\* CompilerInputPage323
\* CompilerInputPage324
\* CompilerInputPage407
\* CompilerInputPage408
\* CompilerInputPage409
\* CompilerInputPage410
\* CompilerInputPage411
\* CompilerInputPage412
\* CompilerInputPage413
AllocatorText(first,n) == [i \in 1..n |-> CompilerInputByte[first+i-1]]

THEOREM AllocatorChunk0 == AllocatorText(4612,12) = <<32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32>>
PROOF
<1>bytes. \A i \in 1..12 : CompilerInputByte[4612+i-1] = <<32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk1 == AllocatorText(4624,16) = <<117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 32, 61, 32, 97>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4624+i-1] = <<117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 32, 61, 32, 97>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk2 == AllocatorText(4640,16) = <<117, 116, 104, 111, 114, 101, 100, 73, 100, 101, 110, 116, 105, 102, 105, 101>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4640+i-1] = <<117, 116, 104, 111, 114, 101, 100, 73, 100, 101, 110, 116, 105, 102, 105, 101>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk3 == AllocatorText(4656,16) = <<114, 115, 10, 32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 110>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4656+i-1] = <<114, 115, 10, 32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 110>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk4 == AllocatorText(4672,14) = <<101, 120, 116, 66, 105, 110, 100, 105, 110, 103, 32, 61, 32, 48>>
PROOF
<1>bytes. \A i \in 1..14 : CompilerInputByte[4672+i-1] = <<101, 120, 116, 66, 105, 110, 100, 105, 110, 103, 32, 61, 32, 48>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk5 == AllocatorText(4886,10) = <<32, 32, 32, 32, 32, 32, 32, 32, 102, 117>>
PROOF
<1>bytes. \A i \in 1..10 : CompilerInputByte[4886+i-1] = <<32, 32, 32, 32, 32, 32, 32, 32, 102, 117>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk6 == AllocatorText(4896,16) = <<110, 99, 32, 98, 105, 110, 100, 105, 110, 103, 40, 41, 32, 45, 62, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4896+i-1] = <<110, 99, 32, 98, 105, 110, 100, 105, 110, 103, 40, 41, 32, 45, 62, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk7 == AllocatorText(4912,16) = <<83, 116, 114, 105, 110, 103, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4912+i-1] = <<83, 116, 114, 105, 110, 103, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk8 == AllocatorText(4928,16) = <<32, 32, 32, 32, 32, 119, 104, 105, 108, 101, 32, 116, 114, 117, 101, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4928+i-1] = <<32, 32, 32, 32, 32, 119, 104, 105, 108, 101, 32, 116, 114, 117, 101, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk9 == AllocatorText(4944,16) = <<123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4944+i-1] = <<123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk10 == AllocatorText(4960,16) = <<32, 32, 108, 101, 116, 32, 99, 97, 110, 100, 105, 100, 97, 116, 101, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4960+i-1] = <<32, 32, 108, 101, 116, 32, 99, 97, 110, 100, 105, 100, 97, 116, 101, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk11 == AllocatorText(4976,16) = <<61, 32, 34, 95, 95, 97, 116, 111, 109, 105, 99, 95, 92, 40, 110, 101>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4976+i-1] = <<61, 32, 34, 95, 95, 97, 116, 111, 109, 105, 99, 95, 92, 40, 110, 101>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk12 == AllocatorText(4992,16) = <<120, 116, 66, 105, 110, 100, 105, 110, 103, 41, 34, 10, 32, 32, 32, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[4992+i-1] = <<120, 116, 66, 105, 110, 100, 105, 110, 103, 41, 34, 10, 32, 32, 32, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk13 == AllocatorText(5008,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 110, 101, 120, 116>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5008+i-1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 110, 101, 120, 116>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk14 == AllocatorText(5024,16) = <<66, 105, 110, 100, 105, 110, 103, 32, 43, 61, 32, 49, 10, 32, 32, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5024+i-1] = <<66, 105, 110, 100, 105, 110, 103, 32, 43, 61, 32, 49, 10, 32, 32, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk15 == AllocatorText(5040,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 105, 102, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5040+i-1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 105, 102, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk16 == AllocatorText(5056,16) = <<117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 46, 105, 110, 115>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5056+i-1] = <<117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 46, 105, 110, 115>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk17 == AllocatorText(5072,16) = <<101, 114, 116, 40, 99, 97, 110, 100, 105, 100, 97, 116, 101, 41, 46, 105>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5072+i-1] = <<101, 114, 116, 40, 99, 97, 110, 100, 105, 100, 97, 116, 101, 41, 46, 105>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk18 == AllocatorText(5088,16) = <<110, 115, 101, 114, 116, 101, 100, 32, 123, 10, 32, 32, 32, 32, 32, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5088+i-1] = <<110, 115, 101, 114, 116, 101, 100, 32, 123, 10, 32, 32, 32, 32, 32, 32>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk19 == AllocatorText(5104,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5104+i-1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk20 == AllocatorText(5120,16) = <<116, 117, 114, 110, 32, 99, 97, 110, 100, 105, 100, 97, 116, 101, 10, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5120+i-1] = <<116, 117, 114, 110, 32, 99, 97, 110, 100, 105, 100, 97, 116, 101, 10, 32>>[i]
    BY ONLY CompilerInputPageBlock6AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk21 == AllocatorText(5136,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5136+i-1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125>>[i]
    BY ONLY CompilerInputPageBlock6AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk22 == AllocatorText(5152,16) = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[5152+i-1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32>>[i]
    BY ONLY CompilerInputPageBlock6AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk23 == AllocatorText(5168,8) = <<32, 32, 32, 32, 32, 32, 32, 125>>
PROOF
<1>bytes. \A i \in 1..8 : CompilerInputByte[5168+i-1] = <<32, 32, 32, 32, 32, 32, 32, 125>>[i]
    BY ONLY CompilerInputPageBlock6AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk24 == AllocatorText(6496,16) = <<108, 101, 116, 32, 115, 116, 97, 116, 101, 109, 101, 110, 116, 115, 32, 61>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[6496+i-1] = <<108, 101, 116, 32, 115, 116, 97, 116, 101, 109, 101, 110, 116, 115, 32, 61>>[i]
    BY ONLY CompilerInputPageBlock7AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk25 == AllocatorText(6512,16) = <<32, 115, 99, 104, 101, 100, 117, 108, 101, 65, 116, 111, 109, 105, 99, 83>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[6512+i-1] = <<32, 115, 99, 104, 101, 100, 117, 108, 101, 65, 116, 111, 109, 105, 99, 83>>[i]
    BY ONLY CompilerInputPageBlock7AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk26 == AllocatorText(6528,16) = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 40, 115, 116, 101, 112, 46, 115>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[6528+i-1] = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 40, 115, 116, 101, 112, 46, 115>>[i]
    BY ONLY CompilerInputPageBlock7AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk27 == AllocatorText(6544,16) = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 44, 32, 98, 105, 110, 100, 105>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[6544+i-1] = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 44, 32, 98, 105, 110, 100, 105>>[i]
    BY ONLY CompilerInputPageBlock7AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk28 == AllocatorText(6560,16) = <<110, 103, 58, 32, 98, 105, 110, 100, 105, 110, 103, 44, 32, 114, 101, 99>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[6560+i-1] = <<110, 103, 58, 32, 98, 105, 110, 100, 105, 110, 103, 44, 32, 114, 101, 99>>[i]
    BY ONLY CompilerInputPageBlock7AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk29 == AllocatorText(6576,16) = <<111, 114, 100, 65, 115, 115, 105, 103, 110, 109, 101, 110, 116, 58, 32, 114>>
PROOF
<1>bytes. \A i \in 1..16 : CompilerInputByte[6576+i-1] = <<111, 114, 100, 65, 115, 115, 105, 103, 110, 109, 101, 110, 116, 58, 32, 114>>[i]
    BY ONLY CompilerInputPageBlock7AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

THEOREM AllocatorChunk30 == AllocatorText(6592,15) = <<101, 99, 111, 114, 100, 83, 99, 104, 101, 100, 117, 108, 101, 100, 44>>
PROOF
<1>bytes. \A i \in 1..15 : CompilerInputByte[6592+i-1] = <<101, 99, 111, 114, 100, 83, 99, 104, 101, 100, 117, 108, 101, 100, 44>>[i]
    BY ONLY CompilerInputPageBlock7AtFileOffsets, SMT
<1>. QED BY ONLY <1>bytes, IsaM("simp"), SMT DEF AllocatorText

RecognizedAllocatorBody ==
    /\ AllocatorText(4612,12) = <<32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32>>
    /\ AllocatorText(4624,16) = <<117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 32, 61, 32, 97>>
    /\ AllocatorText(4640,16) = <<117, 116, 104, 111, 114, 101, 100, 73, 100, 101, 110, 116, 105, 102, 105, 101>>
    /\ AllocatorText(4656,16) = <<114, 115, 10, 32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 110>>
    /\ AllocatorText(4672,14) = <<101, 120, 116, 66, 105, 110, 100, 105, 110, 103, 32, 61, 32, 48>>
    /\ AllocatorText(4886,10) = <<32, 32, 32, 32, 32, 32, 32, 32, 102, 117>>
    /\ AllocatorText(4896,16) = <<110, 99, 32, 98, 105, 110, 100, 105, 110, 103, 40, 41, 32, 45, 62, 32>>
    /\ AllocatorText(4912,16) = <<83, 116, 114, 105, 110, 103, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32>>
    /\ AllocatorText(4928,16) = <<32, 32, 32, 32, 32, 119, 104, 105, 108, 101, 32, 116, 114, 117, 101, 32>>
    /\ AllocatorText(4944,16) = <<123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>
    /\ AllocatorText(4960,16) = <<32, 32, 108, 101, 116, 32, 99, 97, 110, 100, 105, 100, 97, 116, 101, 32>>
    /\ AllocatorText(4976,16) = <<61, 32, 34, 95, 95, 97, 116, 111, 109, 105, 99, 95, 92, 40, 110, 101>>
    /\ AllocatorText(4992,16) = <<120, 116, 66, 105, 110, 100, 105, 110, 103, 41, 34, 10, 32, 32, 32, 32>>
    /\ AllocatorText(5008,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 110, 101, 120, 116>>
    /\ AllocatorText(5024,16) = <<66, 105, 110, 100, 105, 110, 103, 32, 43, 61, 32, 49, 10, 32, 32, 32>>
    /\ AllocatorText(5040,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 105, 102, 32>>
    /\ AllocatorText(5056,16) = <<117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 46, 105, 110, 115>>
    /\ AllocatorText(5072,16) = <<101, 114, 116, 40, 99, 97, 110, 100, 105, 100, 97, 116, 101, 41, 46, 105>>
    /\ AllocatorText(5088,16) = <<110, 115, 101, 114, 116, 101, 100, 32, 123, 10, 32, 32, 32, 32, 32, 32>>
    /\ AllocatorText(5104,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101>>
    /\ AllocatorText(5120,16) = <<116, 117, 114, 110, 32, 99, 97, 110, 100, 105, 100, 97, 116, 101, 10, 32>>
    /\ AllocatorText(5136,16) = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125>>
    /\ AllocatorText(5152,16) = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32>>
    /\ AllocatorText(5168,8) = <<32, 32, 32, 32, 32, 32, 32, 125>>
    /\ AllocatorText(6496,16) = <<108, 101, 116, 32, 115, 116, 97, 116, 101, 109, 101, 110, 116, 115, 32, 61>>
    /\ AllocatorText(6512,16) = <<32, 115, 99, 104, 101, 100, 117, 108, 101, 65, 116, 111, 109, 105, 99, 83>>
    /\ AllocatorText(6528,16) = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 40, 115, 116, 101, 112, 46, 115>>
    /\ AllocatorText(6544,16) = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 44, 32, 98, 105, 110, 100, 105>>
    /\ AllocatorText(6560,16) = <<110, 103, 58, 32, 98, 105, 110, 100, 105, 110, 103, 44, 32, 114, 101, 99>>
    /\ AllocatorText(6576,16) = <<111, 114, 100, 65, 115, 115, 105, 103, 110, 109, 101, 110, 116, 58, 32, 114>>
    /\ AllocatorText(6592,15) = <<101, 99, 111, 114, 100, 83, 99, 104, 101, 100, 117, 108, 101, 100, 44>>

THEOREM ActualAtomicAllocatorBody == RecognizedAllocatorBody
    BY ONLY AllocatorChunk0, AllocatorChunk1, AllocatorChunk2, AllocatorChunk3, AllocatorChunk4, AllocatorChunk5, AllocatorChunk6, AllocatorChunk7, AllocatorChunk8, AllocatorChunk9, AllocatorChunk10, AllocatorChunk11, AllocatorChunk12, AllocatorChunk13, AllocatorChunk14, AllocatorChunk15, AllocatorChunk16, AllocatorChunk17, AllocatorChunk18, AllocatorChunk19, AllocatorChunk20, AllocatorChunk21, AllocatorChunk22, AllocatorChunk23, AllocatorChunk24, AllocatorChunk25, AllocatorChunk26, AllocatorChunk27, AllocatorChunk28, AllocatorChunk29, AllocatorChunk30, PTL DEF RecognizedAllocatorBody

AtomicIncrement == CompilerInputByte[5035] - 48
AtomicPrefix == AllocatorText(4979,9)
THEOREM ActualAtomicAllocatorTokens ==
    /\ AtomicIncrement = 1
    /\ AtomicPrefix = <<95, 95, 97, 116, 111, 109, 105, 99, 95>>
PROOF
<1>one. CompilerInputByte[5035] = 49
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>prefix. \A i \in 1..9 : CompilerInputByte[4979+i-1] = <<95,95,97,116,111,109,105,99,95>>[i]
    BY ONLY CompilerInputPageBlock5AtFileOffsets, SMT
<1>literal. AtomicPrefix = <<95,95,97,116,111,109,105,99,95>>
    BY ONLY <1>prefix, IsaM("simp"), SMT DEF AtomicPrefix,AllocatorText
<1>. QED BY ONLY <1>one,<1>literal,SMT DEF AtomicIncrement
====
