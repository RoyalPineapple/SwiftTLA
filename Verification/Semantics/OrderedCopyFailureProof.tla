------------------ MODULE OrderedCopyFailureProof ------------------
EXTENDS TLAPS, Integers, Sequences

CONSTANTS SwiftIntMin, SwiftIntMax
VARIABLES pc, x, y
Emitted == INSTANCE OrderedCopy
    WITH OrderedIntMin <- SwiftIntMin, OrderedIntMax <- SwiftIntMax
Rule == INSTANCE OrderedFailureSites

SwiftIntBounds ==
    /\ SwiftIntMin \in Int
    /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= -2000000000
    /\ 2000000000 <= SwiftIntMax
ASSUME SwiftIntBounds

SourceAddDefined(value) == value <= SwiftIntMax - 1
RenderedAddDefined(value) ==
    IF value >= -1000000000 /\ value <= 1000000000
    THEN TRUE
    ELSE IF 1 > 0 THEN value <= SwiftIntMax - 1
    ELSE IF 1 < 0 THEN value >= SwiftIntMin - 1
    ELSE TRUE
SourceRepeatGuards == <<SourceAddDefined(x), SourceAddDefined(x + 1)>>
SourceCopyFailure == pc = "copy" /\ ~SourceAddDefined(x)
SourceRepeatFailureAt(index) ==
    pc = "repeatWrites" /\ Rule!SourceFailureAt(SourceRepeatGuards, index)
SourceAnyFailure ==
    SourceCopyFailure \/
    (pc = "repeatWrites" /\ Rule!SourceAnyFailure(SourceRepeatGuards))
SourceEvaluationOK == ~SourceAnyFailure

THEOREM RenderedAddDefinedMatchesSource ==
    ASSUME NEW value \in Int
    PROVE RenderedAddDefined(value) <=> SourceAddDefined(value)
    PROOF
    <1>1. value <= 1000000000 => SourceAddDefined(value)
        BY SwiftIntBounds, SMT DEF SwiftIntBounds, SourceAddDefined
    <1>. QED BY <1>1, SMT DEF RenderedAddDefined, SourceAddDefined

THEOREM RepeatedFailureUsesOrderedSiteRule ==
    ASSUME x \in Int
    PROVE Rule!SourceAnyFailure(SourceRepeatGuards)
          <=> ~(SourceAddDefined(x) /\ SourceAddDefined(x + 1))
    PROOF
    <1>1. SourceRepeatGuards \in Seq(BOOLEAN)
        BY SwiftIntBounds, SMT
            DEF SwiftIntBounds, SourceRepeatGuards, SourceAddDefined
    <1>2. Rule!SourceAnyFailure(SourceRepeatGuards)
            <=> ~Rule!SourcePrefixDefined(
                SourceRepeatGuards, Len(SourceRepeatGuards))
        BY <1>1, Rule!AnyOrderedFailureIsExactlyUndefinedness
    <1>. QED BY <1>2, SMT
        DEF SourceRepeatGuards, Rule!SourcePrefixDefined

THEOREM CopyFailureMatchesSource ==
    ASSUME x \in Int
    PROVE /\ (Emitted!__SwiftTLAOverflowFailure0 <=> SourceCopyFailure)
          /\ (Emitted!__SwiftTLAAnyEvaluationFailure0 <=> SourceCopyFailure)
    BY RenderedAddDefinedMatchesSource, SMT
        DEF Emitted!__SwiftTLAOverflowFailure0,
            Emitted!__SwiftTLAAnyEvaluationFailure0,
            SourceCopyFailure, RenderedAddDefined

THEOREM RepeatFailuresMatchSourceOrder ==
    ASSUME x \in Int
    PROVE /\ (Emitted!__SwiftTLAOverflowFailure1
                <=> SourceRepeatFailureAt(1))
          /\ (Emitted!__SwiftTLAOverflowFailure1_1
                <=> SourceRepeatFailureAt(2))
    PROOF
    <1>1. x + 1 \in Int BY SMT
    <1>2. RenderedAddDefined(x) <=> SourceAddDefined(x)
        BY RenderedAddDefinedMatchesSource
    <1>3. RenderedAddDefined(x + 1) <=> SourceAddDefined(x + 1)
        BY <1>1, RenderedAddDefinedMatchesSource
    <1>. QED BY <1>2, <1>3, SMT
        DEF Emitted!__SwiftTLAOverflowFailure1,
            Emitted!__SwiftTLAOverflowFailure1_1,
            SourceRepeatFailureAt, Rule!SourceFailureAt,
            Rule!SourcePrefixDefined, SourceRepeatGuards,
            RenderedAddDefined

THEOREM RepeatAggregateMatchesSource ==
    ASSUME x \in Int
    PROVE Emitted!__SwiftTLAAnyEvaluationFailure1
          <=> pc = "repeatWrites" /\ Rule!SourceAnyFailure(SourceRepeatGuards)
    PROOF
    <1>1. x + 1 \in Int BY SMT
    <1>2. RenderedAddDefined(x) <=> SourceAddDefined(x)
        BY RenderedAddDefinedMatchesSource
    <1>3. RenderedAddDefined(x + 1) <=> SourceAddDefined(x + 1)
        BY <1>1, RenderedAddDefinedMatchesSource
    <1>. QED BY <1>2, <1>3, SMT
        DEF Emitted!__SwiftTLAAnyEvaluationFailure1,
            Rule!SourceAnyFailure, Rule!SourceFailureAt,
            Rule!SourcePrefixDefined, SourceRepeatGuards,
            RenderedAddDefined

THEOREM AggregateEqualsDetailedFailures ==
    ASSUME x \in Int
    PROVE /\ (Emitted!__SwiftTLAAnyEvaluationFailure0
                 <=> Emitted!__SwiftTLAOverflowFailure0)
          /\ (Emitted!__SwiftTLAAnyEvaluationFailure1
                 <=> (Emitted!__SwiftTLAOverflowFailure1
                      \/ Emitted!__SwiftTLAOverflowFailure1_1))
    BY CopyFailureMatchesSource, RepeatFailuresMatchSourceOrder,
        RepeatAggregateMatchesSource, SMT
        DEF Rule!SourceAnyFailure, SourceRepeatFailureAt,
            SourceRepeatGuards

THEOREM EvaluationCheckMatchesSource ==
    ASSUME x \in Int
    PROVE Emitted!__SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY CopyFailureMatchesSource, RepeatAggregateMatchesSource, SMT
        DEF Emitted!__SwiftTLAEvaluationOK, SourceEvaluationOK,
            SourceAnyFailure

WrongFirstOnlyFailure ==
    SourceCopyFailure \/ SourceRepeatFailureAt(1)

THEOREM DroppingSecondWriteFailureChangesCheck ==
    ASSUME pc = "repeatWrites", x = SwiftIntMax - 1
    PROVE /\ ~WrongFirstOnlyFailure
          /\ SourceAnyFailure
          /\ Emitted!__SwiftTLAAnyEvaluationFailure1
          /\ ~Emitted!__SwiftTLAEvaluationOK
    PROOF
    <1>1. x \in Int
        BY SwiftIntBounds, SMT DEF SwiftIntBounds
    <1>2. ~WrongFirstOnlyFailure /\ SourceAnyFailure
        BY SwiftIntBounds, SMT
            DEF SwiftIntBounds, WrongFirstOnlyFailure,
                SourceAnyFailure, SourceCopyFailure, SourceRepeatFailureAt,
                Rule!SourceAnyFailure, Rule!SourceFailureAt,
                Rule!SourcePrefixDefined, SourceRepeatGuards,
                SourceAddDefined
    <1>3. pc = "repeatWrites" /\ Rule!SourceAnyFailure(SourceRepeatGuards)
        BY <1>2, SMT DEF SourceAnyFailure, SourceCopyFailure
    <1>4. Emitted!__SwiftTLAAnyEvaluationFailure1
        BY <1>1, <1>3, RepeatAggregateMatchesSource
    <1>5. ~Emitted!__SwiftTLAEvaluationOK
        BY <1>1, <1>2, EvaluationCheckMatchesSource,
            SMT DEF SourceEvaluationOK
    <1>. QED BY <1>2, <1>4, <1>5

=====================================================================
