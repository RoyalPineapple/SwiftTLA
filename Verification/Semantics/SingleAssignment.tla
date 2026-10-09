----------------------- MODULE SingleAssignment -----------------------
EXTENDS TLAPS, NaturalsInduction, SequenceTheorems, GeneratedAtomicCopyProofModel
VARIABLE choiceSelected
Choice == INSTANCE GeneratedGuardedChoiceProofModel WITH selected <- choiceSelected
CONSTANTS Vars, Values, Key, ActionLabels
ASSUME KeyIsVariable == Key \in Vars

States == [Vars -> Values]
LabeledEdges == States \X ActionLabels \X States

ChoiceEdges(domain, branches) == UNION {branches[value] : value \in domain}
GuardEdges(enabled, edges) == IF enabled THEN edges ELSE {}
EnabledIn(edges, state, action) ==
    \E successor \in States : <<state, action, successor>> \in edges

THEOREM GuardedChoiceComposition ==
    \A domain \in SUBSET Values :
        \A source, rendered \in [domain -> SUBSET LabeledEdges] :
            (\A value \in domain : source[value] = rendered[value]) =>
                \A guard \in BOOLEAN :
                    GuardEdges(guard, ChoiceEdges(domain, source))
                    = GuardEdges(guard, ChoiceEdges(domain, rendered))
    BY SMT DEF GuardEdges, ChoiceEdges, LabeledEdges, States

THEOREM GuardedChoiceEnabledness ==
    \A domain \in SUBSET Values :
        \A source, rendered \in [domain -> SUBSET LabeledEdges] :
            (\A value \in domain : source[value] = rendered[value]) =>
                \A guard \in BOOLEAN, state \in States, action \in ActionLabels :
                    EnabledIn(GuardEdges(guard, ChoiceEdges(domain, source)), state, action)
                    <=> EnabledIn(GuardEdges(guard, ChoiceEdges(domain, rendered)), state, action)
    BY GuardedChoiceComposition, SMT DEF EnabledIn

ApplyDelta(s, keys, delta) ==
    [key \in Vars |-> IF key \in keys THEN delta[key] ELSE s[key]]

RenderedDelta(s, t, keys, delta) ==
    /\ \A key \in keys : t[key] = delta[key]
    /\ \A key \in Vars \ keys : t[key] = s[key]

THEOREM CompleteDeltaUpdate ==
    \A keys \in SUBSET Vars :
        \A s, t \in States :
            \A delta \in [keys -> Values] :
                (t = ApplyDelta(s, keys, delta)) <=> RenderedDelta(s, t, keys, delta)
    BY SMT DEF ApplyDelta, RenderedDelta, States

Instructions == [target: Vars, rhs: [States -> Values]]
AdvanceSource(current, instruction) ==
    [current EXCEPT ![instruction.target] = instruction.rhs[current]]
AdvanceSchedule(original, keys, values, instruction) ==
    LET current == ApplyDelta(original, keys, values)
        updated == instruction.rhs[current]
    IN  ApplyDelta(original, keys \cup {instruction.target},
            [values EXCEPT ![instruction.target] = updated])

THEOREM EmptySchedule ==
    \A original \in States : ApplyDelta(original, {}, original) = original
    BY SMT DEF ApplyDelta, States

THEOREM OrderedScheduleStep ==
    \A original, values \in States :
        \A keys \in SUBSET Vars :
            \A instruction \in Instructions :
                AdvanceSource(ApplyDelta(original, keys, values), instruction)
                = AdvanceSchedule(original, keys, values, instruction)
    BY SMT DEF AdvanceSource, AdvanceSchedule, ApplyDelta, Instructions, States

ScheduledRecords == [keys: SUBSET Vars, values: States]
AdvanceScheduleRecord(original, prior, instruction) ==
    LET current == ApplyDelta(original, prior.keys, prior.values)
    IN [keys |-> prior.keys \cup {instruction.target},
        values |-> [prior.values EXCEPT ![instruction.target] = instruction.rhs[current]]]

SourceHistory(original, steps, history) ==
    /\ history[0] = original
    /\ \A index \in 1..Len(steps) :
        history[index] = AdvanceSource(history[index - 1], steps[index])

ScheduledHistory(original, steps, history) ==
    /\ history[0] = [keys |-> {}, values |-> original]
    /\ \A index \in 1..Len(steps) :
        history[index] = AdvanceScheduleRecord(original, history[index - 1], steps[index])

THEOREM OrderedHistoryStep ==
    \A original \in States :
        \A prior \in ScheduledRecords :
            \A instruction \in Instructions :
                AdvanceSource(ApplyDelta(original, prior.keys, prior.values), instruction)
                = ApplyDelta(original,
                    AdvanceScheduleRecord(original, prior, instruction).keys,
                    AdvanceScheduleRecord(original, prior, instruction).values)
    BY OrderedScheduleStep, SMT DEF AdvanceScheduleRecord, AdvanceSchedule,
        ScheduledRecords, Instructions, States

HistoryAgrees(original, source, scheduled, index) ==
    source[index] = ApplyDelta(original, scheduled[index].keys, scheduled[index].values)

THEOREM OrderedHistoriesAgree ==
    ASSUME NEW original \in States,
           NEW steps \in Seq(Instructions),
           NEW source \in [0..Len(steps) -> States],
           NEW scheduled \in [0..Len(steps) -> ScheduledRecords],
           SourceHistory(original, steps, source),
           ScheduledHistory(original, steps, scheduled)
    PROVE  \A index \in 0..Len(steps) :
               HistoryAgrees(original, source, scheduled, index)
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(steps) => HistoryAgrees(original, source, scheduled, index)
    <1>1. P(0)
        BY EmptySchedule, SMT DEF P, HistoryAgrees, SourceHistory, ScheduledHistory
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(steps)
                     PROVE HistoryAgrees(original, source, scheduled, index + 1)
            BY SMT DEF P
        <2>1. index \in 0..Len(steps)
            BY P(index), SMT DEF P
        <2>2. steps[index + 1] \in Instructions
            BY LenProperties, SMT
        <2>3. scheduled[index] \in ScheduledRecords
            BY <2>1, SMT
        <2>4. HistoryAgrees(original, source, scheduled, index)
            BY <2>1, P(index), SMT DEF P
        <2>5. source[index + 1] = AdvanceSource(source[index], steps[index + 1])
            BY SMT DEF SourceHistory
        <2>6. scheduled[index + 1] =
                 AdvanceScheduleRecord(original, scheduled[index], steps[index + 1])
            BY SMT DEF ScheduledHistory
        <2>. QED
            BY <2>2, <2>3, <2>4, <2>5, <2>6, OrderedHistoryStep,
                SMT DEF HistoryAgrees
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>4. QED
        BY <1>3, SMT DEF P

ExtendSourceHistory(history, length, instruction) ==
    [index \in 0..(length + 1) |->
        IF index = length + 1
        THEN AdvanceSource(history[length], instruction)
        ELSE history[index]]

ExtendScheduledHistory(original, history, length, instruction) ==
    [index \in 0..(length + 1) |->
        IF index = length + 1
        THEN AdvanceScheduleRecord(original, history[length], instruction)
        ELSE history[index]]

HistoriesExist(original, steps) ==
    \E source \in [0..Len(steps) -> States] :
        \E scheduled \in [0..Len(steps) -> ScheduledRecords] :
            SourceHistory(original, steps, source)
            /\ ScheduledHistory(original, steps, scheduled)

THEOREM OrderedHistoriesExist ==
    ASSUME NEW original \in States
    PROVE \A steps \in Seq(Instructions) : HistoriesExist(original, steps)
    PROOF
    <1>1. HistoriesExist(original, <<>>)
        <2>. DEFINE emptySource == [index \in 0..0 |-> original]
                    emptyScheduled ==
                        [index \in 0..0 |-> [keys |-> {}, values |-> original]]
        <2>1. emptySource \in [0..Len(<<>>) -> States]
            BY SMT DEF emptySource
        <2>2. emptyScheduled \in [0..Len(<<>>) -> ScheduledRecords]
            BY SMT DEF emptyScheduled, ScheduledRecords
        <2>3. SourceHistory(original, <<>>, emptySource)
            BY SMT DEF SourceHistory, emptySource
        <2>4. ScheduledHistory(original, <<>>, emptyScheduled)
            BY SMT DEF ScheduledHistory, emptyScheduled
        <2>. QED
            BY <2>1, <2>2, <2>3, <2>4, SMT DEF HistoriesExist
    <1>2. ASSUME NEW prior \in Seq(Instructions),
                  NEW instruction \in Instructions,
                  HistoriesExist(original, prior)
          PROVE HistoriesExist(original, Append(prior, instruction))
        <2>1. PICK source \in [0..Len(prior) -> States],
                    scheduled \in [0..Len(prior) -> ScheduledRecords] :
                    SourceHistory(original, prior, source)
                    /\ ScheduledHistory(original, prior, scheduled)
            BY HistoriesExist(original, prior) DEF HistoriesExist
        <2>2. AdvanceSource(source[Len(prior)], instruction) \in States
            BY <2>1, SMT DEF AdvanceSource, Instructions, States
        <2>3. AdvanceScheduleRecord(original, scheduled[Len(prior)], instruction)
            \in ScheduledRecords
            BY <2>1, SMT DEF AdvanceScheduleRecord, ScheduledRecords,
                Instructions, ApplyDelta, States
        <2>4. ExtendSourceHistory(source, Len(prior), instruction)
            \in [0..Len(Append(prior, instruction)) -> States]
            BY <2>1, <2>2, AppendProperties, SMT DEF ExtendSourceHistory
        <2>5. ExtendScheduledHistory(original, scheduled, Len(prior), instruction)
            \in [0..Len(Append(prior, instruction)) -> ScheduledRecords]
            BY <2>1, <2>3, AppendProperties, SMT DEF ExtendScheduledHistory
        <2>6. SourceHistory(original, Append(prior, instruction),
                 ExtendSourceHistory(source, Len(prior), instruction))
            BY <2>1, AppendProperties, SMT DEF SourceHistory,
                ExtendSourceHistory
        <2>7. ScheduledHistory(original, Append(prior, instruction),
                 ExtendScheduledHistory(original, scheduled, Len(prior), instruction))
            <3>1. \A index \in 0..Len(prior) :
                    ExtendScheduledHistory(original, scheduled, Len(prior), instruction)[index]
                    = scheduled[index]
                BY SMT DEF ExtendScheduledHistory
            <3>2. ExtendScheduledHistory(original, scheduled, Len(prior), instruction)
                    [Len(prior) + 1]
                    = AdvanceScheduleRecord(original, scheduled[Len(prior)], instruction)
                BY SMT DEF ExtendScheduledHistory
            <3>. QED
                BY <2>1, <3>1, <3>2, AppendProperties,
                    SMT DEF ScheduledHistory
        <2>. QED
            BY <2>4, <2>5, <2>6, <2>7 DEF HistoriesExist
    <1>3. QED
        BY <1>1, <1>2, SequencesInductionAppend

THEOREM OrderedDoPreservation ==
    ASSUME NEW original \in States
    PROVE \A steps \in Seq(Instructions) :
        \E source \in [0..Len(steps) -> States] :
            \E scheduled \in [0..Len(steps) -> ScheduledRecords] :
                /\ SourceHistory(original, steps, source)
                /\ ScheduledHistory(original, steps, scheduled)
                /\ \A index \in 0..Len(steps) :
                    HistoryAgrees(original, source, scheduled, index)
    BY OrderedHistoriesExist, OrderedHistoriesAgree,
        SMT DEF HistoriesExist

MergeCompatible(firstKeys, first, secondKeys, second) ==
    [key \in firstKeys \cup secondKeys |->
        IF key \in firstKeys THEN first[key] ELSE second[key]]

Compatible(firstKeys, first, secondKeys, second) ==
    \A key \in firstKeys \cap secondKeys : first[key] = second[key]

RenderedConjunction(s, t, firstKeys, first, secondKeys, second) ==
    /\ \A key \in firstKeys : t[key] = first[key]
    /\ \A key \in secondKeys : t[key] = second[key]
    /\ \A key \in Vars \ (firstKeys \cup secondKeys) : t[key] = s[key]

THEOREM CompatibleConjunction ==
    \A firstKeys, secondKeys \in SUBSET Vars :
        \A s, t \in States :
            \A first \in [firstKeys -> Values] :
                \A second \in [secondKeys -> Values] :
                    Compatible(firstKeys, first, secondKeys, second) =>
                        (t = ApplyDelta(s, firstKeys \cup secondKeys,
                            MergeCompatible(firstKeys, first, secondKeys, second)))
                        <=> RenderedConjunction(s, t, firstKeys, first, secondKeys, second)
    BY SMT DEF ApplyDelta, MergeCompatible, Compatible, RenderedConjunction, States

THEOREM ConflictingConjunctionHasNoSuccessor ==
    \A firstKeys, secondKeys \in SUBSET Vars :
        \A s, t \in States :
            \A first \in [firstKeys -> Values] :
                \A second \in [secondKeys -> Values] :
                    ~Compatible(firstKeys, first, secondKeys, second)
                    => ~RenderedConjunction(s, t, firstKeys, first, secondKeys, second)
    BY SMT DEF Compatible, RenderedConjunction, States

\* The generated Swift machine replaces one value in a complete state.
NativeStep(s, t, guard, value) ==
    /\ guard
    /\ t = [s EXCEPT ![Key] = value]

\* The rendered TLA+ action assigns the target and leaves every other
\* model variable unchanged.
RenderedStep(s, t, guard, value) ==
    /\ guard
    /\ t[Key] = value
    /\ \A other \in Vars \ {Key} : t[other] = s[other]

THEOREM ForwardUpdate ==
    \A s, t \in States, value \in Values, guard \in BOOLEAN :
        NativeStep(s, t, guard, value)
        => RenderedStep(s, t, guard, value)
    BY KeyIsVariable, SMT DEF NativeStep, RenderedStep, States

THEOREM ReverseUpdate ==
    \A s, t \in States, value \in Values, guard \in BOOLEAN :
        RenderedStep(s, t, guard, value)
        => NativeStep(s, t, guard, value)
    BY KeyIsVariable, SMT DEF NativeStep, RenderedStep, States

THEOREM CompleteStateUpdate ==
    \A s, t \in States, value \in Values, guard \in BOOLEAN :
        NativeStep(s, t, guard, value)
        <=> RenderedStep(s, t, guard, value)
    BY ForwardUpdate, ReverseUpdate

THEOREM EnabledUpdate ==
    \A s \in States, value \in Values, guard \in BOOLEAN :
        (\E t \in States : NativeStep(s, t, guard, value))
        <=> (\E t \in States : RenderedStep(s, t, guard, value))
    BY CompleteStateUpdate, SMT DEF NativeStep, RenderedStep, States

NativeParallelStep(s, t, guard, first, firstValue, second, secondValue) ==
    /\ guard
    /\ first # second
    /\ t = [s EXCEPT ![first] = firstValue, ![second] = secondValue]

RenderedParallelStep(s, t, guard, first, firstValue, second, secondValue) ==
    /\ guard
    /\ first # second
    /\ t[first] = firstValue
    /\ t[second] = secondValue
    /\ \A other \in Vars \ {first, second} : t[other] = s[other]

THEOREM ParallelUpdate ==
    \A s, t \in States, guard \in BOOLEAN,
       first, second \in Vars, firstValue, secondValue \in Values :
        NativeParallelStep(s, t, guard, first, firstValue, second, secondValue)
        <=> RenderedParallelStep(s, t, guard, first, firstValue, second, secondValue)
    BY SMT DEF NativeParallelStep, RenderedParallelStep, States

SourceOrderedCopy ==
    /\ first' = second
    /\ second' = second

SourceSequentialCopy ==
    LET before == [first |-> first, second |-> second]
        afterFirst == [before EXCEPT !.first = before.second]
        afterSecond == [afterFirst EXCEPT !.second = afterFirst.first]
    IN  /\ first' = afterSecond.first
        /\ second' = afterSecond.second

THEOREM OrderedCopySemantics ==
    SourceSequentialCopy <=> SourceOrderedCopy
    BY SMT DEF SourceSequentialCopy, SourceOrderedCopy

SourceInitialCopyState ==
    /\ first = 0
    /\ second = 1

THEOREM EmittedCopyInitialState ==
    Init <=> SourceInitialCopyState
    BY SMT DEF Init, SourceInitialCopyState

THEOREM EmittedCopyStep ==
    copy <=> SourceOrderedCopy
    BY SMT DEF copy, SourceOrderedCopy

THEOREM EmittedCopyNext ==
    Next <=> SourceOrderedCopy
    BY EmittedCopyStep DEF Next

THEOREM EmittedCopyPreservesSourceOrder ==
    Next <=> SourceSequentialCopy
    BY EmittedCopyNext, OrderedCopySemantics

SourceGuardedChoice ==
    /\ choiceSelected = 0
    /\ (choiceSelected' = 1 \/ choiceSelected' = 2)

THEOREM EmittedGuardedChoiceInitialState ==
    Choice!Init <=> choiceSelected = 0
    BY SMT DEF Choice!Init

THEOREM EmittedGuardedChoiceStep ==
    Choice!choose <=> SourceGuardedChoice
    BY SMT DEF Choice!choose, SourceGuardedChoice

THEOREM EmittedGuardedChoiceNext ==
    Choice!Next <=> SourceGuardedChoice
    BY EmittedGuardedChoiceStep DEF Choice!Next

THEOREM GuardedChoiceDisabledAfterSelection ==
    choiceSelected # 0 => ~Choice!choose
    BY EmittedGuardedChoiceStep, SMT DEF SourceGuardedChoice
=======================================================================
