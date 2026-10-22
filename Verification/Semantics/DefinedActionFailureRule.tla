---------------- MODULE DefinedActionFailureRule ----------------
EXTENDS TLAPS

SourceDefinedStep(defined, value, body) == defined /\ body[value]
RenderedDefinedStep(defined, value, body) ==
    IF defined THEN (LET bound == value IN body[bound]) ELSE FALSE
SourceFirstFailure(defined, value, bodyFails) ==
    IF ~defined THEN "binding"
    ELSE IF bodyFails[value] THEN "body" ELSE "none"
RenderedBindingFailure(defined) == ~defined
RenderedBodyFailure(defined, value, bodyFails) ==
    IF defined THEN (LET bound == value IN bodyFails[bound]) ELSE FALSE
RenderedFirstFailure(defined, value, bodyFails) ==
    IF RenderedBindingFailure(defined) THEN "binding"
    ELSE IF RenderedBodyFailure(defined, value, bodyFails) THEN "body"
    ELSE "none"

THEOREM DefinedActionPreservesStepAndFirstFailure ==
    ASSUME NEW domain, NEW value \in domain,
           NEW body \in [domain -> BOOLEAN],
           NEW defined \in BOOLEAN,
           NEW bodyFails \in [domain -> BOOLEAN]
    PROVE /\ (SourceDefinedStep(defined, value, body)
                <=> RenderedDefinedStep(defined, value, body))
          /\ SourceFirstFailure(defined, value, bodyFails)
                = RenderedFirstFailure(defined, value, bodyFails)
    BY SMT DEF SourceDefinedStep, RenderedDefinedStep,
        SourceFirstFailure, RenderedFirstFailure,
        RenderedBindingFailure, RenderedBodyFailure

SourceLabeledEdges(defined, value, updates, state, label) ==
    IF defined THEN {<<state, label, target>> : target \in updates[value]}
    ELSE {}
RenderedLabeledEdges(defined, value, updates, state, label) ==
    IF defined THEN
        (LET bound == value IN
            {<<state, label, target>> : target \in updates[bound]})
    ELSE {}
SourceCompleteOutcome(defined, value, updates, bodyFails, state, label) ==
    [edges |-> SourceLabeledEdges(defined, value, updates, state, label),
     failure |-> SourceFirstFailure(defined, value, bodyFails)]
RenderedCompleteOutcome(defined, value, updates, bodyFails, state, label) ==
    [edges |-> RenderedLabeledEdges(defined, value, updates, state, label),
     failure |-> RenderedFirstFailure(defined, value, bodyFails)]

THEOREM DefinedActionComposesCompleteLabeledOutcomes ==
    ASSUME NEW States,
           NEW domain,
           NEW sourceValue \in domain,
           NEW renderedValue \in domain,
           NEW sourceDefined \in BOOLEAN,
           NEW renderedDefined \in BOOLEAN,
           sourceDefined = renderedDefined,
           sourceDefined => sourceValue = renderedValue,
           NEW sourceUpdates \in [domain -> SUBSET States],
           NEW renderedUpdates \in [domain -> SUBSET States],
           \A candidate \in domain :
               sourceUpdates[candidate] = renderedUpdates[candidate],
           NEW sourceFailures \in [domain -> BOOLEAN],
           NEW renderedFailures \in [domain -> BOOLEAN],
           \A candidate \in domain :
               sourceFailures[candidate] = renderedFailures[candidate],
           NEW state \in States,
           NEW label
    PROVE SourceCompleteOutcome(sourceDefined, sourceValue,
              sourceUpdates, sourceFailures, state, label)
          = RenderedCompleteOutcome(renderedDefined, renderedValue,
              renderedUpdates, renderedFailures, state, label)
    BY SMT DEF SourceCompleteOutcome, RenderedCompleteOutcome,
        SourceLabeledEdges, RenderedLabeledEdges,
        SourceFirstFailure, RenderedFirstFailure,
        RenderedBindingFailure, RenderedBodyFailure

DroppedBodyFailure(defined) ==
    IF ~defined THEN "binding" ELSE "none"

THEOREM OmittingBoundBodyFailureIsRejected ==
    SourceFirstFailure(TRUE, 0, [x \in {0} |-> TRUE])
        # DroppedBodyFailure(TRUE)
    BY SMT DEF SourceFirstFailure, DroppedBodyFailure

=================================================================
