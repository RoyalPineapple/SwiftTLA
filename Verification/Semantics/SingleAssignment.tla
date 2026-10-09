----------------------- MODULE SingleAssignment -----------------------
EXTENDS TLAPS, GeneratedAtomicCopyProofModel
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
