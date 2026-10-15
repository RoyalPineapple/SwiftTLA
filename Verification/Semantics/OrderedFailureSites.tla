-------------------- MODULE OrderedFailureSites --------------------
EXTENDS TLAPS, NaturalsInduction, Sequences

SourcePrefixDefined(guards, prefix) ==
    \A index \in 1..prefix : guards[index]
RenderedHistory(guards, history) ==
    /\ history[0] = TRUE
    /\ \A index \in 1..Len(guards) :
           history[index] =
               IF history[index - 1] THEN guards[index] ELSE FALSE
SourceFailureAt(guards, index) ==
    /\ index \in 1..Len(guards)
    /\ SourcePrefixDefined(guards, index - 1)
    /\ ~guards[index]
RenderedFailureAt(guards, history, index) ==
    /\ index \in 1..Len(guards)
    /\ (IF history[index - 1] THEN ~guards[index] ELSE FALSE)
SourceAnyFailure(guards) ==
    \E index \in 1..Len(guards) : SourceFailureAt(guards, index)

THEOREM AnyOrderedFailureIsExactlyUndefinedness ==
    ASSUME NEW guards \in Seq(BOOLEAN)
    PROVE SourceAnyFailure(guards) <=>
          ~SourcePrefixDefined(guards, Len(guards))
    PROOF
    <1>. DEFINE P(prefix) ==
        prefix \in 0..Len(guards) =>
            ((\E index \in 1..prefix : SourceFailureAt(guards, index))
             <=> ~SourcePrefixDefined(guards, prefix))
    <1>1. P(0)
        BY SMT DEF P, SourcePrefixDefined
    <1>2. ASSUME NEW prefix \in Nat, P(prefix)
          PROVE P(prefix + 1)
        <2>. SUFFICES ASSUME prefix + 1 \in 0..Len(guards)
                     PROVE (\E index \in 1..prefix + 1 :
                                SourceFailureAt(guards, index))
                           <=> ~SourcePrefixDefined(guards, prefix + 1)
            BY SMT DEF P
        <2>1. prefix \in 0..Len(guards)
            BY SMT
        <2>2. SourcePrefixDefined(guards, prefix + 1) =
                 (SourcePrefixDefined(guards, prefix) /\ guards[prefix + 1])
            BY SMT DEF SourcePrefixDefined
        <2>3. SourceFailureAt(guards, prefix + 1) =
                 (SourcePrefixDefined(guards, prefix) /\ ~guards[prefix + 1])
            BY SMT DEF SourceFailureAt
        <2>4. (\E index \in 1..prefix + 1 :
                  SourceFailureAt(guards, index)) =
                 ((\E index \in 1..prefix : SourceFailureAt(guards, index))
                  \/ SourceFailureAt(guards, prefix + 1))
            BY SMT
        <2>. QED
            BY <2>1, <2>2, <2>3, <2>4, P(prefix), SMT DEF P
    <1>3. \A prefix \in Nat : P(prefix)
        BY <1>1, <1>2, NatInduction
    <1>4. QED
        BY <1>3, SMT DEF P, SourceAnyFailure

THEOREM OrderedGuardHistoryPreservesDefinedness ==
    ASSUME NEW guards \in Seq(BOOLEAN),
           NEW history \in [0..Len(guards) -> BOOLEAN],
           RenderedHistory(guards, history)
    PROVE \A index \in 0..Len(guards) :
              history[index] = SourcePrefixDefined(guards, index)
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(guards) =>
            history[index] = SourcePrefixDefined(guards, index)
    <1>1. P(0)
        BY SMT DEF P, RenderedHistory, SourcePrefixDefined
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(guards)
                     PROVE history[index + 1] =
                               SourcePrefixDefined(guards, index + 1)
            BY SMT DEF P
        <2>1. index \in 0..Len(guards)
            BY SMT
        <2>2. history[index + 1] =
                 IF history[index] THEN guards[index + 1] ELSE FALSE
            BY SMT DEF RenderedHistory
        <2>3. SourcePrefixDefined(guards, index + 1) =
                 (SourcePrefixDefined(guards, index) /\ guards[index + 1])
            BY SMT DEF SourcePrefixDefined
        <2>. QED
            BY <2>1, <2>2, <2>3, P(index), SMT DEF P
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>4. QED
        BY <1>3, SMT DEF P

THEOREM EveryRenderedFailureIsTheSourceFirstFailure ==
    ASSUME NEW guards \in Seq(BOOLEAN),
           NEW history \in [0..Len(guards) -> BOOLEAN],
           RenderedHistory(guards, history),
           NEW index \in 1..Len(guards)
    PROVE RenderedFailureAt(guards, history, index)
          <=> SourceFailureAt(guards, index)
    BY OrderedGuardHistoryPreservesDefinedness, SMT
        DEF RenderedFailureAt, SourceFailureAt

RenderedLaterFailure(guards, history, candidate) ==
    IF history[Len(guards)] THEN candidate ELSE FALSE

THEOREM LaterBoundBodyRunsOnlyAfterDefinedValue ==
    ASSUME NEW guards \in Seq(BOOLEAN),
           NEW history \in [0..Len(guards) -> BOOLEAN],
           RenderedHistory(guards, history),
           NEW candidate \in BOOLEAN
    PROVE RenderedLaterFailure(guards, history, candidate)
          <=> SourcePrefixDefined(guards, Len(guards)) /\ candidate
    BY OrderedGuardHistoryPreservesDefinedness, SMT
        DEF RenderedLaterFailure

WrongEagerLaterFailure(guards, candidate) == candidate

THEOREM EagerBodyFailureAfterFailedValueIsRejected ==
    ASSUME NEW guards \in Seq(BOOLEAN),
           NEW history \in [0..Len(guards) -> BOOLEAN],
           RenderedHistory(guards, history),
           Len(guards) > 0,
           ~guards[1]
    PROVE /\ ~RenderedLaterFailure(guards, history, TRUE)
          /\ WrongEagerLaterFailure(guards, TRUE)
    BY OrderedGuardHistoryPreservesDefinedness, SMT
        DEF RenderedLaterFailure, WrongEagerLaterFailure,
            SourcePrefixDefined

======================================================================
