---------------- MODULE FormalStringEqualityGuardRule ----------------
EXTENDS TLAPS, FormalStringByteEncodingRule

SourceGuard(left, right, expected) ==
    left = right /\ right = expected
RenderedGuard(left, right, expected, prefix) ==
    FormalEncode(left, prefix) = FormalEncode(right, prefix)
        /\ FormalEncode(right, prefix) = FormalEncode(expected, prefix)

THEOREM CompleteStringGuardAgreement ==
    ASSUME NEW left \in Seq(Byte), NEW right \in Seq(Byte),
           NEW expected \in Seq(Byte), NEW prefix \in Seq(Byte)
    PROVE SourceGuard(left, right, expected)
        <=> RenderedGuard(left, right, expected, prefix)
    PROOF
    <1>1. FormalEncode(left, prefix) = FormalEncode(right, prefix)
              => left = right
        BY CompleteFormalByteEncodingIsInjective, SMT
    <1>2. FormalEncode(right, prefix) = FormalEncode(expected, prefix)
              => right = expected
        BY CompleteFormalByteEncodingIsInjective, SMT
    <1> QED BY <1>1, <1>2, SMT
        DEF SourceGuard, RenderedGuard

SourceStep(left, right, expected, nextLeft, nextRight,
           nextAdvanced, action) ==
    /\ SourceGuard(left, right, expected)
    /\ action = "advance"
    /\ nextLeft = left
    /\ nextRight = right
    /\ nextAdvanced = TRUE
RenderedStep(left, right, expected, prefix, nextLeft, nextRight,
             nextAdvanced, action) ==
    /\ RenderedGuard(left, right, expected, prefix)
    /\ action = "advance"
    /\ FormalEncode(nextLeft, prefix) = FormalEncode(left, prefix)
    /\ FormalEncode(nextRight, prefix) = FormalEncode(right, prefix)
    /\ nextAdvanced = TRUE

THEOREM CompleteLabeledStepAgreement ==
    ASSUME NEW left \in Seq(Byte), NEW right \in Seq(Byte),
           NEW expected \in Seq(Byte), NEW prefix \in Seq(Byte),
           NEW nextLeft \in Seq(Byte), NEW nextRight \in Seq(Byte),
           NEW nextAdvanced \in BOOLEAN,
           NEW action \in STRING
    PROVE SourceStep(left, right, expected, nextLeft, nextRight,
                     nextAdvanced, action)
        <=> RenderedStep(left, right, expected, prefix,
                         nextLeft, nextRight, nextAdvanced, action)
    PROOF
    <1>1. FormalEncode(nextLeft, prefix) = FormalEncode(left, prefix)
              => nextLeft = left
        BY CompleteFormalByteEncodingIsInjective, SMT
    <1>2. FormalEncode(nextRight, prefix) = FormalEncode(right, prefix)
              => nextRight = right
        BY CompleteFormalByteEncodingIsInjective, SMT
    <1> QED BY <1>1, <1>2, CompleteStringGuardAgreement, SMT
        DEF SourceStep, RenderedStep

WrongGuard(left, right, prefix) ==
    FormalEncode(left, prefix) # FormalEncode(right, prefix)

THEOREM InvertedGuardChangesLabeledStep ==
    SourceStep(<<65>>, <<65>>, <<65>>, <<65>>, <<65>>,
               TRUE, "advance")
        /\ ~WrongGuard(<<65>>, <<65>>, <<1>>)
    BY SMT DEF SourceStep, SourceGuard, WrongGuard

=====================================================================
