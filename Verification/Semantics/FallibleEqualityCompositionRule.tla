---------------- MODULE FallibleEqualityCompositionRule ----------------
EXTENDS TLAPS

CONSTANTS States, Values, Errors, Actions

Outcomes == [defined: BOOLEAN, value: Values, error: Errors]

EqualityEdges(outcome, right, source, action, write) ==
    IF outcome.defined
    THEN {<<source, action, write[source][outcome.value = right]>>}
    ELSE {}

EqualityFailures(outcome, source, action) ==
    IF outcome.defined
    THEN {}
    ELSE {<<source, action, outcome.error>>}

THEOREM EqualOperandOutcomesPreserveEqualityStepsAndFailures ==
    \A source, native, rendered \in Outcomes :
    \A right \in Values :
    \A write \in [States -> [BOOLEAN -> States]] :
    \A action \in Actions :
    \A state \in States :
        source = native /\ source = rendered
        => /\ EqualityEdges(source, right, state, action, write)
                = EqualityEdges(native, right, state, action, write)
           /\ EqualityEdges(source, right, state, action, write)
                = EqualityEdges(rendered, right, state, action, write)
           /\ EqualityFailures(source, state, action)
                = EqualityFailures(native, state, action)
           /\ EqualityFailures(source, state, action)
                = EqualityFailures(rendered, state, action)
    BY SMT DEF EqualityEdges, EqualityFailures, Outcomes

THEOREM FailedOperandHasNoEqualityEdgeAndRetainsItsFailure ==
    \A outcome \in Outcomes :
    \A right \in Values :
    \A write \in [States -> [BOOLEAN -> States]] :
    \A source \in States :
    \A action \in Actions :
        ~outcome.defined
        => /\ EqualityEdges(outcome, right, source, action, write) = {}
           /\ EqualityFailures(outcome, source, action)
                = {<<source, action, outcome.error>>}
    BY SMT DEF EqualityEdges, EqualityFailures, Outcomes

===============================================================
