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

SourceInequality(left, forbidden) == left # forbidden
RenderedInequality(left, forbidden, prefix) ==
    FormalEncode(left, prefix) # FormalEncode(forbidden, prefix)

THEOREM CompleteStringInequalityAgreement ==
    ASSUME NEW left \in Seq(Byte), NEW forbidden \in Seq(Byte),
           NEW prefix \in Seq(Byte)
    PROVE SourceInequality(left, forbidden)
        <=> RenderedInequality(left, forbidden, prefix)
    BY CompleteFormalByteEncodingIsInjective, SMT
        DEF SourceInequality, RenderedInequality

SourceMixedStep(left, right, expected, forbidden,
                nextLeft, nextRight, nextAdvanced, action) ==
    SourceStep(left, right, expected, nextLeft, nextRight,
               nextAdvanced, action)
        /\ SourceInequality(left, forbidden)
RenderedMixedStep(left, right, expected, forbidden, prefix,
                  nextLeft, nextRight, nextAdvanced, action) ==
    RenderedStep(left, right, expected, prefix, nextLeft, nextRight,
                 nextAdvanced, action)
        /\ RenderedInequality(left, forbidden, prefix)

THEOREM CompleteMixedLabeledStepAgreement ==
    ASSUME NEW left \in Seq(Byte), NEW right \in Seq(Byte),
           NEW expected \in Seq(Byte), NEW forbidden \in Seq(Byte),
           NEW prefix \in Seq(Byte), NEW nextLeft \in Seq(Byte),
           NEW nextRight \in Seq(Byte), NEW nextAdvanced \in BOOLEAN,
           NEW action \in STRING
    PROVE SourceMixedStep(left, right, expected, forbidden,
                          nextLeft, nextRight, nextAdvanced, action)
        <=> RenderedMixedStep(left, right, expected, forbidden, prefix,
                              nextLeft, nextRight, nextAdvanced, action)
    PROOF
    <1>1. SourceGuard(left, right, expected)
              <=> RenderedGuard(left, right, expected, prefix)
        BY CompleteStringGuardAgreement, SMT
    <1>2. SourceInequality(left, forbidden)
              <=> RenderedInequality(left, forbidden, prefix)
        BY CompleteStringInequalityAgreement, SMT
    <1>3. nextLeft = left
              <=> FormalEncode(nextLeft, prefix) = FormalEncode(left, prefix)
        BY CompleteFormalByteEncodingIsInjective, SMT
    <1>4. nextRight = right
              <=> FormalEncode(nextRight, prefix) = FormalEncode(right, prefix)
        BY CompleteFormalByteEncodingIsInjective, SMT
    <1> QED BY <1>1, <1>2, <1>3, <1>4, SMT
        DEF SourceMixedStep, RenderedMixedStep, SourceStep,
            RenderedStep

WrongGuard(left, right, prefix) ==
    FormalEncode(left, prefix) # FormalEncode(right, prefix)

THEOREM InvertedGuardChangesLabeledStep ==
    SourceStep(<<65>>, <<65>>, <<65>>, <<65>>, <<65>>,
               TRUE, "advance")
        /\ ~WrongGuard(<<65>>, <<65>>, <<1>>)
    BY SMT DEF SourceStep, SourceGuard, WrongGuard

=====================================================================
