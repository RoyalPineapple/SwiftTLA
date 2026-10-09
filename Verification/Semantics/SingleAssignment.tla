----------------------- MODULE SingleAssignment -----------------------
EXTENDS TLAPS
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
=======================================================================
