---------------- MODULE SequenceExpressionConstructorRules ----------------
EXTENDS TLAPS, SequenceTheorems_proofs

CONSTANTS Elements, FailureValues, NoFailure
ASSUME FailureDomain == NoFailure \notin FailureValues

ActionOutcomes == INSTANCE ActionOutcomeInterface WITH UpdateValues <- Seq(Elements)

SequenceOutcomes ==
    {outcome \in [defined: BOOLEAN, value: Seq(Elements),
                  firstFailure: FailureValues \cup {NoFailure}] :
        /\ (outcome.defined <=> outcome.firstFailure = NoFailure)
        /\ (~outcome.defined => outcome.value = <<>>)}
ElementOutcomes ==
    {outcome \in [defined: BOOLEAN, value: Elements,
                  firstFailure: FailureValues \cup {NoFailure}] :
        outcome.defined <=> outcome.firstFailure = NoFailure}
Success(value) == [defined |-> TRUE, value |-> value, firstFailure |-> NoFailure]
Failed(failure) == [defined |-> FALSE, value |-> <<>>, firstFailure |-> failure]

SourceAppendValue(sequence, element) ==
    [index \in 1..(Len(sequence) + 1) |->
        IF index <= Len(sequence) THEN sequence[index] ELSE element]
SourceConcatValue(left, right) ==
    [index \in 1..(Len(left) + Len(right)) |->
        IF index <= Len(left) THEN left[index] ELSE right[index - Len(left)]]

SourceAppend(sequence, element) ==
    IF ~sequence.defined THEN sequence
    ELSE IF ~element.defined THEN Failed(element.firstFailure)
    ELSE Success(SourceAppendValue(sequence.value, element.value))
GeneratedAppend(sequence, element) ==
    IF sequence.firstFailure # NoFailure THEN Failed(sequence.firstFailure)
    ELSE IF element.firstFailure # NoFailure THEN Failed(element.firstFailure)
    ELSE Success(Append(sequence.value, element.value))
SourceConcat(left, right) ==
    IF ~left.defined THEN left
    ELSE IF ~right.defined THEN right
    ELSE Success(SourceConcatValue(left.value, right.value))
GeneratedConcat(left, right) ==
    IF left.firstFailure # NoFailure THEN Failed(left.firstFailure)
    ELSE IF right.firstFailure # NoFailure THEN Failed(right.firstFailure)
    ELSE Success(left.value \o right.value)

THEOREM AppendRetainsEveryIndex ==
    ASSUME NEW sequence \in Seq(Elements), NEW element \in Elements
    PROVE SourceAppendValue(sequence, element) = Append(sequence, element)
    BY SMT DEF SourceAppendValue

THEOREM ConcatenationRetainsEveryIndex ==
    ASSUME NEW left \in Seq(Elements), NEW right \in Seq(Elements)
    PROVE SourceConcatValue(left, right) = left \o right
    BY ConcatProperties, SeqEqual, IsASeq, SMT DEF SourceConcatValue

THEOREM AppendRetainsValueAndFirstFailure ==
    ASSUME NEW sequence \in SequenceOutcomes, NEW element \in ElementOutcomes
    PROVE /\ SourceAppend(sequence, element) = GeneratedAppend(sequence, element)
          /\ SourceAppend(sequence, element) \in SequenceOutcomes
    BY AppendRetainsEveryIndex, AppendProperties, IsASeq, SMT
        DEF SourceAppend, GeneratedAppend, SequenceOutcomes, ElementOutcomes, Success, Failed

THEOREM ConcatenationRetainsValueAndFirstFailure ==
    ASSUME NEW left \in SequenceOutcomes, NEW right \in SequenceOutcomes
    PROVE /\ SourceConcat(left, right) = GeneratedConcat(left, right)
          /\ SourceConcat(left, right) \in SequenceOutcomes
    PROOF
    <1>1. CASE ~left.defined
        BY <1>1, SMT DEF SourceConcat, GeneratedConcat, SequenceOutcomes, Failed
    <1>2. CASE left.defined /\ ~right.defined
        BY <1>2, SMT DEF SourceConcat, GeneratedConcat, SequenceOutcomes, Failed
    <1>3. CASE left.defined /\ right.defined
        <2>1. left.value \in Seq(Elements) /\ right.value \in Seq(Elements)
            BY SMT DEF SequenceOutcomes
        <2>2. SourceConcatValue(left.value, right.value) = left.value \o right.value
            BY <2>1, ConcatenationRetainsEveryIndex
        <2>3. left.value \o right.value \in Seq(Elements)
            BY <2>1, ConcatProperties
        <2>. QED BY <1>3, <2>2, <2>3, SMT
            DEF SourceConcat, GeneratedConcat, SequenceOutcomes, Success
    <1>. QED BY <1>1, <1>2, <1>3, SMT

THEOREM EarlierFailureSuppressesTheLaterChild ==
    ASSUME NEW first \in FailureValues, NEW second \in FailureValues, first # second
    PROVE /\ GeneratedConcat(Failed(first), Failed(second)) = Failed(first)
          /\ GeneratedConcat(Failed(first), Failed(second)) # Failed(second)
    BY FailureDomain, SMT DEF FailureDomain, GeneratedConcat, Failed

THEOREM ReversingDistinctSingletonsChangesTheResult ==
    ASSUME NEW first \in Elements, NEW second \in Elements, first # second
    PROVE GeneratedConcat(Success(<<first>>), Success(<<second>>))
            # GeneratedConcat(Success(<<second>>), Success(<<first>>))
    BY ConcatProperties, SMT DEF GeneratedConcat, Success

THEOREM OmittingTheAppendedElementChangesTheResult ==
    ASSUME NEW sequence \in Seq(Elements), NEW element \in Elements
    PROVE GeneratedAppend(Success(sequence),
              [defined |-> TRUE, value |-> element, firstFailure |-> NoFailure])
            # Success(sequence)
    BY AppendProperties, SMT DEF GeneratedAppend, Success

SequenceProjection(outcome) ==
    [updates |-> IF outcome.defined THEN <<outcome.value>> ELSE <<>>,
     failure |-> outcome.firstFailure]

THEOREM ProjectionRetainsTheCompleteSelectedFailure ==
    ASSUME NEW outcome \in SequenceOutcomes
    PROVE /\ SequenceProjection(outcome) \in ActionOutcomes!OrderedOutcome
          /\ SequenceProjection(outcome).failure = outcome.firstFailure
          /\ (~outcome.defined => SequenceProjection(outcome).updates = <<>>)
    BY IsASeq, SMT DEF SequenceProjection, SequenceOutcomes, ActionOutcomes!OrderedOutcome

=============================================================================
