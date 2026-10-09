----------------------- MODULE SingleAssignment -----------------------
EXTENDS TLAPS, GeneratedAtomicCopyProofModel
CONSTANTS Vars, Values, Key
ASSUME KeyIsVariable == Key \in Vars

States == [Vars -> Values]

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
=======================================================================
